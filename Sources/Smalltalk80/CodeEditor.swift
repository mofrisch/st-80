import AppKit
import SmalltalkCore
import SwiftUI

enum EditorContextAction: Equatable {
    case control(String)
    case legacyInspect
}

enum EditorContextItem {
    case command(title: String, identifier: String, action: EditorContextAction, enabled: Bool)
    case divider

    init?(projected element: UIElementInfo) {
        guard element.visible else { return nil }
        switch element.kind {
        case .button:
            self = .command(title: element.text, identifier: element.command ?? element.id,
                            action: .control(element.id), enabled: element.enabled)
        case .divider:
            self = .divider
        default:
            return nil
        }
    }
}

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var isEditable = true
    var identifier: String
    var label: String
    var contextMenuItems: [EditorContextItem] = []
    var contextCommandsEnabled = true
    var onContextCommand: (EditorContextAction, String) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = CodeEditorTextView()
        textView.isRichText = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        textView.defaultParagraphStyle = paragraph
        textView.string = text
        textView.delegate = context.coordinator
        textView.setAccessibilityIdentifier(identifier)
        textView.setAccessibilityLabel(label)
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        // AppKit sends selection notifications synchronously while applying model updates.
        // These updates must not write back into SwiftUI bindings.
        context.coordinator.isUpdatingView = true
        defer { context.coordinator.isUpdatingView = false }
        textView.isEditable = isEditable
        if textView.string != text {
            textView.string = text
            textView.undoManager?.removeAllActions()
        }
        let length = (text as NSString).length
        let range = NSRange(location: min(selection.location, length), length: min(selection.length, max(0, length - min(selection.location, length))))
        if textView.selectedRange() != range { textView.setSelectedRange(range) }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSMenuItemValidation {
        private struct ContextInvocation {
            let action: EditorContextAction
            let selection: String
        }

        var parent: CodeEditor
        var isUpdatingView = false
        init(_ parent: CodeEditor) { self.parent = parent }

        func contextItems(for selection: String) -> [NSMenuItem] {
            parent.contextMenuItems.map { descriptor in
                switch descriptor {
                case .divider:
                    return .separator()
                case .command(let title, let identifier, let action, let enabled):
                    let item = NSMenuItem(title: title, action: #selector(invokeContextCommand(_:)), keyEquivalent: "")
                    item.target = self
                    item.setAccessibilityIdentifier("editorContext-\(identifier)")
                    item.representedObject = ContextInvocation(action: action, selection: selection)
                    item.isEnabled = parent.contextCommandsEnabled && enabled
                    return item
                }
            }
        }

        func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
            guard parent.contextCommandsEnabled, let invocation = menuItem.representedObject as? ContextInvocation else { return false }
            return parent.contextMenuItems.contains {
                guard case .command(_, _, let action, let enabled) = $0 else { return false }
                return action == invocation.action && enabled
            }
        }

        @objc private func invokeContextCommand(_ menuItem: NSMenuItem) {
            guard validateMenuItem(menuItem), let invocation = menuItem.representedObject as? ContextInvocation else { return }
            parent.onContextCommand(invocation.action, invocation.selection)
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingView, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.selection = textView.selectedRange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdatingView, let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            if parent.selection != range { parent.selection = range }
        }
    }
}

@MainActor
private final class CodeEditorTextView: NSTextView {
    private struct ContextSelection {
        let ranges: [NSValue]
        let text: String
    }

    private var clickSelection: ContextSelection?

    override func rightMouseDown(with event: NSEvent) {
        clickSelection = captureContextSelection()
        defer { clickSelection = nil }
        super.rightMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let coordinator = delegate as? CodeEditor.Coordinator else { return super.menu(for: event) }
        let selection = clickSelection ?? captureContextSelection()
        let items = coordinator.contextItems(for: selection.text)
        let nativeMenu = super.menu(for: event)
        guard !items.isEmpty else { return nativeMenu }

        if !selection.text.isEmpty, selectedRanges != selection.ranges {
            selectedRanges = selection.ranges
        }
        // AppKit can reuse its menu. Compose a copy for this selection.
        let menu = nativeMenu?.copy() as? NSMenu ?? NSMenu()
        if menu.numberOfItems > 0 { menu.insertItem(.separator(), at: 0) }
        for (index, item) in items.enumerated() { menu.insertItem(item, at: index) }
        return menu
    }

    private func captureContextSelection() -> ContextSelection {
        let source = string as NSString
        let range = selectedRange()
        let text = range.location <= source.length && range.length <= source.length - range.location
            ? source.substring(with: range) : ""
        return ContextSelection(ranges: selectedRanges, text: text)
    }
}
