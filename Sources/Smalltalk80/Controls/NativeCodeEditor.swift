import AppKit
import SmalltalkCore
import SwiftUI

struct NativeCodeEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var isEditable = true
    var identifier: String
    var label: String
    var allowsUndo = true
    var lineNumbers: Bool
    var syntaxHighlighting: Bool
    var editingMenu: [UIEditorMenuItem]
    var highlightsForSource: @MainActor (String) async -> [SourceHighlight] = { _ in [] }
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
        textView.allowsUndo = allowsUndo
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
        if textView.setPresentation(lineNumbers: lineNumbers, syntaxHighlighting: syntaxHighlighting, in: scrollView) {
            textView.refreshSourceStyle(with: highlightsForSource)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CodeEditorTextView else { return }
        context.coordinator.parent = self
        // AppKit sends selection notifications synchronously while applying model updates.
        // These updates must not write back into SwiftUI bindings.
        context.coordinator.isUpdatingView = true
        defer { context.coordinator.isUpdatingView = false }
        if textView.isEditable != isEditable { textView.isEditable = isEditable }
        if textView.allowsUndo != allowsUndo { textView.allowsUndo = allowsUndo }
        let styleChanged = textView.setPresentation(lineNumbers: lineNumbers, syntaxHighlighting: syntaxHighlighting, in: scrollView)
        let textChanged = !textView.string.utf16.elementsEqual(text.utf16)
        if textChanged {
            textView.string = text
            if allowsUndo { textView.undoManager?.removeAllActions() }
        }
        if textChanged || styleChanged { textView.refreshSourceStyle(with: highlightsForSource) }
        let length = (text as NSString).length
        let range = NSRange(location: min(selection.location, length), length: min(selection.length, max(0, length - min(selection.location, length))))
        if textView.selectedRange() != range { textView.setSelectedRange(range) }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        (scrollView.documentView as? CodeEditorTextView)?.cancelSourceHighlighting()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSMenuItemValidation {
        private struct ContextInvocation {
            let action: EditorContextAction
            let selection: String
        }

        var parent: NativeCodeEditor
        var isUpdatingView = false
        private let editorUndoManager = UndoManager()
        init(_ parent: NativeCodeEditor) { self.parent = parent }

        func undoManager(for view: NSTextView) -> UndoManager? {
            parent.allowsUndo ? editorUndoManager : nil
        }

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
            (textView as? CodeEditorTextView)?.refreshSourceStyle(with: parent.highlightsForSource)
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
    private weak var lineNumbers: SourceLineNumberRuler?
    private var highlightTask: Task<Void, Never>?
    private var highlightsSyntax = false

    func setPresentation(lineNumbers showsLineNumbers: Bool, syntaxHighlighting: Bool, in scrollView: NSScrollView) -> Bool {
        let rulerChanged = showsLineNumbers != (lineNumbers != nil)
        let highlightingChanged = syntaxHighlighting != highlightsSyntax
        if rulerChanged {
            if showsLineNumbers {
                let ruler = SourceLineNumberRuler(scrollView: scrollView, editor: self)
                lineNumbers = ruler
                scrollView.verticalRulerView = ruler
                scrollView.hasVerticalRuler = true
                scrollView.rulersVisible = true
            } else {
                scrollView.rulersVisible = false
                scrollView.hasVerticalRuler = false
                scrollView.verticalRulerView = nil
                lineNumbers = nil
            }
        }
        highlightsSyntax = syntaxHighlighting
        if highlightingChanged && !syntaxHighlighting {
            cancelSourceHighlighting()
            applySourceHighlights([])
        }
        return rulerChanged || highlightingChanged
    }

    func cancelSourceHighlighting() {
        highlightTask?.cancel()
        highlightTask = nil
    }

    func refreshSourceStyle(with scan: @escaping @MainActor (String) async -> [SourceHighlight]) {
        cancelSourceHighlighting()
        let source = string
        lineNumbers?.updateLineStarts(in: source as NSString)
        guard highlightsSyntax, !source.isEmpty else { return }
        highlightTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(90)) } catch { return }
            let highlights = await scan(source)
            guard !Task.isCancelled, let self,
                  self.string.utf16.elementsEqual(source.utf16) else { return }
            applySourceHighlights(highlights)
        }
    }

    private func applySourceHighlights(_ highlights: [SourceHighlight]) {
        guard let layoutManager else { return }
        let length = (string as NSString).length
        guard length > 0 else { return }
        // TextKit temporary attributes stay out of clipboard data and undo.
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: length))
        for highlight in highlights where highlight.range.upperBound <= length {
            let color: NSColor = switch highlight.kind {
            case .comment: .secondaryLabelColor
            case .literal: .linkColor
            case .language: .systemPurple
            }
            layoutManager.addTemporaryAttribute(.foregroundColor, value: color,
                                                forCharacterRange: NSRange(highlight.range))
        }
        needsDisplay = true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleUndoShortcut(event) || super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if !handleUndoShortcut(event) { super.keyDown(with: event) }
    }

    private func handleUndoShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        guard isEditable, allowsUndo, window?.firstResponder === self,
              event.charactersIgnoringModifiers?.lowercased() == "z", let undoManager else { return false }
        if modifiers == [.command, .shift], undoManager.canRedo {
            undoManager.redo()
            return true
        }
        if modifiers == .command, undoManager.canUndo {
            undoManager.undo()
            return true
        }
        return false
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        // NSTextView's contextual menu performs synchronous system lookups on this path.
        // Present our own menu and leave the editor's selection intact.
        guard let menu = menu(for: event) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let range = selectedRange()
        let hasSelection = range.length > 0

        guard let coordinator = delegate as? NativeCodeEditor.Coordinator else { return nil }
        let source = string as NSString
        let selection = range.location <= source.length && range.length <= source.length - range.location
            ? source.substring(with: range) : ""
        let commands = coordinator.contextItems(for: selection)
        let editing = coordinator.parent.editingMenu.compactMap { descriptor -> NSMenuItem? in
            let action: Selector
            let enabled: Bool
            switch descriptor.action {
            case .cut:
                guard isEditable else { return nil }
                action = #selector(cut(_:))
                enabled = hasSelection
            case .copy:
                action = #selector(copy(_:))
                enabled = hasSelection
            case .paste:
                guard isEditable else { return nil }
                action = #selector(paste(_:))
                // Read the clipboard only if the user chooses to paste.
                enabled = true
            case .selectAll:
                action = #selector(selectAll(_:))
                enabled = !string.isEmpty
            }
            let item = NSMenuItem(title: descriptor.title, action: action, keyEquivalent: "")
            item.target = self
            item.setAccessibilityIdentifier("editorContext-\(descriptor.action.rawValue)")
            item.isEnabled = enabled
            return item
        }
        for item in commands { menu.addItem(item) }
        if !commands.isEmpty && !editing.isEmpty { menu.addItem(.separator()) }
        for item in editing { menu.addItem(item) }
        return menu.numberOfItems > 0 ? menu : nil
    }
}
