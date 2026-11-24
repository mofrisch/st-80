import Darwin
import Foundation
import Testing
@testable import SmalltalkCore

struct ImageJournalIntegrityTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("st80-image-integrity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test(arguments: ["missing", "truncated", "replaced", "same-size edit", "appended"])
    func damagedAssociatedJournalCannotReplaceTheLastGoodImage(_ damage: String) async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("World.stimage")
        let changes = folder.appendingPathComponent("World.changes")
        let session = SmalltalkSession()
        #expect(await session.compile("answer ^ 41", in: "Counter").error == nil)
        try await session.saveImage(to: image, workspace: "first", transcript: "")
        let goodImage = try Data(contentsOf: image)
        #expect(await session.evaluate("kept := 7. Counter compile: 'answer ^ 42'").error == nil)
        let before = await session.snapshot()
        let goodLog = try Data(contentsOf: changes)
        switch damage {
        case "missing":
            try FileManager.default.removeItem(at: changes)
        case "truncated":
            try goodLog.dropLast().write(to: changes)
        case "replaced":
            let id = try SourceJournal.read(changes).id
            let replacement = String(decoding: goodLog, as: UTF8.self).replacingOccurrences(of: id, with: UUID().uuidString)
            try Data(replacement.utf8).write(to: changes, options: .atomic)
        case "same-size edit":
            let replacement = String(decoding: goodLog, as: UTF8.self).replacingOccurrences(of: "answer ^ 42", with: "answer ^ 43")
            try Data(replacement.utf8).write(to: changes)
        default:
            let external = try SourceJournal.read(changes)
            try external.append(kind: .method, className: "Counter", selector: "answer", source: "answer ^ 99")
        }
        let damagedLog = try? Data(contentsOf: changes)

        await #expect(throws: (any Error).self) {
            try await session.saveImage(to: image, workspace: "second", transcript: "")
        }
        let failed = await session.snapshot()
        #expect(try Data(contentsOf: image) == goodImage)
        #expect((try? Data(contentsOf: changes)) == damagedLog)
        #expect(failed.savedChangeSequence == before.savedChangeSequence)
        #expect(failed.changesPath == before.changesPath)
        #expect(failed.changes.map(\.id) == before.changes.map(\.id))
        #expect(await session.evaluate("kept + Counter new answer").value == "49")

        // Restoring the exact companion makes the previous image usable again,
        // and allows this live session to retry without losing its edits.
        try goodLog.write(to: changes, options: .atomic)
        let previous = SmalltalkSession()
        let restored = try await previous.loadImage(from: image)
        #expect(restored.workspace == "first")
        #expect(await previous.evaluate("Counter new answer").value == "41")
        try await session.saveImage(to: image, workspace: "second", transcript: "")
        let current = SmalltalkSession()
        _ = try await current.loadImage(from: image)
        #expect(await current.evaluate("kept + Counter new answer").value == "49")
    }

    @Test func savingRequiresExclusiveAccessToItsAssociatedJournal() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("Locked.stimage")
        let changes = folder.appendingPathComponent("Locked.changes")
        let session = SmalltalkSession()
        try await session.saveImage(to: image, workspace: "first", transcript: "")
        let original = try Data(contentsOf: image)
        let file = try FileHandle(forUpdating: changes)
        defer { try? file.close() }
        try #require(flock(file.fileDescriptor, LOCK_EX | LOCK_NB) == 0)
        await #expect(throws: (any Error).self) {
            try await session.saveImage(to: image, workspace: "second", transcript: "")
        }
        #expect(try Data(contentsOf: image) == original)
        #expect(flock(file.fileDescriptor, LOCK_UN) == 0)
        try await session.saveImage(to: image, workspace: "second", transcript: "")
    }

    @Test(arguments: ["changes", "sources", "uppercase changes"])
    func collidingNamesFailBeforeAddingJournalRecordsOrCompanions(_ collision: String) async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try SystemLibrary.shared.get()
        let sourcesName = "Smalltalk80-\(library.identifier.prefix(12)).sources"
        let filename: String
        switch collision {
        case "changes": filename = "World.changes"
        case "sources": filename = sourcesName
        default:
            let sensitive = try folder.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames
            guard sensitive == false else { return }
            filename = "World.CHANGES"
        }
        let session = SmalltalkSession()
        #expect(await session.compile("answer ^ 42", in: "Counter").error == nil)
        // A portable world can contain methods missing from its changes log.
        // Collision validation must precede the save's source reconstruction.
        await session.worker.submit { $0.journal = SourceJournal() }
        await #expect(throws: (any Error).self) {
            try await session.saveImage(to: folder.appendingPathComponent(filename), workspace: "", transcript: "")
        }
        #expect(await session.snapshot().changes.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test(arguments: ["symlink", "hardlink"])
    func imageAliasesCannotOverwriteTheSourcesArchive(_ link: String) async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try SystemLibrary.shared.get()
        let sources = folder.appendingPathComponent("Smalltalk80-\(library.identifier.prefix(12)).sources")
        let image = folder.appendingPathComponent("Alias.snapshot")
        try library.data.write(to: sources)
        if link == "symlink" { try FileManager.default.createSymbolicLink(at: image, withDestinationURL: sources) }
        else { try FileManager.default.linkItem(at: sources, to: image) }
        let session = SmalltalkSession()
        await #expect(throws: (any Error).self) {
            try await session.saveImage(to: image, workspace: "", transcript: "")
        }
        #expect(try Data(contentsOf: sources) == library.data)
        #expect(try Data(contentsOf: image) == library.data)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("Alias.changes").path))
    }

    @Test(arguments: ["symlink", "hardlink"])
    func imageAliasesCannotOverwriteTheActiveJournal(_ link: String) async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let changes = folder.appendingPathComponent("Active.changes")
        let image = folder.appendingPathComponent("Alias.snapshot")
        let session = SmalltalkSession()
        try await session.startChangeLog(at: changes)
        #expect(await session.compile("answer ^ 42", in: "Counter").error == nil)
        let original = try Data(contentsOf: changes)
        if link == "symlink" { try FileManager.default.createSymbolicLink(at: image, withDestinationURL: changes) }
        else { try FileManager.default.linkItem(at: changes, to: image) }
        await #expect(throws: (any Error).self) {
            try await session.saveImage(to: image, workspace: "", transcript: "")
        }
        #expect(try Data(contentsOf: changes) == original)
        #expect(try Data(contentsOf: image) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
        #expect(await session.compile("answer ^ 43", in: "Counter").error == nil)
    }

    @Test func symlinkedCompanionsCannotAliasEachOther() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try SystemLibrary.shared.get()
        let changes = folder.appendingPathComponent("World.changes")
        let sources = folder.appendingPathComponent("Smalltalk80-\(library.identifier.prefix(12)).sources")
        let original = Data("unrelated contents".utf8)
        try original.write(to: changes)
        try FileManager.default.createSymbolicLink(at: sources, withDestinationURL: changes)
        let session = SmalltalkSession()
        await #expect(throws: (any Error).self) {
            try await session.saveImage(to: folder.appendingPathComponent("World.snapshot"), workspace: "", transcript: "")
        }
        #expect(try Data(contentsOf: changes) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
    }

    @Test func aDanglingImageSymlinkCannotBecomeItsOwnChangesFile() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("World.snapshot")
        let changes = folder.appendingPathComponent("World.changes")
        try FileManager.default.createSymbolicLink(at: image, withDestinationURL: changes)
        let session = SmalltalkSession()
        await #expect(throws: (any Error).self) {
            try await session.saveImage(to: image, workspace: "", transcript: "")
        }
        #expect(!FileManager.default.fileExists(atPath: changes.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["World.snapshot"])
    }

    @Test func symlinksFollowedByParentComponentsCannotHideAnActiveJournalCollision() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let real = folder.appendingPathComponent("elsewhere", isDirectory: true)
        let child = real.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("alias"), withDestinationURL: child)
        let changes = real.appendingPathComponent("Active.snapshot")
        let image = URL(fileURLWithPath: folder.path + "/alias/../Active.snapshot")
        let session = SmalltalkSession()
        try await session.startChangeLog(at: changes)
        let original = try Data(contentsOf: changes)
        await #expect(throws: (any Error).self) {
            try await session.saveImage(to: image, workspace: "", transcript: "")
        }
        #expect(try Data(contentsOf: changes) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: real.path).sorted() == ["Active.snapshot", "child"])
    }

    @Test func distinctExtensionsAndSymlinkedDirectoriesCanSaveNormally() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let real = folder.appendingPathComponent("real", isDirectory: true)
        let alias = folder.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        let session = SmalltalkSession()
        #expect(await session.compile("answer ^ 42", in: "Counter").error == nil)
        try await session.saveImage(to: real.appendingPathComponent("World.snapshot"), workspace: "first", transcript: "")
        let changes = real.appendingPathComponent("World.changes")
        let id = try SourceJournal.read(changes).id
        #expect(await session.compile("answer ^ 43", in: "Counter").error == nil)
        try await session.saveImage(to: alias.appendingPathComponent("World.snapshot"), workspace: "second", transcript: "")
        #expect(try SourceJournal.read(changes).id == id)
        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(from: real.appendingPathComponent("World.snapshot"))
        #expect(loaded.workspace == "second")
        #expect(await restored.evaluate("Counter new answer").value == "43")
    }
}
