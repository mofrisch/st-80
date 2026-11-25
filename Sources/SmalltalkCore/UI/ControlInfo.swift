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
