import Foundation
import Testing
@testable import SmalltalkCore

struct ChangesBrowserPersistenceTests {
    private func element(_ id: String, in root: UIElementInfo?) -> UIElementInfo? {
        guard let root else { return nil }
        if root.accessibilityID == id { return root }
        return root.children.lazy.compactMap { element(id, in: $0) }.first
    }

    private func effects(in session: SmalltalkSession) async -> String? {
        await session.worker.submit { runtime in
            runtime.globals["loadEffects"].map { runtime.printValue($0) }
        }
    }

    @Test func closedChangesWindowRetainsItsOwnHistoryAcrossCollectionAndImageLoad() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("st80-changes-reopen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appendingPathComponent("History.stimage")
        let session = SmalltalkSession()
        #expect(await session.compile("value ^ 41", in: "Counter").error == nil)
        #expect(await session.compile("otherVersion ^ 12", in: "Counter").error == nil)
        let opened = await session.windowAction(.showChanges(className: "Counter", selector: "value", side: .instance))
        let window = try #require(opened.windows.first { $0.kind == .changes })
        #expect(await session.evaluate("(Desktop windowOfKind: #changes) class name").value == "#ChangesBrowser")
        let list = try #require(element("changesList", in: window.content))
        let record = try #require(list.historyEntries.first)
        #expect(record.title == "Counter » value")
        let selected = await session.uiAction(.select(windowID: window.id, elementID: list.id, value: record.id))
        #expect(selected.error == nil)
        let closed = await session.windowAction(.close(window.id))
        #expect(!closed.windows.contains { $0.kind == .changes })
        _ = await session.collectGarbage()
        try await session.saveImage(to: image, workspace: "", transcript: "")

        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(from: image)
        #expect(loaded.evaluation.error == nil)
        #expect(!loaded.evaluation.windows.contains { $0.kind == .changes })
        let reopened = await restored.windowAction(.open(.changes))
        #expect(reopened.error == nil)
        let reopenedWindow = try #require(reopened.windows.first { $0.kind == .changes })
        let history = try #require(element("changesList", in: reopenedWindow.content))
        #expect(history.selection == record.id)
        #expect(history.historyEntries.map(\.title) == ["Counter » value", "Counter » value"])
        #expect(element("changeSource", in: reopenedWindow.content)?.children.first?.text == "value ^ 41")
    }

    @Test(arguments: [false, true])
    func loadingAndSnapshotsNeverRunChangesBrowserMethods(fileImage: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("st80-changes-load-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = SmalltalkSession()
        let configured = await original.evaluate("""
            loadEffects := 0.
            Desktop openChanges.
            ChangesBrowser compile: 'initialize loadEffects := loadEffects + 100. self buildContent'.
            ChangesBrowser compile: 'synchronizeHistory loadEffects := loadEffects + 1'
            """)
        #expect(configured.error == nil)
        await original.worker.submit { $0.globals["loadEffects"] = .integer(0) }
        #expect(await original.snapshot().error == nil)
        #expect(await effects(in: original) == "0")

        let restored = SmalltalkSession()
        let loaded: LoadedImage
        if fileImage {
            let image = folder.appendingPathComponent("Changes.stimage")
            try await original.saveImage(to: image, workspace: "", transcript: "")
            loaded = try await restored.loadImage(from: image)
        } else {
            loaded = try await restored.loadImage(original.imageData())
        }
        #expect(loaded.evaluation.error == nil)
        #expect(element("changesList", in: loaded.evaluation.windows.first { $0.kind == .changes }?.content) != nil)
        #expect(await effects(in: original) == "0")
        #expect(await effects(in: restored) == "0")
        #expect(await restored.snapshot().error == nil)
        #expect(await restored.snapshot().error == nil)
        #expect(await effects(in: restored) == "0")

        // Synchronization is allowed at the next explicit execution boundary,
        // and uses the restored browser rather than sending initialize again.
        #expect(await restored.evaluate("nil").error == nil)
        #expect(await effects(in: restored) == "1")
    }

    @Test func restoredHistoryControlsStillSelectSourcesAndRefreshAfterAnEdit() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("st80-changes-controls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("History.stimage")
        let original = SmalltalkSession()
        #expect(await original.compile("value ^ 41", in: "Counter").error == nil)
        let opened = await original.windowAction(.showChanges(className: "Counter", selector: "value", side: .instance))
        let window = try #require(opened.windows.first { $0.kind == .changes })
        let list = try #require(element("changesList", in: window.content))
        let record = try #require(list.historyEntries.first)
        _ = await original.uiAction(.select(windowID: window.id, elementID: list.id, value: record.id))
        try await original.saveImage(to: image, workspace: "", transcript: "")

        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(from: image)
        let content = try #require(loaded.evaluation.windows.first { $0.id == window.id }?.content)
        #expect(element("changesList", in: content)?.selection == record.id)
        #expect(element("changeSource", in: content)?.children.first?.text == "value ^ 41")
        let all = try #require(element("allChangesButton", in: content))
        let clicked = await restored.uiAction(.click(windowID: window.id, elementID: all.id))
        #expect(clicked.error == nil)
        let refreshed = await restored.compile("value ^ 42", in: "Counter")
        #expect(refreshed.error == nil)
        let refreshedList = try #require(element("changesList", in: refreshed.windows.first { $0.id == window.id }?.content))
        #expect(refreshedList.historyEntries.first?.id == refreshed.changes.last?.id)
        #expect(refreshedList.historyEntries.contains { $0.id == record.id })
    }
}
