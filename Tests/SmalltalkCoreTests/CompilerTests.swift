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

    @Test func mixedLineEndingsAndUnicodeKeepTheirPositionsAcrossAnImageRoundTrip() async throws {
        let session = SmalltalkSession()
        let comment = "\"Café 🛠\""
        let source = "lineProbe\r\n    \(comment)\r    ^ missingLineProbe\n"
        let compiled = await session.compile(source, in: "Counter")
        try #require(compiled.executionError == nil)
        let original = await session.evaluate("Counter new lineProbe")
        #expect(original.executionError == "Line 3, column 7: Unknown variable: missingLineProbe")

        let reopened = try await session.loadImage(session.imageData())
        let counter = try #require(reopened.evaluation.classes.first { $0.name == "Counter" })
        let method = try #require(counter.methods.first { $0.selector == "lineProbe" })
        #expect(method.source.utf8.elementsEqual(source.utf8))
        let highlights = await session.sourceHighlights(method.source)
        let nativeSource = method.source as NSString
        let substrings = highlights.map { nativeSource.substring(with: NSRange($0.range)) }
        #expect(substrings == [comment, "^"])
        let restored = await session.evaluate("Counter new lineProbe")
        #expect(restored.executionError == original.executionError)
    }

    @Test func imageLoadRejectsUnsupportedVersionsBeforeReplacingTheSession() async throws {
        let session = SmalltalkSession()
        _ = await session.evaluate("kept := 42")
        let supported = ImageCodec.version
        for version in [supported - 1, supported + 1] {
            let header = Data(#"{"format":"st80-image","version":\#(version)}"#.utf8)
            do {
                _ = try await session.loadImage(header)
                Issue.record("An unsupported image version unexpectedly loaded.")
            } catch {
                #expect(error.localizedDescription == "Image version \(version) is unsupported. Expected version \(supported).")
            }
        }
        #expect(await session.evaluate("kept").value == "42")
    }
}
