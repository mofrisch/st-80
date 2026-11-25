import Foundation
import Testing
@testable import SmalltalkCore

struct ImageSaveRecoveryTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("st80-save-recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test(arguments: [false, true])
    func failedFirstSaveKeepsTheActiveJournalAndCanRetryTheSameName(attached: Bool) async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("Retry.stimage")
        let changes = folder.appendingPathComponent("Retry.changes")
        let unsaved = folder.appendingPathComponent("Unsaved.changes")
        let session = SmalltalkSession()
        if attached { try await session.startChangeLog(at: unsaved) }
        #expect(await session.evaluate("kept := 42. Counter compile: 'answer ^ 1'").error == nil)
        let before = await session.snapshot()

        // A directory at the image path fails the atomic replacement after
        // the save has created its companion files.
        try FileManager.default.createDirectory(at: image, withIntermediateDirectories: true)
        await #expect(throws: (any Error).self) {
            try await session.saveImage(to: image, workspace: "kept", transcript: "")
        }
        let failed = await session.snapshot()
        #expect(failed.changesPath == before.changesPath)
        #expect(failed.savedChangeSequence == before.savedChangeSequence)
        #expect(failed.changes.map(\.id) == before.changes.map(\.id))
        #expect(!FileManager.default.fileExists(atPath: changes.path))
        #expect(await session.evaluate("kept").value == "42")
        #expect(await session.compile("answer ^ 2", in: "Counter").error == nil)
        if attached { #expect(try SourceJournal.read(unsaved).records.last?.source == "answer ^ 2") }

        try FileManager.default.removeItem(at: image)
        try await session.saveImage(to: image, workspace: "kept", transcript: "")
        let saved = await session.snapshot()
        #expect(saved.changesPath == changes.path)
        #expect(saved.savedChangeSequence == saved.changes.last?.sequence)
        let reopened = SmalltalkSession()
        let restored = try await reopened.loadImage(from: image)
        #expect(restored.workspace == "kept")
        #expect(await reopened.evaluate("kept + Counter new answer").value == "44")
    }

    @Test func failedSaveAsPreservesThePreviousImageAndBranchesOnlyOnSuccess() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("First.stimage")
        let second = folder.appendingPathComponent("Second.stimage")
        let firstLog = folder.appendingPathComponent("First.changes")
        let secondLog = folder.appendingPathComponent("Second.changes")
        let session = SmalltalkSession()
        #expect(await session.compile("answer ^ 1", in: "Counter").error == nil)
        try await session.saveImage(to: first, workspace: "first", transcript: "")
        let firstImageBytes = try Data(contentsOf: first)
        let checkpoint = await session.snapshot().savedChangeSequence
        #expect(await session.compile("answer ^ 2", in: "Counter").error == nil)
        let logBeforeFailure = try Data(contentsOf: firstLog)

        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        await #expect(throws: (any Error).self) {
            try await session.saveImage(to: second, workspace: "second", transcript: "")
        }
        let failed = await session.snapshot()
        #expect(failed.changesPath == firstLog.path)
        #expect(failed.savedChangeSequence == checkpoint)
        #expect(try Data(contentsOf: first) == firstImageBytes)
        #expect(try Data(contentsOf: firstLog) == logBeforeFailure)
        #expect(!FileManager.default.fileExists(atPath: secondLog.path))
        #expect(await session.compile("answer ^ 3", in: "Counter").error == nil)
        #expect(try SourceJournal.read(firstLog).records.last?.source == "answer ^ 3")

        let oldImage = SmalltalkSession()
        let restored = try await oldImage.loadImage(from: first)
        #expect(restored.workspace == "first")
        #expect(restored.evaluation.savedChangeSequence == checkpoint)
        #expect(await oldImage.evaluate("Counter new answer").value == "1")
        #expect(restored.evaluation.changes.filter { $0.sequence > checkpoint }.map(\.source) == ["answer ^ 2", "answer ^ 3"])

        try FileManager.default.removeItem(at: second)
        try await session.saveImage(to: second, workspace: "second", transcript: "")
        let firstLogBytes = try Data(contentsOf: firstLog)
        #expect(try SourceJournal.read(firstLog).id != SourceJournal.read(secondLog).id)
        #expect(await session.compile("answer ^ 4", in: "Counter").error == nil)
        #expect(try Data(contentsOf: firstLog) == firstLogBytes)
        #expect(try SourceJournal.read(secondLog).records.last?.source == "answer ^ 4")
        let branched = SmalltalkSession()
        _ = try await branched.loadImage(from: second)
        #expect(await branched.evaluate("Counter new answer").value == "3")
    }

    @Test func failedSaveNeverRemovesAnExistingUnrelatedJournal() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("Occupied.stimage")
        let changes = folder.appendingPathComponent("Occupied.changes")
        let activeLog = folder.appendingPathComponent("Active.changes")
        let unrelated = SourceJournal()
        try unrelated.append(kind: .method, className: "Counter", selector: "answer", source: "answer ^ 99")
        try unrelated.attach(to: changes)
        let originalBytes = try Data(contentsOf: changes)
        let session = SmalltalkSession()
        try await session.startChangeLog(at: activeLog)
        #expect(await session.compile("answer ^ 42", in: "Counter").error == nil)
        let activeBytes = try Data(contentsOf: activeLog)
        let before = await session.snapshot()

        await #expect(throws: (any Error).self) {
            try await session.saveImage(to: image, workspace: "", transcript: "")
        }
        let failed = await session.snapshot()
        #expect(try Data(contentsOf: changes) == originalBytes)
        #expect(try Data(contentsOf: activeLog) == activeBytes)
        #expect(!FileManager.default.fileExists(atPath: image.path))
        #expect(failed.changesPath == before.changesPath)
        #expect(failed.savedChangeSequence == before.savedChangeSequence)
        #expect(await session.evaluate("Counter new answer").value == "42")
    }
}
