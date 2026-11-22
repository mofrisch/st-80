import Foundation

public enum UIElementKind: String, Sendable {
    case label, button, textField, column, row, spacer
}

/// Immutable native projection. Smalltalk objects and blocks stay on the worker.
public struct UIElementInfo: Identifiable, Sendable {
    public let id: String
    public let kind: UIElementKind
    public let text: String
    public let label: String
    public let placeholder: String
    public let enabled: Bool
    public let spacing: Int64
    public let padding: Int64
    public let children: [UIElementInfo]
}

public enum UIAction: Sendable {
    case click(windowID: Int64, elementID: String)
    case text(windowID: Int64, elementID: String, value: String)
}

extension SmalltalkSession {
    public func uiAction(_ action: UIAction) async -> EvaluationResult {
        await worker.submit { $0.performUIAction(action) }
    }
}

extension SmalltalkRuntime {
    private struct UIClassDefinition {
        let name: String
        let superclass: String
        let fields: [String]
        let methods: [String]
    }

    private static let uiClasses: [UIClassDefinition] = [
        .init(name: "UIElement", superclass: "Object", fields: ["enabled"], methods: [
            "initialize enabled := true", "enabled ^ enabled", "enabled: aBoolean enabled := aBoolean",
        ]),
        .init(name: "UILabel", superclass: "UIElement", fields: ["text"], methods: [
            "initialize super initialize. text := ''", "text ^ text", "text: aString text := aString",
        ]),
        .init(name: "UIButton", superclass: "UIElement", fields: ["title", "action"], methods: [
            "initialize super initialize. title := 'Button'. action := nil",
            "title ^ title", "title: aString title := aString", "action: aBlock action := aBlock",
            "click enabled ifFalse: [ ^ self ]. action notNil ifTrue: [ ^ action value ]",
        ]),
        .init(name: "UITextField", superclass: "UIElement", fields: ["label", "text", "placeholder"], methods: [
            "initialize super initialize. label := ''. text := ''. placeholder := ''",
            "label ^ label", "label: aString label := aString",
            "text ^ text", "text: aString text := aString",
            "placeholder ^ placeholder", "placeholder: aString placeholder := aString",
        ]),
        .init(name: "UIContainer", superclass: "UIElement", fields: ["children", "spacing", "padding"], methods: [
            "initialize super initialize. children := Array new: 0. spacing := 8. padding := 0",
            "children ^ children", "children: anArray children := anArray",
            "spacing ^ spacing", "spacing: aNumber spacing := aNumber",
            "padding ^ padding", "padding: aNumber padding := aNumber",
            """
            add: anElement
                | replacement |
                replacement := Array new: children size + 1.
                1 to: children size do: [ :index | replacement at: index put: (children at: index) ].
                replacement at: replacement size put: anElement.
                children := replacement.
                ^ anElement
            """,
            "remove: anElement children := children select: [ :each | (each == anElement) not ]",
            "removeAll children := Array new: 0",
        ]),
        .init(name: "UIColumn", superclass: "UIContainer", fields: [], methods: []),
        .init(name: "UIRow", superclass: "UIContainer", fields: [], methods: []),
        .init(name: "UISpacer", superclass: "UIElement", fields: [], methods: []),
        .init(name: "UIWindow", superclass: "SystemWindow", fields: ["content"], methods: [
            "initialize super initialize. kind := #custom. title := 'Fenster'. width := 480. height := 320. content := nil",
            "content ^ content", "content: anElement content := anElement",
        ]),
    ]

    /// Upgrade old images without changing SystemWindow's serialized layout or
    /// executing initialize/getters. Existing user methods remain untouched.
    func installUserInterfaceIfNeeded() throws {
        if classes["UIElement"] == nil {
            guard Self.uiClasses.allSatisfy({ classes[$0.name] == nil && globals[$0.name] == nil }),
                  classes.count + Self.uiClasses.count <= 128 else {
                throw SmalltalkError("Die UI-Klassen können nicht installiert werden: Namenskonflikt oder Klassentabelle voll.")
            }
            for definition in Self.uiClasses {
                guard let parent = classes[definition.superclass] else { throw SmalltalkError("UI-Oberklasse fehlt.") }
                let stClass = try subclass(of: parent, name: definition.name, fields: definition.fields.joined(separator: " "))
                for method in definition.methods { try compile(method, in: stClass) }
            }
        } else {
            for definition in Self.uiClasses {
                guard let stClass = classes[definition.name], stClass.ownFields == definition.fields,
                      stClass.superclass === classes[definition.superclass] else {
                    throw SmalltalkError("\(definition.name) kollidiert mit den UI-Klassen.")
                }
            }
        }
        let additions = [
            ("SystemWindow", "open ^ Desktop open: self"),
            ("DesktopManager", "openWindow ^ self open: UIWindow new"),
            ("DesktopManager", """
            open: aWindow
                windows do: [ :each | each == aWindow ifTrue: [ ^ self activate: aWindow ] ].
                windows size >= 128 ifTrue: [ ^ nil ].
                aWindow id: nextID.
                nextID := nextID + 1.
                ^ self activate: aWindow
            """),
        ]
        for (name, source) in additions {
            var parser = try Parser(source)
            let selector = try parser.method(source: source).selector
            guard let stClass = classes[name] else { throw SmalltalkError("Fensterklasse fehlt.") }
            if stClass.lookup(selector) == nil { try compile(source, in: stClass) }
        }
    }

