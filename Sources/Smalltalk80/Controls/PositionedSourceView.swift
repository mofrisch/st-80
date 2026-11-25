import SwiftUI

struct PositionedSourceView: View {
    let text: String
    let line: Int
    let column: Int
    let identifier: String

    private struct SourceLocation: Equatable {
        let text: String
        let line: Int
    }

    var body: some View {
        let lines = text.split(omittingEmptySubsequences: false) {
            $0 == "\n" || $0 == "\r" || $0 == "\r\n"
        }
        return ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.indices, id: \.self) { index in
                        sourceLine(lines[index], number: index + 1)
                            .id(index + 1)
                    }
                }
            }
            .accessibilityIdentifier(identifier)
            .task(id: SourceLocation(text: text, line: line)) {
                guard lines.indices.contains(line - 1) else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                reader.scrollTo(line, anchor: .center)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func sourceLine(_ source: Substring, number: Int) -> some View {
        let current = number == line
        let width: CGFloat = 42
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(String(number))
                .foregroundStyle(.secondary)
                .frame(width: width, alignment: .trailing)
                .accessibilityHidden(true)
            Text(markedSource(source, column: current ? column : nil))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 14, design: .monospaced))
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .background(current ? Color.accentColor.opacity(0.14) : .clear)
        .overlay(alignment: .leading) {
            if current {
                Rectangle().fill(Color.accentColor).frame(width: 2)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
    }

    private func markedSource(_ source: Substring, column: Int?) -> AttributedString {
        var marked = AttributedString(String(source))
        if let column, column > 0,
           let start = marked.characters.index(marked.startIndex, offsetBy: column - 1, limitedBy: marked.endIndex),
           start < marked.endIndex {
            let end = marked.characters.index(after: start)
            marked[start..<end].backgroundColor = Color.accentColor.opacity(0.3)
        }
        return marked
    }
}
