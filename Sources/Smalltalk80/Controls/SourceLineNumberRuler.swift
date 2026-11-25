import AppKit

@MainActor
final class SourceLineNumberRuler: NSRulerView {
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