    private func isUIClass(_ stClass: STClass, named name: String) -> Bool {
        guard let base = classes[name] else { return false }
        var current: STClass? = stClass
        while let candidate = current {
            if candidate === base { return true }
            current = candidate.superclass
        }
        return false
    }

    private struct ProjectedControl {
        let object: STObject
        let kind: UIElementKind
        let enabled: Bool
    }

    /// Validate a bounded tree using fields only, never Smalltalk message sends.
    private func projectInterface(_ value: Value) throws -> (root: UIElementInfo?, controls: [String: ProjectedControl]) {
        if case .nilValue = value { return (nil, [:]) }
        var seen: Set<ObjectIdentifier> = []
        var controls: [String: ProjectedControl] = [:]
        let kinds: [(String, UIElementKind)] = [
            ("UILabel", .label), ("UIButton", .button), ("UITextField", .textField),
            ("UIColumn", .column), ("UIRow", .row), ("UISpacer", .spacer),
        ]
        func project(_ value: Value, depth: Int, parentEnabled: Bool) throws -> UIElementInfo {
            guard depth <= 16, seen.count < 512, case .object(let object) = value,
                  seen.insert(ObjectIdentifier(object)).inserted,
                  let kind = kinds.first(where: { isUIClass(object.stClass, named: $0.0) })?.1,
                  case .boolean(let ownEnabled)? = object.fields["enabled"] else {
                throw SmalltalkError("Ungültige Oberfläche: erwartet wird ein Baum aus UI-Elementen (maximal 512 Elemente, Tiefe 16, keine Zyklen oder mehrfach verwendeten Elemente).")
            }
            func string(_ name: String) throws -> String {
                guard case .string(let text)? = object.fields[name], text.utf8.count <= 65_536 else {
                    throw SmalltalkError("Ungültige Oberfläche: \(object.stClass.name)>>\(name) muss ein String mit maximal 64 KiB sein.")
                }
                return text
            }
            let enabled = parentEnabled && ownEnabled
            var text = "", label = "", placeholder = ""
            var spacing: Int64 = 0, padding: Int64 = 0
            var children: [UIElementInfo] = []
            switch kind {
            case .label: text = try string("text")
            case .button:
                text = try string("title")
                switch object.fields["action"] {
                case .nilValue?: break
                case .block(let block)? where block.parameters.isEmpty: break
                default: throw SmalltalkError("Ungültige Oberfläche: Button-Aktionen müssen Blöcke ohne Argumente oder nil sein.")
                }
            case .textField:
                text = try string("text"); label = try string("label"); placeholder = try string("placeholder")
            case .column, .row:
                guard case .array(let array)? = object.fields["children"], array.elements.count <= 512,
                      case .integer(let gap)? = object.fields["spacing"], (0...128).contains(gap),
                      case .integer(let inset)? = object.fields["padding"], (0...256).contains(inset) else {
                    throw SmalltalkError("Ungültiges Layout: children muss ein Array sein, spacing zwischen 0 und 128 und padding zwischen 0 und 256 liegen.")
                }
                spacing = gap; padding = inset
                children = try array.elements.map { try project($0, depth: depth + 1, parentEnabled: enabled) }
            case .spacer: break
            }
            controls[object.nativeID] = ProjectedControl(object: object, kind: kind, enabled: enabled)
            return UIElementInfo(id: object.nativeID, kind: kind, text: text, label: label, placeholder: placeholder,
                                 enabled: enabled, spacing: spacing, padding: padding, children: children)
        }
        let root = try project(value, depth: 0, parentEnabled: true)
        return (root, controls)
    }

    func projectWindowContent(_ object: STObject) throws -> UIElementInfo? {
        guard isUIClass(object.stClass, named: "UIWindow"), let content = object.fields["content"] else {
            throw SmalltalkError("Ein eigenes Fenster muss eine Instanz von UIWindow oder einer Unterklasse sein.")
        }
        return try projectInterface(content).root
    }

    func performUIAction(_ action: UIAction) -> EvaluationResult {
        transcript = ""; steps = 0; depth = 0
        do {
            let windowID: Int64, elementID: String
            switch action {
            case .click(let window, let element), .text(let window, let element, _):
                windowID = window; elementID = element
            }
            // A callback from a removed control/window or a previous image must
            // never be retargeted to a different object at the same tree position.
            guard case .object(let desktop)? = globals["Desktop"],
                  case .array(let windows)? = desktop.fields["windows"],
                  let window = windows.elements.prefix(128).compactMap({ value -> STObject? in
                      guard case .object(let object) = value, case .integer(windowID)? = object.fields["id"] else { return nil }
                      return object
                  }).first,
                  case .symbol("custom")? = window.fields["kind"],
                  let content = window.fields["content"] else { return snapshot() }
            let projection = try projectInterface(content)
            guard let control = projection.controls[elementID], control.enabled else { return snapshot() }
            let result: Value
            switch action {
            case .click:
                guard control.kind == .button else { throw SmalltalkError("Das Element ist kein Button.") }
                result = try send(.object(control.object), "click", [])
            case .text(_, _, let text):
                guard control.kind == .textField, text.utf8.count <= 65_536 else { throw SmalltalkError("Ungültige Texteingabe (maximal 64 KiB).") }
                result = try send(.object(control.object), "text:", [.string(text)])
            }
            return snapshot(value: printValue(result))
        } catch { return snapshot(error: error.localizedDescription) }
    }
}
