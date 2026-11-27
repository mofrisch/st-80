import Foundation
import Testing
@testable import SmalltalkCore

private final class SmalltalkTestBundleToken {}

struct SmalltalkTestFrameworkTests {
    @Test func bundledSmalltalkTestsPassInAFreshImage() async throws {
        let session = SmalltalkSession()
        let execution = await session.evaluate("testReport := TestRunner runAll. testReport summary")
        try #require(execution.executionError == nil, "\(execution.executionError ?? "")")
        let report = try await inspectReport(in: session)
        #expect(report.passed, "\(execution.value ?? "No test summary")")
        for message in report.diagnostics { Issue.record(Comment(rawValue: message)) }
        #expect(await session.evaluate("CounterTest run passedCount").value == "2")
        #expect(await session.evaluate("CollectionsTest run passedCount").value == "2")
        #expect(await session.evaluate("UIBindingTest run passedCount").value == "2")
        #expect(await session.evaluate("ANSISmalltalkTest run passedCount").value == "64")
    }

    @Test func ansiFileStreamSmalltalkTestsPass() async throws {
        let directory = try newFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = SmalltalkSession()
        try await session.worker.submitThrowing { runtime in
            runtime.globals["ansiFileStreamDirectory"] = .string(directory.path)
        }
        try await load(fixtureDirectory().appendingPathComponent("Fixtures/ANSIFileStreams.st"), in: session)
        let execution = await session.evaluate("testReport := ANSIFileStreamTest run. testReport summary")
        try #require(execution.executionError == nil, "\(execution.executionError ?? "")")
        let report = try await inspectReport(in: session)
        #expect(report.passed, "\(execution.value ?? "No test summary")")
        for message in report.diagnostics { Issue.record(Comment(rawValue: message)) }
        #expect(await session.evaluate("testReport passedCount").value == "6")
        let text = try String(contentsOf: directory.appendingPathComponent("text.txt"), encoding: .utf8)
        #expect(text == "Grüße 猫\t!\n")
        let binary = try Data(contentsOf: directory.appendingPathComponent("bytes.bin"))
        #expect(binary == Data([0, 255, 128, 255, 42]))
    }

    @Test func fileStreamsReadAcrossBuffersAndPreserveTheSuffixWhenOverwritingText() async throws {
        let directory = try newFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("boundary.txt")
        let prefix = "\u{FEFF}" + String(repeating: "x", count: 4_092)
        let suffix = String(repeating: "y", count: 9_000)
        try Data((prefix + "🐱" + suffix).utf8).write(to: path)
        let session = SmalltalkSession()
        try await session.worker.submitThrowing { runtime in
            runtime.globals["filePath"] = .string(path.path)
        }
        let read = await session.evaluate("""
            fileReader := FileStream read: filePath.
            fileReader skip: 4093.
            Array with: (fileReader contents at: 1) codePoint
                with: fileReader peek with: (fileReader next: 2) with: fileReader position
            """)
        #expect(read.error == nil)
        #expect(read.value == "#(65279 $🐱 '🐱y' 4095)")
        let write = await session.evaluate("""
            fileWriter := FileStream write: filePath mode: #append.
            fileWriter position: 4093.
            fileWriter nextPut: $é.
            fileWriter position: 4094.
            fileWriter nextPut: $猫; close.
            fileReader close
            """)
        #expect(write.error == nil)
        #expect(try Data(contentsOf: path) == Data((prefix + "é猫" + suffix.dropFirst()).utf8))
    }

    @Test func fileStreamCollectionLimitsLeaveLargerFilesReadableInChunks() async throws {
        let directory = try newFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("large.bin")
        let output = directory.appendingPathComponent("copy.bin")
        let bytes = Data(repeating: 255, count: 70_000)
        try bytes.write(to: path)
        let session = SmalltalkSession()
        try await session.worker.submitThrowing { runtime in
            runtime.globals["filePath"] = .string(path.path)
            runtime.globals["outputPath"] = .string(output.path)
        }
        let execution = await session.evaluate("""
            fileReader := FileStream read: filePath type: #binary.
            contentsError := [ fileReader contents. false ] on: Error do: [ :error | true ].
            readError := [ fileReader next: 70000. false ] on: Error do: [ :error | true ].
            positionAfterError := fileReader position.
            firstChunk := fileReader next: 65535.
            secondChunk := fileReader next: 4465.
            fileReader close.
            fileWriter := FileStream write: outputPath mode: #create check: true type: #binary.
            fileWriter nextPutAll: firstChunk; nextPutAll: secondChunk; close.
            Array with: contentsError & readError with: positionAfterError with: firstChunk size with: secondChunk size
            """)
        #expect(execution.error == nil)
        #expect(execution.value == "#(true 0 65535 4465)")
        #expect(try Data(contentsOf: output) == bytes)
    }

