import Foundation
import Testing
@testable import SmalltalkCore

struct SourceJournalTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("st80-journal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func classMethodsAndTheirLexicalSuperSurviveBothImageFormats() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("ClassSide.stimage")
        let log = url.deletingPathExtension().appendingPathExtension("changes")
        let session = SmalltalkSession()
        let definitions = await session.evaluate("""
            Object subclass: #SideBase instanceVariableNames: 'count'.
            SideBase subclass: #SideChild instanceVariableNames: ''.
            SideBase compile: 'answer ^ 3'.
            SideBase compileClass: 'answer ^ 40'.
            SideBase compileClass: 'make ^ super new'.
            SideChild compileClass: 'answer ^ super answer + 2'.
            SideChild compileClass: 'callback ^ [ super answer + 1 ]'.
            callback := SideChild callback
            """)
        #expect(definitions.error == nil)
        #expect(await session.evaluate("SideChild answer").value == "42")
        #expect(await session.evaluate("SideChild make answer").value == "3")
        #expect(await session.evaluate("SideBase respondsTo: #make").value == "true")
        #expect(await session.evaluate("SideChild classMethodNames").value == "#('answer' 'callback')")
        #expect(await session.evaluate("SideChild classMethodSourceAt: #answer asString").value == "'answer ^ super answer + 2'")
        #expect(await session.evaluate("SideChild new respondsTo: #callback").value == "false")

        try await session.saveImage(to: url, workspace: "", transcript: "")
        let records = try SourceJournal.read(log).records.filter { $0.className == "SideBase" && $0.selector == "answer" }
        #expect(records.map(\.side) == [.instance, .classSide])
        let classVersion = try #require(records.first { $0.side == .classSide })
        let portable = try await session.imageData()
        let reopened = SmalltalkSession()
        _ = try await reopened.loadImage(portable)
        #expect(await reopened.evaluate("callback value").value == "41")
        #expect(await reopened.evaluate("SideChild answer").value == "42")

        _ = try await reopened.loadImage(from: url)
        #expect(await reopened.evaluate("callback value").value == "41")
        #expect(await reopened.evaluate("SideChild make answer").value == "3")
        #expect(await reopened.compile("answer ^ 99", in: "SideBase", side: .classSide).error == nil)
        #expect(await reopened.evaluate("SideChild answer").value == "101")
        #expect(await reopened.restoreChange(classVersion.id).value == "Restored: SideBase class » answer")
        #expect(await reopened.evaluate("SideChild answer").value == "42")
        #expect(await reopened.evaluate("SideChild new answer").value == "3")
    }

    @Test func acceptedMethodsAreDurableBeforeSavingAndRejectedEditsNeverInstall() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let log = folder.appendingPathComponent("Unsaved.changes")
        let session = SmalltalkSession()
        try await session.startChangeLog(at: log)
        let accepted = await session.compile("answer ^ 42", in: "Counter")
        #expect(accepted.error == nil)
        let journal = try SourceJournal.read(log)
        #expect(journal.records.last?.source == "answer ^ 42")
        #expect(journal.records.last?.className == "Counter")
        let invalid = await session.compile("answer ^ (", in: "Counter")
        #expect(invalid.error != nil)
        #expect(try SourceJournal.read(log).sequence == journal.sequence)
        // An external writer invalidates the log's append position. An accepted
        // method must never become live when its durable journal write failed.
        let file = try FileHandle(forWritingTo: log)
        try file.seekToEnd(); try file.write(contentsOf: Data("external\n".utf8)); try file.close()
        let failed = await session.compile("answer ^ 73", in: "Counter")
        #expect(failed.error?.contains("outside") == true)
        let current = await session.evaluate("Counter new answer")
        #expect(current.value == "42")
    }

    @Test func fileImageUsesExecutableCodeAndExternalSourcesWhilePortableDataStillLoads() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("World.stimage")
        let session = SmalltalkSession()
        _ = await session.evaluate("Counter compile: 'answer ^ 42'. counter := Counter new. counter add: 7")
        try await session.saveImage(to: url, workspace: "counter value", transcript: "hello")
        let bytes = try Data(contentsOf: url)
        let saved = try JSONDecoder().decode(ImageFileArchive.self, from: bytes)
        #expect(saved.version == 4)
        #expect(saved.memory.classes.allSatisfy { $0.methods.isEmpty })
        #expect(saved.methods.contains { $0.className == "Counter" && $0.code.selector == "answer" && $0.changeID != nil })
        #expect(!String(decoding: bytes, as: UTF8.self).contains("answer ^ 42"))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(saved.sourcesFile).path))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("World.changes").path))
        let restarted = SmalltalkSession()
        let loaded = try await restarted.loadImage(from: url)
        #expect(loaded.evaluation.error == nil)
        #expect(loaded.evaluation.savedChangeSequence == saved.checkpoint)
        let value = await restarted.evaluate("counter value + counter answer")
        #expect(value.value == "49")
        let portable = try await restarted.imageData()
        let copied = SmalltalkSession()
        _ = try await copied.loadImage(portable)
        let original = await copied.evaluate("counter answer")
        #expect(original.value == "42")
    }

    @Test func unsavedCodeAfterSnapshotIsReviewedAndRecoveredWithoutReplayingObjectMutations() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Recovery.stimage")
        let original = SmalltalkSession()
        _ = await original.evaluate("Counter compile: 'answer ^ 1'. counter := Counter new. counter add: 10")
        try await original.saveImage(to: url, workspace: "counter value", transcript: "")
        let after = await original.evaluate("""
        Counter compile: 'answer ^ 2'.
        Object subclass: #RecoveredClass instanceVariableNames: ''.
        RecoveredClass compile: 'answer ^ 99'.
        counter add: 100
        """)
        #expect(after.error == nil)
        let restarted = SmalltalkSession()
        let loaded = try await restarted.loadImage(from: url)
        let state = await restarted.evaluate("counter value + counter answer")
        #expect(state.value == "11")
        #expect(!state.classes.contains { $0.name == "RecoveredClass" })
        let pending = loaded.evaluation.changes.filter { $0.sequence > loaded.evaluation.savedChangeSequence }
        #expect(pending.count == 3)
        for change in pending {
            let recovered = await restarted.restoreChange(change.id)
            #expect(recovered.error == nil)
        }
        let restored = await restarted.evaluate("counter value + counter answer + RecoveredClass new answer")
        #expect(restored.value == "111")
        try await restarted.saveImage(to: url, workspace: "", transcript: "")
        let third = SmalltalkSession()
        let savedAgain = try await third.loadImage(from: url)
        #expect(savedAgain.evaluation.changes.allSatisfy { $0.sequence <= savedAgain.evaluation.savedChangeSequence })
        let verified = await third.evaluate("RecoveredClass new answer")
        #expect(verified.value == "99")
    }

    @Test func interruptedFinalRecordIsIgnoredAndTheNextEditRepairsItsTail() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Interrupted.stimage")
        let original = SmalltalkSession()
        try await original.saveImage(to: url, workspace: "", transcript: "")
        _ = await original.compile("answer ^ 17", in: "Counter")
        let log = url.deletingPathExtension().appendingPathExtension("changes")
        let file = try FileHandle(forWritingTo: log)
        try file.seekToEnd(); try file.write(contentsOf: Data("{\"incomplete\":".utf8)); try file.close()
        let restarted = SmalltalkSession()
        let loaded = try await restarted.loadImage(from: url)
        #expect(loaded.evaluation.changes.last?.source == "answer ^ 17")
        let edit = await restarted.compile("answer ^ 23", in: "Counter")
        #expect(edit.error == nil)
        let journal = try SourceJournal.read(log)
        #expect(journal.records.last?.source == "answer ^ 23")
        #expect(!String(decoding: try Data(contentsOf: log), as: UTF8.self).contains("incomplete"))
    }

    @Test func saveAsBranchesHistoryAndNeverOverwritesAnUnrelatedLog() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("First.stimage"), second = folder.appendingPathComponent("Second.stimage")
        let session = SmalltalkSession()
        _ = await session.compile("answer ^ 1", in: "Counter")
        try await session.saveImage(to: first, workspace: "", transcript: "")
        let firstLog = first.deletingPathExtension().appendingPathExtension("changes")
        let firstBytes = try Data(contentsOf: firstLog)
        try await session.saveImage(to: second, workspace: "", transcript: "")
        _ = await session.compile("answer ^ 2", in: "Counter")
        #expect(try Data(contentsOf: firstLog) == firstBytes)
        let firstID = try SourceJournal.read(firstLog).id
        let secondLog = try SourceJournal.read(second.deletingPathExtension().appendingPathExtension("changes"))
        #expect(firstID != secondLog.id)
        #expect(secondLog.records.last?.source == "answer ^ 2")
        let stranger = folder.appendingPathComponent("Stranger.changes")
        try Data("Do not overwrite".utf8).write(to: stranger)
        await #expect(throws: (any Error).self) { try await session.saveImage(to: folder.appendingPathComponent("Stranger.stimage"), workspace: "", transcript: "") }
        #expect(try String(contentsOf: stranger, encoding: .utf8) == "Do not overwrite")
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("Stranger.stimage").path))
    }

    @Test func missingOrMismatchedCompanionsLeaveTheCurrentWorldIntact() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Missing.stimage")
        let donor = SmalltalkSession()
        try await donor.saveImage(to: url, workspace: "", transcript: "")
        let image = try JSONDecoder().decode(ImageFileArchive.self, from: Data(contentsOf: url))
        let sourcesURL = folder.appendingPathComponent(image.sourcesFile)
        let sources = try Data(contentsOf: sourcesURL)
        try FileManager.default.removeItem(at: sourcesURL)
        let current = SmalltalkSession()
        _ = await current.evaluate("kept := 42")
        await #expect(throws: (any Error).self) { try await current.loadImage(from: url) }
        let kept = await current.evaluate("kept")
        #expect(kept.value == "42")
        try sources.write(to: sourcesURL)
        let changesURL = folder.appendingPathComponent(image.changesFile)
        try FileManager.default.removeItem(at: changesURL)
        try SourceJournal().attach(to: changesURL)
        await #expect(throws: (any Error).self) { try await current.loadImage(from: url) }
        let stillKept = await current.evaluate("kept")
        #expect(stillKept.value == "42")
    }

    @Test func logsFromAnUnsavedWorldCanBeImportedWithoutExecutingThem() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Unsaved.changes")
        let original = SmalltalkSession()
        try await original.startChangeLog(at: url)
        _ = await original.evaluate("Object subclass: #LostClass instanceVariableNames: ''. LostClass compile: 'answer ^ 73'")
        let fresh = SmalltalkSession()
        let imported = try await fresh.importChanges(from: url)
        #expect(!imported.classes.contains { $0.name == "LostClass" })
        #expect(imported.changes.count == 2)
        for record in imported.changes { #expect(await fresh.restoreChange(record.id).error == nil) }
        let recovered = await fresh.evaluate("LostClass new answer")
        #expect(recovered.value == "73")
    }

    @Test func theShippedBaseVersionCanBeRestoredAndTheRestoreIsJournaled() async throws {
        let session = SmalltalkSession()
        let base = try #require(await session.baseVersion(of: "value", in: "Counter"))
        _ = await session.compile("value ^ 99", in: "Counter")
        let restored = await session.restoreChange(base.id)
        #expect(restored.error == nil)
        #expect(restored.changes.last?.source == base.source)
        let result = await session.evaluate("Counter new value")
        #expect(result.value == "0")
    }

    @Test func aSecondSessionCannotSilentlyOverwriteTheFirstSessionsLog() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Shared.stimage")
        let first = SmalltalkSession()
        try await first.saveImage(to: url, workspace: "", transcript: "")
        let second = SmalltalkSession()
        _ = try await second.loadImage(from: url)
        #expect(await first.compile("answer ^ 42", in: "Counter").error == nil)
        let rejected = await second.compile("answer ^ 73", in: "Counter")
        #expect(rejected.error != nil)
        let log = try SourceJournal.read(url.deletingPathExtension().appendingPathExtension("changes"))
        #expect(log.records.last?.source == "answer ^ 42")
        let unchanged = await second.evaluate("Counter new respondsTo: #answer")
        #expect(unchanged.value == "false")
    }
}
