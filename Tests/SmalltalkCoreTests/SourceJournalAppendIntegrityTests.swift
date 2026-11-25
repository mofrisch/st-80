import Darwin
import Foundation
import Testing
@testable import SmalltalkCore

struct SourceJournalAppendIntegrityTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("st80-append-integrity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test(arguments: ["foreignHeader", "changedRecord"])
    func sameSizeExternalEditsRejectAppendBeforeInstallingCode(tampering: String) async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = folder.appendingPathComponent("Active.changes")
        let session = SmalltalkSession()
        try await session.startChangeLog(at: log)
        // Two successful appends also exercise the cached validation path.
        try #require(await session.compile("answer ^ 1", in: "Counter").error == nil)
        try #require(await session.compile("another ^ 3", in: "Counter").error == nil)
        let before = await session.snapshot()
        let bytes = try Data(contentsOf: log)
        let journal = try SourceJournal.read(log)
        let text = try #require(String(data: bytes, encoding: .utf8))
        let tampered: Data
        if tampering == "foreignHeader" {
            let replacementID = UUID().uuidString
            tampered = Data(text.replacingOccurrences(of: journal.id, with: replacementID).utf8)
            try tampered.write(to: log, options: .atomic)
        } else {
            tampered = Data(text.replacingOccurrences(of: "answer ^ 1", with: "answer ^ 9").utf8)
            // Preserve the inode as well as the byte count; size and identity
            // alone cannot detect a changed existing record.
            let file = try FileHandle(forWritingTo: log)
            defer { try? file.close() }
            var previousStatus = stat()
            try #require(fstat(file.fileDescriptor, &previousStatus) == 0)
            try file.write(contentsOf: tampered)
            try file.synchronize()
            let times = [previousStatus.st_atimespec, previousStatus.st_mtimespec]
            let restoredTime = times.withUnsafeBufferPointer { futimens(file.fileDescriptor, $0.baseAddress) }
            try #require(restoredTime == 0)
        }
        try #require(tampered.count == bytes.count && tampered != bytes)

        let rejected = await session.compile("answer ^ 2", in: "Counter")
        #expect(rejected.error?.contains("modified outside this session") == true)
        #expect(rejected.changes.map(\.id) == before.changes.map(\.id))
        #expect(rejected.savedChangeSequence == before.savedChangeSequence)
        #expect(try Data(contentsOf: log) == tampered)
        #expect(await session.evaluate("Counter new answer").value == "1")
        let count = await session.worker.submit { $0.journal.records.count }
        #expect(count == 2)

        try bytes.write(to: log, options: .atomic)
        let recovered = await session.compile("answer ^ 4", in: "Counter")
        #expect(recovered.error == nil)
        #expect(await session.evaluate("Counter new answer").value == "4")
        #expect(try SourceJournal.read(log).records.count == 3)
    }

    @Test func metadataChangesWithIdenticalRecordsRevalidateAndRemainAppendable() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = folder.appendingPathComponent("Unchanged.changes")
        let journal = SourceJournal()
        try journal.attach(to: log)
        try journal.append(kind: .method, className: "Counter", selector: "answer", source: "answer ^ 1")
        let unchanged = try Data(contentsOf: log)
        // A byte-identical rewrite changes the file stamp but does not change
        // journal ownership or history. It must take the full validation path.
        try unchanged.write(to: log, options: .atomic)
        try journal.append(kind: .method, className: "Counter", selector: "answer", source: "answer ^ 2")
        let reopened = try SourceJournal.read(log)
        #expect(reopened.id == journal.id)
        #expect(reopened.records.map(\.source) == ["answer ^ 1", "answer ^ 2"])
        try journal.withValidatedFile {}
    }

    @Test func aPreviouslyReadIncompleteTailIsStillRepairedByAppend() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = folder.appendingPathComponent("Interrupted.changes")
        let original = SourceJournal()
        try original.append(kind: .method, className: "Counter", selector: "answer", source: "answer ^ 1")
        try original.attach(to: log)
        let file = try FileHandle(forWritingTo: log)
        try file.seekToEnd()
        try file.write(contentsOf: Data("{\"incomplete\":".utf8))
        try file.close()

        let recovered = try SourceJournal.read(log)
        try recovered.append(kind: .method, className: "Counter", selector: "answer", source: "answer ^ 2")
        let reopened = try SourceJournal.read(log)
        #expect(reopened.records.map(\.source) == ["answer ^ 1", "answer ^ 2"])
        #expect(!String(decoding: try Data(contentsOf: log), as: UTF8.self).contains("incomplete"))
    }

    @Test func failedAppendAfterRepairingAnIncompleteTailCanRetryWithoutReloading() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = folder.appendingPathComponent("RetryInterrupted.changes")
        let original = SourceJournal()
        try original.append(kind: .method, className: "Counter", selector: "answer", source: "answer ^ 1")
        try original.attach(to: log)
        let validBytes = try Data(contentsOf: log)
        let file = try FileHandle(forWritingTo: log)
        try file.seekToEnd()
        try file.write(contentsOf: Data("{\"incomplete\":".utf8))
        try file.close()

        let recovered = try SourceJournal.read(log)
        recovered.savedSequence = 1
        do {
            try recovered.append(kind: .method, className: "Counter", selector: "answer", source: "answer ^ 2") { file, bytes in
                #expect(try file.seekToEnd() == UInt64(validBytes.count))
                try file.write(contentsOf: bytes.prefix(1))
                throw SmalltalkError("Simulated failure after a partial record write.")
            }
            Issue.record("The injected write failure did not propagate.")
        } catch let error as SmalltalkError {
            #expect(error.message == "Simulated failure after a partial record write.")
        }
        #expect(try Data(contentsOf: log) == validBytes)
        #expect(recovered.records.map(\.source) == ["answer ^ 1"])
        #expect(recovered.savedSequence == 1)

        // Neither reloading nor constructing another journal is needed after
        // rolling back our own partial write and removing the interrupted tail.
        try recovered.withValidatedFile {}
        try recovered.append(kind: .method, className: "Counter", selector: "answer", source: "answer ^ 3")
        let reopened = try SourceJournal.read(log)
        #expect(reopened.id == original.id)
        #expect(reopened.records.map(\.source) == ["answer ^ 1", "answer ^ 3"])
        #expect(reopened.sequence == 2)
    }

    @Test func failedImportRollsBackEvenACompleteFirstRecordAndCanRetry() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("ImportTarget.changes")
        let target = SourceJournal()
        let existing = try target.append(kind: .method, className: "Counter", selector: "value", source: "value ^ 1")
        target.savedSequence = target.sequence
        try target.attach(to: url)
        let before = try Data(contentsOf: url)

        let incoming = SourceJournal()
        try incoming.append(kind: .classDefinition, className: "Imported", superclass: "Object", fields: ["value"],
                            source: "Object subclass: #Imported instanceVariableNames: 'value'")
        try incoming.append(kind: .method, className: "Imported", selector: "answer", side: .classSide, source: "answer ^ 42")

        do {
            try target.appendImportedRecords(incoming.records) { file, bytes in
                let firstRecordLength = try #require(bytes.firstIndex(of: 10)) + 1
                try #require(firstRecordLength < bytes.count - 1)
                try file.write(contentsOf: bytes.prefix(firstRecordLength + 1))
                throw SmalltalkError("Simulated failure during the second imported record.")
            }
            Issue.record("The injected write failure did not propagate.")
        } catch let error as SmalltalkError {
            #expect(error.message == "Simulated failure during the second imported record.")
        }

        #expect(try Data(contentsOf: url) == before)
        #expect(target.records.map(\.id) == [existing.id])
        #expect(target.sequence == 1)
        #expect(target.savedSequence == 1)

        try target.appendImportedRecords(incoming.records)
        let reopened = try SourceJournal.read(url)
        let imported = Array(reopened.records.dropFirst())
        #expect(reopened.id == target.id)
        #expect(reopened.records.map(\.sequence) == [1, 2, 3])
        #expect(reopened.records.first?.id == existing.id)
        #expect(imported.map(\.source) == incoming.records.map(\.source))
        #expect(imported.first?.fields == ["value"])
        #expect(imported.last?.side == .classSide)
        #expect(Set(imported.map(\.id)).isDisjoint(with: incoming.records.map(\.id)))
        #expect(target.savedSequence == 1)
    }
}
