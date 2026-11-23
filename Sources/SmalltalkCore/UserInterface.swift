import Foundation

public enum UIElementKind: String, Sendable {
    case label, button, textField, codeEditor, list, column, row, split, scroll, menu, spacer, divider
}

/// Immutable native projection. Smalltalk objects and blocks stay on the worker.
public struct UIElementInfo: Identifiable, Sendable {
    public let id: String
    public let kind: UIElementKind
    public let text: String
    public let label: String
    public let placeholder: String
    public let enabled: Bool
    public let liveInput: Bool
    public let spacing: Int64
    public let padding: Int64
    public let children: [UIElementInfo]
    public let accessibilityID: String?
    public let role: String?
    public let visible: Bool
    public let minimumWidth: Int64?
    public let maximumWidth: Int64?
    public let minimumHeight: Int64?
    public let maximumHeight: Int64?
    public let readOnly: Bool
    public let items: [String]
    public let selection: String?
    public let command: String?
    public let selectionSource: String?
}

public enum UIAction: Sendable {
    case click(windowID: Int64, elementID: String, selection: String = "")
    case select(windowID: Int64, elementID: String, value: String?)
    case text(windowID: Int64, elementID: String, value: String)
}

extension SmalltalkSession {
    public func uiAction(_ action: UIAction) async -> EvaluationResult {
        await worker.submit { $0.performUIAction(action) }
    }
}

