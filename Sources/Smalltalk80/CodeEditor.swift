import AppKit
import SmalltalkCore
import SwiftUI

enum EditorContextAction: Equatable {
    case control(String)
    case legacyInspect
    case debugWorkspace(editorID: String)
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
    var allowsUndo = true
    var usesSmalltalkSourceStyle = false
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
        if usesSmalltalkSourceStyle {
            textView.installSourceStyle(in: scrollView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        // AppKit sends selection notifications synchronously while applying model updates.
        // These updates must not write back into SwiftUI bindings.
        context.coordinator.isUpdatingView = true
        defer { context.coordinator.isUpdatingView = false }
        if textView.isEditable != isEditable { textView.isEditable = isEditable }
        if textView.string != text {
            textView.string = text
            if allowsUndo { textView.undoManager?.removeAllActions() }
            (textView as? CodeEditorTextView)?.refreshSourceStyle()
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
        private let editorUndoManager = UndoManager()
        init(_ parent: CodeEditor) { self.parent = parent }

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
            (textView as? CodeEditorTextView)?.refreshSourceStyle()
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

    func installSourceStyle(in scrollView: NSScrollView) {
        let ruler = SourceLineNumberRuler(scrollView: scrollView, editor: self)
        lineNumbers = ruler
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        refreshSourceStyle()
    }

    func refreshSourceStyle() {
        guard let lineNumbers, let layoutManager else { return }
        let source = string as NSString
        lineNumbers.updateLineStarts(in: source)
        let range = NSRange(location: 0, length: source.length)
        guard range.length > 0 else { return }

        // Paint the editor only. Keep syntax colors out of text storage,
        // pasteboard contents, drafts, and the undo history.
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        Self.sourceTokens.enumerateMatches(in: string, range: range) { match, _, _ in
            guard let match else { return }
            let color: NSColor
            if match.range(withName: "comment").location != NSNotFound {
                color = .secondaryLabelColor
            } else if match.range(withName: "literal").location != NSNotFound {
                color = .linkColor
            } else {
                color = .systemPurple
            }
            layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: match.range)
        }
        needsDisplay = true
    }

    /// This tolerant matcher only colors literals and a few language marks.
    /// The image compiler still owns tokenization, diagnostics and execution.
    private static let sourceTokens: NSRegularExpression = {
        let comment = #"(?<comment>"[^"]*"?)"#
        let literal = #"(?<literal>#?'(?:''|[^'])*'?|#(?:\(|[\p{L}_][\p{L}\p{M}\p{N}_]*(?::[\p{L}\p{M}\p{N}_]*)*|[+\-*/\\~<>=@%,&?!]+))"#
        let marks = #":=|\^|(?<![\p{L}\p{M}\p{N}_])(?:[0-9]+|self|super|nil|true|false)(?![\p{L}\p{M}\p{N}_])"#
        return try! NSRegularExpression(pattern: [comment, literal, marks].joined(separator: "|"))
    }()

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

        if let coordinator = delegate as? CodeEditor.Coordinator {
            let source = string as NSString
            let selection = range.location <= source.length && range.length <= source.length - range.location
                ? source.substring(with: range) : ""
            for item in coordinator.contextItems(for: selection) { menu.addItem(item) }
            if menu.numberOfItems > 0 { menu.addItem(.separator()) }
        }

        func add(_ title: String, _ identifier: String, _ action: Selector, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.setAccessibilityIdentifier("editorContext-\(identifier)")
            item.isEnabled = enabled
            menu.addItem(item)
        }

        if isEditable { add("Cut", "cut", #selector(cut(_:)), enabled: hasSelection) }
        add("Copy", "copy", #selector(copy(_:)), enabled: hasSelection)
        // Read the clipboard only if the user chooses to paste.
        if isEditable { add("Paste", "paste", #selector(paste(_:))) }
        add("Select All", "selectAll", #selector(selectAll(_:)), enabled: !string.isEmpty)
        return menu
    }
}

@MainActor
private final class SourceLineNumberRuler: NSRulerView {
    private var lineNumbers = [0: 1]
    private let numberStyle: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.secondaryLabelColor,
    ]

    init(scrollView: NSScrollView, editor: NSTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = editor
        ruleThickness = 44

        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(invalidateGutter),
                                               name: NSView.boundsDidChangeNotification, object: clipView)
    }

    required init(coder: NSCoder) { fatalError("SourceLineNumberRuler is created in code") }

    @objc private func invalidateGutter() { needsDisplay = true }

    func updateLineStarts(in source: NSString) {
        var starts = [0: 1]
        var start = 0
        var number = 1
        while start < source.length {
            var end = start
            var contentsEnd = start
            source.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))
            guard end > start else { break }
            if contentsEnd < end {
                number += 1
                starts[end] = number
            }
            start = end
        }
        lineNumbers = starts
        invalidateGutter()
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        // AppKit can pass the scroll view's dirty rectangle to the ruler.
        let dirty = rect.intersection(bounds)
        guard !dirty.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: dirty).addClip()

        NSColor.controlBackgroundColor.setFill()
        dirty.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: dirty.minY, width: 1, height: dirty.height).fill()

        guard let editor = clientView as? NSTextView, let layout = editor.layoutManager,
              let container = editor.textContainer else { return }
        let origin = editor.textContainerOrigin
        let visible = editor.visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)

        func drawNumber(_ number: Int, at fragment: NSRect) {
            let line = convert(fragment.offsetBy(dx: origin.x, dy: origin.y), from: editor)
            guard line.maxY >= dirty.minY, line.minY <= dirty.maxY else { return }
            let label = NSAttributedString(string: String(number), attributes: numberStyle)
            let size = label.size()
            label.draw(at: NSPoint(x: floor(bounds.maxX - size.width - 8), y: floor(line.midY - size.height / 2)))
        }

        if glyphs.length > 0 {
            layout.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, range, _ in
                let character = layout.characterIndexForGlyph(at: range.location)
                if let number = self.lineNumbers[character] {
                    drawNumber(number, at: used)
                }
            }
        }
        // TextKit represents an empty document or the line after a trailing
        // newline as an extra fragment without glyphs.
        let length = (editor.string as NSString).length
        if let number = lineNumbers[length], layout.extraLineFragmentTextContainer === container {
            drawNumber(number, at: layout.extraLineFragmentUsedRect)
        }
    }
}
