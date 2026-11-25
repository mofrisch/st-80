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
            ChangesBrowser compile: 'synchronize loadEffects := loadEffects + 1'
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

    @Test func olderImagesWithoutCachedHistoryLoadWithoutInitializingTheBrowser() async throws {
        let original = SmalltalkSession()
        #expect(await original.evaluate("""
            loadEffects := 0.
            Desktop openChanges.
            ChangesBrowser compile: 'initialize loadEffects := loadEffects + 100. self buildContent'.
            ChangesBrowser compile: 'synchronize loadEffects := loadEffects + 1'
            """).error == nil)
        var archive = try JSONDecoder().decode(ImageArchive.self, from: await original.imageData())
        archive.changesBrowser = nil
        archive.globals["loadEffects"] = .integer(0)
        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(JSONEncoder().encode(archive))
        #expect(loaded.evaluation.error == nil)
        #expect(loaded.evaluation.windows.contains { $0.kind == .changes })
        _ = await restored.snapshot()
        #expect(await effects(in: restored) == "0")
        let opened = await restored.windowAction(.showChanges(className: nil, selector: nil, side: .instance))
        #expect(opened.error == nil)
        #expect(element("changesList", in: opened.windows.first { $0.kind == .changes }?.content) != nil)
        #expect(await effects(in: restored) == "101")
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