extension SmalltalkRuntime {
    func isUIClass(_ stClass: STClass, named name: String) -> Bool {
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
            ("UILabel", .label), ("UIButton", .button), ("UICodeEditor", .codeEditor),
            ("UITextField", .textField), ("UIList", .list), ("UIColumn", .column), ("UIRow", .row),
            ("UISplit", .split), ("UIScroll", .scroll), ("UIMenu", .menu), ("UISpacer", .spacer), ("UIDivider", .divider),
        ]
        func project(_ value: Value, depth: Int, parentEnabled: Bool) throws -> UIElementInfo {
            guard depth <= 16, seen.count < 512, case .object(let object) = value,
                  seen.insert(ObjectIdentifier(object)).inserted,
                  let kind = kinds.first(where: { isUIClass(object.stClass, named: $0.0) })?.1,
                  case .boolean(let ownEnabled)? = object.fields["enabled"],
                  case .boolean(let visible)? = object.fields["visible"] else {
                throw SmalltalkError("Ungültige Oberfläche: erwartet wird ein Baum aus UI-Elementen (maximal 512 Elemente, Tiefe 16, keine Zyklen oder mehrfach verwendeten Elemente).")
            }
            func string(_ name: String) throws -> String {
                guard case .string(let text)? = object.fields[name], text.utf8.count <= 65_536 else {
                    throw SmalltalkError("Ungültige Oberfläche: \(object.stClass.name)>>\(name) muss ein String mit maximal 64 KiB sein.")
                }
                return text
            }
            func field(_ name: String) -> String? {
                if case .string(let value)? = object.fields[name] { return value }
                return nil
            }
            func symbolField(_ name: String) -> String? {
                if case .symbol(let value)? = object.fields[name] { return value }
                return nil
            }
            func dimension(_ name: String) -> Int64? {
                if case .integer(let n)? = object.fields[name], (0...8192).contains(n) { return n }
                return nil
            }
            let enabled = parentEnabled && ownEnabled && visible
            var text = "", label = "", placeholder = ""
            var liveInput = false
            var spacing: Int64 = 0, padding: Int64 = 0
            var children: [UIElementInfo] = []
            var readOnly = false
            var items: [String] = []
            var selectionSource: String?
            var selection: String?
            switch kind {
            case .label: text = try string("text")
            case .button:
                text = try string("title")
                switch object.fields["action"] {
                case .nilValue?: break
                case .block(let block)? where block.parameters.isEmpty: break
                default: throw SmalltalkError("Ungültige Oberfläche: Button-Aktionen müssen Blöcke ohne Argumente oder nil sein.")
                }
                if case .block(let action)? = object.fields["selectionAction"] {
                    guard action.parameters.count == 1, case .object(let editor)? = object.fields["selectionSource"],
                          isUIClass(editor.stClass, named: "UICodeEditor") else {
                        throw SmalltalkError("Eine Auswahlaktion benötigt einen Code-Editor und einen Block mit einem Argument.")
                    }
                    selectionSource = editor.nativeID
                }
            case .textField, .codeEditor:
                if case .boolean(let value)? = object.fields["readOnly"] { readOnly = value }
                text = try string("text"); label = try string("label"); placeholder = try string("placeholder")
                switch object.fields["mvcInputTarget"] {
                case .nilValue?: break
                case .object?:
                    guard case .symbol(let selector)? = object.fields["mvcInputSelector"],
                          selector.filter({ $0 == ":" }).count == 1, selector.hasSuffix(":") else {
                        throw SmalltalkError("Ungültiger Controller für ein Eingabefeld.")
                    }
                    liveInput = true
                default: throw SmalltalkError("Ungültiger Controller für ein Eingabefeld.")
                }
            case .list:
                guard case .array(let values)? = object.fields["items"], values.elements.count <= 1024 else {
                    throw SmalltalkError("Eine Liste benötigt ein Array mit maximal 1.024 Einträgen.")
                }
                items = try values.elements.map {
                    guard case .string(let title) = $0, title.utf8.count <= 4096 else {
                        throw SmalltalkError("Listeneinträge müssen Strings sein.")
                    }
                    return title
                }
                guard Set(items).count == items.count else {
                    throw SmalltalkError("Listeneinträge müssen eindeutig sein.")
                }
                if let selected = field("selection"), items.contains(selected) { selection = selected }
            case .column, .row, .split, .scroll, .menu:
                if kind == .menu { text = try string("title") }
                guard case .array(let array)? = object.fields["children"], array.elements.count <= 512,
                      case .integer(let gap)? = object.fields["spacing"], (0...128).contains(gap),
                      case .integer(let inset)? = object.fields["padding"], (0...256).contains(inset) else {
                    throw SmalltalkError("Ungültiges Layout: children muss ein Array sein, spacing zwischen 0 und 128 und padding zwischen 0 und 256 liegen.")
                }
                spacing = gap; padding = inset
                children = try array.elements.map { try project($0, depth: depth + 1, parentEnabled: enabled) }
            case .spacer, .divider: break
            }
            controls[object.nativeID] = ProjectedControl(object: object, kind: kind, enabled: enabled)
            return UIElementInfo(id: object.nativeID, kind: kind, text: text, label: label, placeholder: placeholder,
                                 enabled: enabled, liveInput: liveInput, spacing: spacing, padding: padding, children: children,
                                 accessibilityID: field("identifier"), role: symbolField("role"), visible: visible,
                                 minimumWidth: dimension("minWidth"), maximumWidth: dimension("maxWidth"),
                                 minimumHeight: dimension("minHeight"), maximumHeight: dimension("maxHeight"),
                                 readOnly: readOnly, items: items, selection: selection, command: symbolField("command"),
                                 selectionSource: selectionSource)
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
            case .click(let window, let element, _), .text(let window, let element, _), .select(let window, let element, _):
                windowID = window; elementID = element
            }
            // A callback from a removed control/window or a previous image must
            // never be retargeted to a different object at the same tree position.
            guard case .object(let desktop)? = globals["Desktop"],
                  case .object(let model)? = desktop.fields["model"],
                  case .array(let windows)? = model.fields["windows"],
                  let window = windows.elements.prefix(128).compactMap({ value -> STObject? in
                      guard case .object(let object) = value, case .integer(windowID)? = object.fields["id"] else { return nil }
                      return object
                  }).first,
                  let content = window.fields["content"] else { return snapshot() }
            let projection = try projectInterface(content)
            guard let control = projection.controls[elementID], control.enabled else { return snapshot() }
            let result: Value
            switch action {
            case .click(_, _, let selection):
                guard control.kind == .button else { throw SmalltalkError("Das Element ist kein Button.") }
                guard selection.utf8.count <= 65_536 else { throw SmalltalkError("Die Auswahl ist zu groß.") }
                result = try send(.object(control.object), "clickWithSelection:", [.string(selection)])
            case .select(_, _, let value):
                guard control.kind == .list else { throw SmalltalkError("Das Element ist keine Liste.") }
                result = try send(.object(control.object), "select:", [value.map(Value.string) ?? .nilValue])
            case .text(_, _, let text):
                guard control.kind == .textField || control.kind == .codeEditor,
                      text.utf8.count <= 65_536 else { throw SmalltalkError("Ungültige Texteingabe (maximal 64 KiB).") }
                if case .boolean(true)? = control.object.fields["readOnly"] { return snapshot() }
                result = try send(.object(control.object), "editText:", [.string(text)])
            }
            return finishEvaluation(value: printValue(result))
        } catch { return finishEvaluation(error: error.localizedDescription) }
    }
}
