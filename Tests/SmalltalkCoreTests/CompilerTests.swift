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

    @Test func malformedCompilerOutputCannotReplaceAnInstalledMethod() async {
        let session = SmalltalkSession()
        #expect(await session.compile("answer ^ 42", in: "Counter").executionError == nil)
        #expect(await session.compile("method: source ^ #(wrong)", in: "STCompiler").executionError == nil)
        let attempted = await session.compile("answer ^ 99", in: "Counter")
        #expect(attempted.executionError?.contains("Syntaxbaum") == true)
        #expect(await session.evaluate("Counter new answer").value == "42")
    }

    @Test func imageLoadRejectsOldVersionsBeforeReplacingTheSession() async throws {
        let session = SmalltalkSession()
        _ = await session.evaluate("kept := 42")
        for version in [1, 2, 3] {
            let oldHeader = Data(#"{"format":"st80-image","version":\#(version)}"#.utf8)
            await #expect(throws: SmalltalkError.self) {
                _ = try await session.loadImage(oldHeader)
            }
        }
        #expect(await session.evaluate("kept").value == "42")
    }
}
