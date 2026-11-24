import Foundation

public enum UIElementKind: String, Sendable {
    case label, button, textField, codeEditor, sourceView, list, historyList, valueTable, column, row, split, scroll, menu, spacer, divider
}

public struct UIValueRow: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let value: String
    public let className: String
}

public struct UIValueTableInfo: Sendable {
    public let headings: (name: String, value: String, className: String)
    public let rowIdentifierPrefix: String
    public let rows: [UIValueRow]
    package let nameWidth: Int
    package let classWidth: Int
    package let columnSpacing: Int
    package let horizontalPadding: Int
    package let valueLines: Int
}

package enum UIEditorAction: String, Sendable {
    case cut, copy, paste, selectAll
}

package struct UIEditorMenuItem: Sendable {
    package let action: UIEditorAction
    package let title: String
}

package struct UIEditorInfo: Sendable {
    package let lineNumbers: Bool
    package let syntaxHighlighting: Bool
    package let undoEnabled: Bool
    package let editingMenu: [UIEditorMenuItem]
}

public struct UIHistoryEntry: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let badge: String
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
    public let historyEntries: [UIHistoryEntry]
    public let historyRowIdentifierPrefix: String?
    public let sourcePosition: (line: Int, column: Int)?
    public let selection: String?
    public let command: String?
    public let icon: String?
    public let table: UIValueTableInfo?
    package let editor: UIEditorInfo?
    public let selectionSource: String?
    /// A native context menu projected from a Smalltalk control.
    public let contextMenuItems: [UIElementInfo]?

    package func firstVisible(where matches: (UIElementInfo) -> Bool) -> UIElementInfo? {
        guard visible else { return nil }
        if matches(self) { return self }
        for child in children {
            if let found = child.firstVisible(where: matches) { return found }
        }
        for item in contextMenuItems ?? [] {
            if let found = item.firstVisible(where: matches) { return found }
        }
        return nil
    }
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

    /// Projection and MVC mounting must follow the same context-menu edges.
    func interfaceContextMenu(of view: STObject) throws -> Value? {
        guard isUIClass(view.stClass, named: "UICodeEditor") || isUIClass(view.stClass, named: "UIScroll"),
              let menu = view.fields["contextMenu"] else { return nil }
        if case .nilValue = menu { return menu }
        guard case .object(let menuObject) = menu, isUIClass(menuObject.stClass, named: "UIMenu") else {
            throw SmalltalkError("A context menu must be a UIMenu or nil.")
        }
        return menu
    }

    /// Validate a bounded tree using fields only, never Smalltalk message sends.
    private func projectInterface(_ value: Value) throws -> (root: UIElementInfo?, controls: [String: ProjectedControl]) {
        if case .nilValue = value { return (nil, [:]) }
        var seen: Set<ObjectIdentifier> = []
        var controls: [String: ProjectedControl] = [:]
        let kinds: [(String, UIElementKind)] = [
            ("UILabel", .label), ("UIButton", .button), ("UICodeEditor", .codeEditor), ("UISourceView", .sourceView),
            ("UITextField", .textField), ("UIValueTable", .valueTable), ("UIHistoryList", .historyList), ("UIList", .list), ("UIColumn", .column), ("UIRow", .row),
            ("UISplit", .split), ("UIScroll", .scroll), ("UIMenu", .menu), ("UISpacer", .spacer), ("UIDivider", .divider),
        ]
        func project(_ value: Value, depth: Int, parentEnabled: Bool) throws -> UIElementInfo {
            guard depth <= 16, seen.count < 512, case .object(let object) = value,
                  seen.insert(ObjectIdentifier(object)).inserted,
                  let kind = kinds.first(where: { isUIClass(object.stClass, named: $0.0) })?.1,
                  case .boolean(let ownEnabled)? = object.fields["enabled"],
                  case .boolean(let visible)? = object.fields["visible"] else {
                throw SmalltalkError("Invalid interface. Expected a tree of UI elements with at most 512 elements, a depth of 16, and no cycles or reused elements.")
            }
            func string(_ name: String, maximum: Int = 65_536) throws -> String {
                guard case .string(let text)? = object.fields[name], text.utf8.count <= maximum else {
                    throw SmalltalkError("Invalid interface. \(object.stClass.name)>>\(name) must be a string of at most \(maximum / 1024) KiB.")
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
            var table: UIValueTableInfo?
            var editor: UIEditorInfo?
            var historyEntries: [UIHistoryEntry] = []
            var historyRowIdentifierPrefix: String?
            var sourcePosition: (line: Int, column: Int)?
            var selectionSource: String?
            var selection: String?
            var contextMenuItems: [UIElementInfo]?
            switch kind {
            case .label: text = try string("text", maximum: symbolField("role") == "document" ? 262_144 : 65_536)
            case .button:
                text = try string("title")
                label = field("shortcutHint") ?? ""
                switch object.fields["action"] {
                case .nilValue?: break
                case .block(let block)? where block.parameters.isEmpty: break
                default: throw SmalltalkError("Invalid interface. Button actions must be blocks with no arguments or nil.")
                }
                if case .block(let action)? = object.fields["selectionAction"] {
                    guard action.parameters.count == 1, case .object(let editor)? = object.fields["selectionSource"],
                          isUIClass(editor.stClass, named: "UICodeEditor") else {
                        throw SmalltalkError("A selection action requires a code editor and a block with one argument.")
                    }
                    selectionSource = editor.nativeID
                }
            case .textField, .codeEditor:
                if case .boolean(let value)? = object.fields["readOnly"] { readOnly = value }
                text = try string("text"); label = try string("label"); placeholder = try string("placeholder")
                if kind == .codeEditor {
                    editor = try projectEditor(object, readOnly: readOnly, sourceRole: symbolField("role") == "source")
                }
                switch object.fields["mvcInputTarget"] {
                case .nilValue?: break
                case .object?:
                    guard case .symbol(let selector)? = object.fields["mvcInputSelector"],
                          selector.filter({ $0 == ":" }).count == 1, selector.hasSuffix(":") else {
                        throw SmalltalkError("Invalid text input controller.")
                    }
                    liveInput = true
                default: throw SmalltalkError("Invalid text input controller.")
                }
            case .sourceView:
                text = try string("text", maximum: 262_144)
                guard case .integer(let line)? = object.fields["line"], line > 0,
                      case .integer(let column)? = object.fields["column"], column > 0 else {
                    throw SmalltalkError("A source view requires a positive line and column.")
                }
                sourcePosition = (Int(line), Int(column))
            case .list:
                guard case .array(let values)? = object.fields["items"], values.elements.count <= 1024 else {
                    throw SmalltalkError("A list requires an array of at most 1,024 items.")
                }
                items = try values.elements.map {
                    guard case .string(let title) = $0, title.utf8.count <= 4096 else {
                        throw SmalltalkError("List items must be strings.")
                    }
                    return title
                }
                guard Set(items).count == items.count else {
                    throw SmalltalkError("List items must be unique.")
                }
                if let selected = field("selection"), items.contains(selected) { selection = selected }
            case .historyList:
                historyRowIdentifierPrefix = field("rowIdentifierPrefix")
                guard case .array(let source)? = object.fields["entries"], source.elements.count <= 2001 else {
                    throw SmalltalkError("A history list requires an array of at most 2,001 entries.")
                }
                historyEntries = try source.elements.map { value in
                    guard case .array(let row) = value, row.elements.count == 4,
                          case .string(let key) = row.elements[0], case .string(let title) = row.elements[1],
                          case .string(let subtitle) = row.elements[2], case .string(let badge) = row.elements[3],
                          [key, title, subtitle, badge].allSatisfy({ $0.utf8.count <= 4_096 }) else {
                        throw SmalltalkError("Invalid history list entry.")
                    }
                    return UIHistoryEntry(id: key, title: title, subtitle: subtitle, badge: badge)
                }
                let keys = Set(historyEntries.map(\.id))
                guard keys.count == historyEntries.count else {
                    throw SmalltalkError("History list keys must be unique.")
                }
                if let selected = field("selection"), keys.contains(selected) { selection = selected }
            case .valueTable:
                if case .boolean(let value)? = object.fields["readOnly"] { readOnly = value }
                func strings(_ value: Value?, count: Int) throws -> [String] {
                    guard case .array(let array)? = value, array.elements.count == count else {
                        throw SmalltalkError("Invalid value table column count.")
                    }
                    return try array.elements.map {
                        guard case .string(let string) = $0, string.utf8.count <= 4_096 else {
                            throw SmalltalkError("Value table cells must be strings of at most 4 KiB.")
                        }
                        return string
                    }
                }

                let headings = try strings(object.fields["headings"], count: 3)
                guard case .array(let source)? = object.fields["rows"], source.elements.count <= 4_096 else {
                    throw SmalltalkError("A value table requires an array of at most 4,096 rows.")
                }
                let rows = try source.elements.map { value in
                    let cells = try strings(value, count: 4)
                    return UIValueRow(id: cells[0], name: cells[1], value: cells[2], className: cells[3])
                }
                guard Set(rows.map(\.id)).count == rows.count else {
                    throw SmalltalkError("Value table row identifiers must be unique.")
                }
                func layout(_ name: String, default defaultValue: Int, in range: ClosedRange<Int64>) throws -> Int {
                    switch object.fields[name] {
                    case nil, .nilValue?: return defaultValue
                    case .integer(let value)? where range.contains(value): return Int(value)
                    default: throw SmalltalkError("Invalid value table layout for \(name).")
                    }
                }
                table = UIValueTableInfo(headings: (headings[0], headings[1], headings[2]),
                                         rowIdentifierPrefix: try string("rowIdentifierPrefix"), rows: rows,
                                         nameWidth: try layout("nameWidth", default: 96, in: 1...8192),
                                         classWidth: try layout("classWidth", default: 108, in: 1...8192),
                                         columnSpacing: try layout("columnSpacing", default: 12, in: 0...128),
                                         horizontalPadding: try layout("horizontalPadding", default: 12, in: 0...256),
                                         valueLines: try layout("valueLines", default: 3, in: 1...128))
            case .column, .row, .split, .scroll, .menu:
                if kind == .menu { text = try string("title") }
                guard case .array(let array)? = object.fields["children"], array.elements.count <= 512,
                      case .integer(let gap)? = object.fields["spacing"], (0...128).contains(gap),
                      case .integer(let inset)? = object.fields["padding"], (0...256).contains(inset) else {
                    throw SmalltalkError("Invalid layout. children must be an array, spacing must be between 0 and 128, and padding must be between 0 and 256.")
                }
                spacing = gap; padding = inset
                children = try array.elements.map { try project($0, depth: depth + 1, parentEnabled: enabled) }
            case .spacer, .divider: break
            }
            if let menu = try interfaceContextMenu(of: object) {
                if case .nilValue = menu {
                    contextMenuItems = []
                } else {
                    let menuInfo = try project(menu, depth: depth + 1, parentEnabled: enabled)
                    guard menuInfo.children.allSatisfy({ item in
                        (item.kind == .button || item.kind == .divider) &&
                        (item.selectionSource == nil || (kind == .codeEditor && item.selectionSource == object.nativeID))
                    }) else {
                        throw SmalltalkError("Context menus accept buttons and dividers. Selection actions require the owning editor.")
                    }
                    contextMenuItems = menuInfo.visible ? menuInfo.children.filter(\.visible) : []
                }
            }
            controls[object.nativeID] = ProjectedControl(object: object, kind: kind, enabled: enabled)
            return UIElementInfo(id: object.nativeID, kind: kind, text: text, label: label, placeholder: placeholder,
                                 enabled: enabled, liveInput: liveInput, spacing: spacing, padding: padding, children: children,
                                 accessibilityID: field("identifier"), role: symbolField("role"), visible: visible,
                                 minimumWidth: dimension("minWidth"), maximumWidth: dimension("maxWidth"),
                                 minimumHeight: dimension("minHeight"), maximumHeight: dimension("maxHeight"),
                                 readOnly: readOnly, items: items, historyEntries: historyEntries,
                                 historyRowIdentifierPrefix: historyRowIdentifierPrefix, sourcePosition: sourcePosition,
                                 selection: selection, command: symbolField("command"),
                                 icon: field("icon"), table: table, editor: editor, selectionSource: selectionSource,
                                 contextMenuItems: contextMenuItems)
        }
        let root = try project(value, depth: 0, parentEnabled: true)
        return (root, controls)
    }

    private func projectEditor(_ object: STObject, readOnly: Bool, sourceRole: Bool) throws -> UIEditorInfo {
        func flag(_ name: String, default defaultValue: Bool) throws -> Bool {
            switch object.fields[name] {
            case nil, .nilValue?: return defaultValue
            case .boolean(let value)?: return value
            default: throw SmalltalkError("Invalid code editor setting for \(name).")
            }
        }

        let menu: [UIEditorMenuItem]
        switch object.fields["editingMenu"] {
        case nil, .nilValue?:
            // Older image layouts still use the standard AppKit editing commands.
            menu = [UIEditorMenuItem(action: .cut, title: "Cut"), UIEditorMenuItem(action: .copy, title: "Copy"),
                    UIEditorMenuItem(action: .paste, title: "Paste"), UIEditorMenuItem(action: .selectAll, title: "Select All")]
        case .array(let entries)? where entries.elements.count <= 4:
            menu = try entries.elements.map { entry in
                guard case .array(let row) = entry, row.elements.count == 2,
                      case .symbol(let name) = row.elements[0], let action = UIEditorAction(rawValue: name),
                      case .string(let title) = row.elements[1], !title.isEmpty, title.utf8.count <= 4096 else {
                    throw SmalltalkError("Invalid code editor menu action or title.")
                }
                return UIEditorMenuItem(action: action, title: title)
            }
            guard Set(menu.map(\.action)).count == menu.count else {
                throw SmalltalkError("Code editor menu actions must be unique.")
            }
        default: throw SmalltalkError("A code editor menu requires an array of at most four editing actions.")
        }
        return UIEditorInfo(lineNumbers: try flag("lineNumbers", default: sourceRole),
                            syntaxHighlighting: try flag("syntaxHighlighting", default: sourceRole),
                            undoEnabled: try flag("undoEnabled", default: true) && !readOnly, editingMenu: menu)
    }

    func projectWindowContent(_ object: STObject) throws -> UIElementInfo? {
        guard isUIClass(object.stClass, named: "UIWindow"), let content = object.fields["content"] else {
            throw SmalltalkError("A custom window must be an instance of UIWindow or one of its subclasses.")
        }
        return try projectContent(content)
    }

    func projectContent(_ content: Value) throws -> UIElementInfo? {
        try projectInterface(content).root
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
            guard let window = projectedWindow(withID: windowID),
                  let content = changesBrowserContent(for: window) ?? window.fields["content"] else { return snapshot() }
            let projection = try projectInterface(content)
            guard let control = projection.controls[elementID], control.enabled else { return snapshot() }
            let result: Value
            switch action {
            case .click(_, _, let selection):
                guard control.kind == .button else { throw SmalltalkError("The element is not a button.") }
                guard selection.utf8.count <= 65_536 else { throw SmalltalkError("The selection is too large.") }
                result = try send(.object(control.object), "clickWithSelection:", [.string(selection)])
            case .select(_, _, let value):
                guard control.kind == .list || control.kind == .historyList || control.kind == .valueTable else { throw SmalltalkError("The element does not support selection.") }
                if control.kind == .valueTable, case .boolean(true)? = control.object.fields["readOnly"] { return snapshot() }
                result = try send(.object(control.object), "select:", [value.map(Value.string) ?? .nilValue])
            case .text(_, _, let text):
                guard control.kind == .textField || control.kind == .codeEditor,
                      text.utf8.count <= 65_536 else { throw SmalltalkError("Invalid text input. The limit is 64 KiB.") }
                if case .boolean(true)? = control.object.fields["readOnly"] { return snapshot() }
                result = try send(.object(control.object), "editText:", [.string(text)])
            }
            return finishEvaluation(value: printValue(result))
        } catch { return finishEvaluation(error: error.localizedDescription) }
    }
}