    @Test func runnerSeparatesFailuresFromErrorsAndAlwaysAttemptsCleanup() async throws {
        let session = SmalltalkSession()
        let bundled = await session.evaluate("TestRunner runAll testCount")
        let bundledCount = try #require(bundled.value.flatMap { Int($0) })
        try await load(fixtureDirectory().appendingPathComponent("Fixtures/Runner.st"), in: session)
        let execution = await session.evaluate("""
        testReport := TestRunner runAll.
        runnerOutcomes := testReport outcomes select: [ :each |
            #(#RunnerCase #RunnerCleanupCase #RunnerLastCase) includes: each testClass name ].
        testReport summary
        """)
        try #require(execution.executionError == nil, "\(execution.executionError ?? "")")
        #expect(execution.value == "'\(bundledCount + 6) total, \(bundledCount + 2) passed, 1 failed, 3 with errors'")
        #expect(await session.evaluate("testReport isSuccess").value == "false")
        #expect(await session.evaluate("runnerOutcomes collect: [ :each | each selector ]").value
                == "#(#testAssertion #testDivision #testLimit #testPass #testSkippedAfterSetup #testStillRuns)")
        #expect(await session.evaluate("runnerOutcomes collect: [ :each | each status ]").value
                == "#(#failure #error #error #passed #error #passed)")
        #expect(await session.evaluate("runnerSetups").value == "6")
        #expect(await session.evaluate("runnerCleanups").value == "6")
        #expect(await session.evaluate("runnerUnreachable").value == "0")

        let assertion = await session.evaluate("((runnerOutcomes at: 1) diagnostics at: 1)").value
        #expect(assertion == "#(#test #failure 'Expected 99, got 42.' 2 5)")
        let division = await session.evaluate("((runnerOutcomes at: 2) diagnostics at: 1) at: 3").value
        #expect(division?.contains("Division by zero") == true)
        let limit = await session.evaluate("((runnerOutcomes at: 3) diagnostics at: 1) at: 3").value
        #expect(limit?.contains("100,000 steps") == true)
        let phases = await session.evaluate("((runnerOutcomes at: 5) diagnostics) collect: [ :each | each at: 1 ]")
        #expect(phases.value == "#(#setUp #tearDown)")
    }

    @Test func runnerSupportsAnExplicitTestAndRejectsAnEmptyOrUnknownSelection() async throws {
        let session = SmalltalkSession()
        #expect(await session.evaluate("TestCase run isSuccess").value == "false")
        try await load(fixtureDirectory().appendingPathComponent("Fixtures/Runner.st"), in: session)

        let single = await session.evaluate("(RunnerCase run: #testPass) isSuccess")
        #expect(single.executionError == nil)
        #expect(single.value == "true")
        #expect(await session.evaluate("RunnerCase run testCount").value == "4")
        #expect(await session.evaluate("RunnerLastCase run testCount").value == "1")
        #expect(await session.evaluate("RunnerCase run: #testMissing").executionError?.contains("No test named testMissing") == true)
    }

    private func fixtureDirectory() throws -> URL {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: SmalltalkTestBundleToken.self)
        #endif
        let resources = try #require(bundle.resourceURL)
        return resources.appendingPathComponent("SmalltalkTests", isDirectory: true)
    }

    private func newFixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("st80-file-streams-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func load(_ source: URL, in session: SmalltalkSession) async throws {
        let execution = await session.evaluate(try String(contentsOf: source, encoding: .utf8))
        try #require(execution.executionError == nil, "\(source.lastPathComponent): \(execution.executionError ?? "")")
    }

    private func inspectReport(in session: SmalltalkSession) async throws -> (passed: Bool, diagnostics: [String]) {
        try await session.worker.submitThrowing { runtime in
            guard let report = runtime.globals["testReport"] else { throw SmalltalkError("Missing test report.") }
            runtime.steps = 0
            let passed = try runtime.boolean(runtime.send(report, "isSuccess", []))
            let outcomes = try elements(runtime.send(report, "outcomes", []))
            var messages: [String] = []
            for outcome in outcomes {
                let diagnostics = try elements(runtime.send(outcome, "diagnostics", []))
                guard !diagnostics.isEmpty else { continue }
                let testClass = try runtime.send(outcome, "testClass", [])
                let name = try runtime.symbol(runtime.send(testClass, "name", []))
                let selector = try runtime.symbol(runtime.send(outcome, "selector", []))
                for diagnostic in diagnostics {
                    let fields = try elements(diagnostic)
                    guard fields.count == 5 else { throw SmalltalkError("Invalid test diagnostic.") }
                    let phase = try runtime.symbol(fields[0])
                    let message = try runtime.string(fields[2])
                    messages.append("\(name)>>\(selector) (\(phase)): \(message) [\(runtime.printValue(fields[3])):\(runtime.printValue(fields[4]))]")
                }
            }
            return (passed, messages)
        }
    }

    private func elements(_ value: Value) throws -> [Value] {
        guard case .array(let array) = value else { throw SmalltalkError("Expected a test result array.") }
        return array.elements
    }
}
