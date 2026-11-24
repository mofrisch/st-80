import Foundation
import Testing
@testable import SmalltalkCore

struct CompilerTests {
    @Test func aLiveScannerEditChangesWorkspaceAndMethodCompilationAndSurvivesReload() async throws {
        let session = SmalltalkSession()
        let scanner = """
        source: input
            input = '6 * 7' ifTrue: [ input := '73' ].
            input = 'answer ^ 1' ifTrue: [ input := 'answer ^ 99' ].
            characters := input characters
        """
        let changed = await session.compile(scanner, in: "STScanner")
        #expect(changed.executionError == nil)
        #expect(await session.evaluate("6 * 7").value == "73")
        #expect(await session.compile("answer ^ 1", in: "Counter").executionError == nil)
        #expect(await session.evaluate("Counter new answer").value == "99")

        let restored = SmalltalkSession()
        _ = try await restored.loadImage(session.imageData())
        #expect(await restored.evaluate("6 * 7").value == "73")
        #expect(await restored.evaluate("Counter new answer").value == "99")
        #expect(await restored.evaluate("Counter compile: 'answer ^ 1'. Counter new answer").value == "99")
    }

    @Test func sourceHighlightingRecoversFromPartialInputAndReturnsUTF16Ranges() async {
        let session = SmalltalkSession()
        let comment = "\"💡\r\ncomment\""
        let symbol = "#'e\u{301}'"
        let unfinished = "'unterminated 💡"
        let source = "\(comment) café := \(symbol). 💥 # 9223372036854775809 ^ self \(unfinished)"
        let highlights = await session.sourceHighlights(source)
        let nativeText = source as NSString

        #expect(highlights.map(\.kind) == [.comment, .language, .literal, .language, .language, .language, .literal])
        #expect(highlights.map { nativeText.substring(with: NSRange($0.range)) }
                == [comment, ":=", symbol, "9223372036854775809", "^", "self", unfinished])

        let openComment = "\"open comment 💡"
        let commentHighlights = await session.sourceHighlights(openComment)
        #expect(commentHighlights == [SourceHighlight(kind: .comment, range: 0..<openComment.utf16.count)])
        #expect(await session.evaluate(openComment).executionError?.contains("Unterminated comment") == true)
        #expect(await session.evaluate(unfinished).executionError?.contains("Unterminated string") == true)
    }

    @Test func sourceHighlightingFollowsTheLiveImageScanner() async {
        let session = SmalltalkSession()
        let initial = await session.sourceHighlights("42")
        #expect(initial.map(\.kind) == [.language])
        let change = await session.compile("token: kind value: value ^ self highlight: #comment", in: "STSourceScanner")
        #expect(change.executionError == nil)
        let updated = await session.sourceHighlights("42")
        #expect(updated.map(\.kind) == [.comment])
        #expect(await session.evaluate("6 * 7").value == "42")
    }

    @Test func malformedCompilerOutputCannotReplaceAnInstalledMethod() async {
        let session = SmalltalkSession()
        #expect(await session.compile("answer ^ 42", in: "Counter").executionError == nil)
        #expect(await session.compile("method: source ^ #(wrong)", in: "STCompiler").executionError == nil)
        let attempted = await session.compile("answer ^ 99", in: "Counter")
        #expect(attempted.executionError?.contains("syntax tree") == true)
        #expect(await session.evaluate("Counter new answer").value == "42")
    }

    @Test func imageLoadRejectsOldVersionsBeforeReplacingTheSession() async throws {
        let session = SmalltalkSession()
        _ = await session.evaluate("kept := 42")
        for version in [1, 2, 3, 4] {
            let oldHeader = Data(#"{"format":"st80-image","version":\#(version)}"#.utf8)
            await #expect(throws: SmalltalkError.self) {
                _ = try await session.loadImage(oldHeader)
            }
        }
        #expect(await session.evaluate("kept").value == "42")
    }
}
