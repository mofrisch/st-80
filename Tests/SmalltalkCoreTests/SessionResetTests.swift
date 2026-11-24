import Foundation
import Testing
@testable import SmalltalkCore

struct SessionResetTests {
    @Test func journalFailureKeepsTheWorldAndItsDurableJournal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("st80-reset-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("Original.changes")
        let session = SmalltalkSession()
        try await session.startChangeLog(at: log)
        #expect(await session.evaluate("kept := 42. Counter compile: 'answer ^ 7'").error == nil)
        let before = try SourceJournal.read(log)

        await #expect(throws: (any Error).self) {
            try await session.reset(startingChangeLogAt: directory.appendingPathComponent("missing/New.changes"))
        }

        #expect(await session.evaluate("kept + Counter new answer").value == "49")
        let accepted = await session.compile("answer ^ 8", in: "Counter")
        #expect(accepted.executionError == nil)
        #expect(accepted.changesPath == log.path)
        let after = try SourceJournal.read(log)
        #expect(after.id == before.id)
        #expect(after.sequence == before.sequence + 1)
        #expect(after.records.last?.source == "answer ^ 8")
    }

    @Test func successfulResetStartsWithAnAttachedJournalAndFreshWorld() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("st80-reset-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("Fresh.changes")
        let session = SmalltalkSession()
        _ = await session.evaluate("kept := 42. Counter compile: 'value ^ 99'")

        let reset = try await session.reset(startingChangeLogAt: log)
        #expect(reset.error == nil)
        #expect(reset.changesPath == log.path)
        #expect(reset.changes.isEmpty)
        #expect(await session.evaluate("Counter new value").value == "0")
        #expect(await session.evaluate("kept").executionError != nil)
        #expect(await session.compile("answer ^ 17", in: "Counter").error == nil)
        #expect(try SourceJournal.read(log).records.last?.source == "answer ^ 17")
    }
}
