import Foundation
import Testing
@testable import SmalltalkCore

struct JournalForkRegressionTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("st80-journal-fork-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test(arguments: [false, true])
    func saveAsBackfillsOnlyTheDestinationJournalAndLeavesItsSourceUnchanged(failImageWrite: Bool) throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sourceLog = folder.appendingPathComponent("Original.changes")
        let image = folder.appendingPathComponent("Branched.stimage")
        let destinationLog = folder.appendingPathComponent("Branched.changes")
        let donor = SmalltalkRuntime()
        let prepared = donor.run("""
            Object subclass: #PortableOwner instanceVariableNames: 'payload'.
            PortableOwner compile: 'answer ^ 42'.
            PortableOwner compileClass: 'answer ^ 73'.
            Counter compile: 'value ^ 99'.
            nil
            """)
        try #require(prepared.error == nil)
        let (runtime, _) = try ImageCodec.decode(ImageCodec.encode(donor, workspace: "", transcript: ""))
        let original = runtime.journal
        let history = try original.append(kind: .method, className: "Counter", selector: "historyOnly", source: "historyOnly ^ 1")
        try original.attach(to: sourceLog)
        original.savedSequence = original.sequence
        let oldBytes = try Data(contentsOf: sourceLog)
        let oldMemory = try original.data()
        let oldCheckpoint = original.savedSequence
        if failImageWrite {
            try FileManager.default.createDirectory(at: image, withIntermediateDirectories: true)
            #expect(throws: (any Error).self) {
                try ImageFiles.save(runtime, to: image, workspace: "", transcript: "")
            }
            #expect(runtime.journal === original)
            #expect(!FileManager.default.fileExists(atPath: destinationLog.path))
        } else {
            try ImageFiles.save(runtime, to: image, workspace: "", transcript: "")
            #expect(runtime.journal !== original)
            #expect(runtime.journal.id != original.id)
            #expect(runtime.journal.url == destinationLog)
            let destination = try SourceJournal.read(destinationLog)
            #expect(destination.records.first?.id == history.id)
            #expect(destination.records.contains { $0.kind == .classDefinition && $0.className == "PortableOwner" && $0.fields == ["payload"] })
            #expect(destination.records.contains { $0.className == "PortableOwner" && $0.side == .instance && $0.source == "answer ^ 42" })
            #expect(destination.records.contains { $0.className == "PortableOwner" && $0.side == .classSide && $0.source == "answer ^ 73" })
            #expect(destination.records.contains { $0.className == "Counter" && $0.source == "value ^ 99" })
            let (restored, _) = try ImageFiles.load(image)
            #expect(restored.run("PortableOwner new answer + PortableOwner answer + Counter new value").value == "214")
        }
        // Test both the file and the still-referenced old journal object.
        #expect(try Data(contentsOf: sourceLog) == oldBytes)
        #expect(try original.data() == oldMemory)
        #expect(original.records.map(\.id) == [history.id])
        #expect(original.sequence == 1)
        #expect(original.savedSequence == oldCheckpoint)
        #expect(original.url == sourceLog)
    }
}
