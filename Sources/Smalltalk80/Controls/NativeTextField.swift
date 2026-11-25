import AppKit
import SwiftUI

struct NativeTextField: NSViewRepresentable {
    let text: String
    let placeholder: String
    let identifier: String
    let label: String
    let onEdit: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEdit: onEdit) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.onEdit = onEdit
        coordinator.isApplyingSnapshot = true
        defer { coordinator.isApplyingSnapshot = false }

        field.placeholderString = placeholder
        field.setAccessibilityIdentifier(identifier)
        field.setAccessibilityLabel(label)
        if let editor = field.currentEditor() {
            if !editor.string.utf16.elementsEqual(text.utf16) {
                let selection = editor.selectedRange
                field.stringValue = text
                if !editor.string.utf16.elementsEqual(text.utf16) { editor.string = text }
                let length = text.utf16.count
                let location = min(selection.location, length)
                editor.selectedRange = NSRange(location: location, length: min(selection.length, length - location))
            }
        } else if !field.stringValue.utf16.elementsEqual(text.utf16) {
            field.stringValue = text
        }
        if field.isEnabled != context.environment.isEnabled { field.isEnabled = context.environment.isEnabled }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var onEdit: (String) -> Void
        var isApplyingSnapshot = false

        init(onEdit: @escaping (String) -> Void) { self.onEdit = onEdit }

        // The field editor can commit its old text on focus loss. Only an
        // actual text change should enter the image's native-input queue.
        func controlTextDidChange(_ notification: Notification) {
            guard !isApplyingSnapshot, let field = notification.object as? NSTextField else { return }
            onEdit(field.currentEditor()?.string ?? field.stringValue)
        }
    }
}
