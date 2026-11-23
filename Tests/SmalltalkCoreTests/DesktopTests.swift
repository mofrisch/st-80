import Foundation
import Testing
@testable import SmalltalkCore

@MainActor
struct DesktopTests {
    private func value(_ source: String, in session: SmalltalkSession) async -> String? {
        let evaluation = await session.evaluate(source)
        #expect(evaluation.error == nil, "\(evaluation.error ?? "")")
        return evaluation.value
    }

    @Test func desktopIsAnEditableSmalltalkObjectWithThreeInitialTools() async throws {
        let session = SmalltalkSession()
        let snapshot = await session.snapshot()
        #expect(snapshot.windows.count == 3)
        #expect(Set(snapshot.windows.map(\.id)).count == 3)
        #expect(snapshot.windows.allSatisfy { $0.id > 0 })
        #expect(snapshot.windows.filter { $0.kind == .workspace }.count == 1)
        #expect(snapshot.windows.filter { $0.kind == .browser }.count == 1)
        #expect(snapshot.windows.filter { $0.kind == .transcript }.count == 1)
        let workspace = try #require(snapshot.windows.first { $0.kind == .workspace })
        #expect(snapshot.activeWindowID == workspace.id)
        #expect(workspace.text == SmalltalkExamples.workspace)
        #expect(await value("Desktop class name", in: session) == "#DesktopManager")
        #expect(await value("Desktop windows size", in: session) == "3")

        // Native menu commands must dispatch the live Smalltalk method as well.
        #expect(await value("DesktopManager compile: 'openWorkspace ^ self openBrowser'", in: session) == "#openWorkspace")
        let redirected = await session.windowAction(.open(.workspace))
        #expect(redirected.error == nil)
        #expect(redirected.windows.count == 3)
        let browser = try #require(redirected.windows.first { $0.kind == .browser })
        #expect(redirected.activeWindowID == browser.id)
    }

    @Test func workspacesKeepIndependentBuffersAndShareTheObjectSpace() async throws {
        let session = SmalltalkSession()
        let initial = await session.snapshot()
        let first = try #require(initial.windows.first { $0.kind == .workspace })
        _ = await session.windowAction(.text(first.id, "shared := 40. shared"))
        let opened = await session.windowAction(.open(.workspace))
        let second = try #require(opened.windows.first { $0.kind == .workspace && $0.id != first.id })
        #expect(opened.activeWindowID == second.id)
        let edited = await session.windowAction(.text(second.id, "shared + 2"))
        #expect(edited.windows.first { $0.id == first.id }?.text == "shared := 40. shared")
        #expect(edited.windows.first { $0.id == second.id }?.text == "shared + 2")
        #expect(await value("shared := 40. shared", in: session) == "40")
        #expect(await value("shared + 2", in: session) == "42")
        #expect(await value("(Desktop windowAt: \(first.id)) text", in: session) == "'shared := 40. shared'")
        #expect(await value("(Desktop windowAt: \(second.id)) text", in: session) == "'shared + 2'")
    }

    @Test func activationRestoresMinimizedWindowsAndClosingPreservesOtherTools() async throws {
        let session = SmalltalkSession()
        let initial = await session.snapshot()
        let workspace = try #require(initial.windows.first { $0.kind == .workspace })
        let extra = await session.windowAction(.open(.workspace))
        let second = try #require(extra.windows.first { $0.kind == .workspace && $0.id != workspace.id })
        let minimized = await session.windowAction(.minimize(workspace.id, true))
        #expect(minimized.windows.first { $0.id == workspace.id }?.minimized == true)
        let activated = await session.windowAction(.activate(workspace.id))
        #expect(activated.activeWindowID == workspace.id)
        #expect(activated.windows.first { $0.id == workspace.id }?.minimized == false)
        #expect(activated.windows.last?.id == workspace.id)
        let closed = await session.windowAction(.close(workspace.id))
        #expect(closed.error == nil)
        #expect(!closed.windows.contains { $0.id == workspace.id })
        #expect(closed.windows.contains { $0.id == second.id })
        #expect(closed.windows.contains { $0.kind == .browser })
        #expect(closed.windows.contains { $0.kind == .transcript })
        #expect(closed.activeWindowID != workspace.id)
    }

    @Test func browserAndTranscriptCommandsReuseTheirExistingWindows() async throws {
        let session = SmalltalkSession()
        let initial = await session.snapshot()
        let browser = try #require(initial.windows.first { $0.kind == .browser })
        let transcript = try #require(initial.windows.first { $0.kind == .transcript })
        for _ in 0..<3 {
            let shown = await session.windowAction(.open(.browser))
            #expect(shown.error == nil)
            #expect(shown.activeWindowID == browser.id)
            #expect(shown.windows.filter { $0.kind == .browser }.count == 1)
            let output = await session.windowAction(.open(.transcript))
            #expect(output.activeWindowID == transcript.id)
            #expect(output.windows.filter { $0.kind == .transcript }.count == 1)
            #expect(output.windows.count == 3)
        }
    }

    @Test func nativeGeometryAndSmalltalkWindowMessagesSurviveImageRestart() async throws {
        let session = SmalltalkSession()
        let opened = await session.windowAction(.open(.workspace))
        let workspace = try #require(opened.windows.first { $0.id == opened.activeWindowID })
        _ = await session.windowAction(.text(workspace.id, "'Ein zweiter Workspace 👋'"))
        _ = await session.windowAction(.frame(workspace.id, x: 111, y: 222, width: 680, height: 420))
        _ = await session.windowAction(.minimize(workspace.id, true))
        #expect(await value("(Desktop windowAt: \(workspace.id)) title: 'Saved Workspace'", in: session) != nil)
        let before = await session.snapshot()
        let image = try await session.imageData(workspace: "legacy metadata", transcript: "history\n")
        let restarted = SmalltalkSession()
        let loaded = try await restarted.loadImage(image)
        #expect(loaded.evaluation.windows.count == before.windows.count)
        let restored = try #require(loaded.evaluation.windows.first { $0.id == workspace.id })
        #expect(restored.kind == .workspace)
        #expect(restored.title == "Saved Workspace")
        #expect(restored.text == "'Ein zweiter Workspace 👋'")
        #expect(restored.x == 111)
        #expect(restored.y == 222)
        #expect(restored.width == 680)
        #expect(restored.height == 420)
        #expect(restored.minimized)
        let next = await restarted.windowAction(.open(.workspace))
        let nextID = try #require(next.activeWindowID)
        let previousMaximum = try #require(before.windows.map(\.id).max())
        #expect(nextID > previousMaximum)
        #expect(await value("(Desktop windowAt: \(workspace.id)) class name", in: restarted) == "#WorkspaceWindow")
    }

    @Test func invalidSavedWindowsDoNotReplaceTheCurrentSession() async throws {
        let donor = SmalltalkSession()
        let bytes = try await donor.imageData()
        let original = try JSONDecoder().decode(ImageArchive.self, from: bytes)
        let windowIndices = original.nodes.indices.filter { index in
            if case .object(let object) = original.nodes[index] { return ["WorkspaceWindow", "BrowserWindow", "TranscriptWindow"].contains(object.className) }
            return false
        }
        #expect(windowIndices.count == 3)
        let first = try #require(windowIndices.first)
        let second = try #require(windowIndices.dropFirst().first)
        guard case .object(var firstWindow) = original.nodes[first],
              case .object(var secondWindow) = original.nodes[second] else {
            Issue.record("Expected serialized SystemWindow objects.")
            return
        }
        var invalidKind = original
        firstWindow.fields["kind"] = .symbol("unknownTool")
        invalidKind.nodes[first] = .object(firstWindow)

        var duplicateID = original
        guard case .object(let originalFirst) = original.nodes[first] else { return }
        secondWindow.fields["id"] = originalFirst.fields["id"]
        duplicateID.nodes[second] = .object(secondWindow)

        let current = SmalltalkSession()
        #expect(await value("kept := 42", in: current) == "42")
        let before = await current.windowAction(.open(.workspace))
        let originalIDs = Set(before.windows.map(\.id))
        for corrupt in [invalidKind, duplicateID] {
            let data = try JSONEncoder().encode(corrupt)
            do {
                _ = try await current.loadImage(data)
                Issue.record("An invalid saved window unexpectedly replaced the session.")
            } catch {
                #expect(error.localizedDescription.contains("Fenster"))
            }
            let after = await current.evaluate("kept")
            #expect(after.error == nil)
            #expect(after.value == "42")
            #expect(Set(after.windows.map(\.id)) == originalIDs)
            #expect(after.activeWindowID == before.activeWindowID)
        }
    }

    @Test func desktopManagerSubclassesRetainTheirClassAndDispatchAfterImageLoad() async throws {
        let original = SmalltalkSession()
        #expect(await value("""
        DesktopManager subclass: #CustomDesktop instanceVariableNames: 'marker'.
        CustomDesktop compile: 'initialize super initialize. marker := 73'.
        CustomDesktop compile: 'marker ^ marker'.
        CustomDesktop compile: 'openWorkspace ^ self openTranscript'.
        Desktop := CustomDesktop new.
        Desktop openBrowser.
        Desktop marker
        """, in: original) == "73")
        let bytes = try await original.imageData()
        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(bytes)
        #expect(loaded.evaluation.error == nil)
        #expect(loaded.evaluation.windows.count == 1)
        #expect(await value("Desktop class name", in: restored) == "#CustomDesktop")
        #expect(await value("Desktop marker", in: restored) == "73")

        // The native command still sends the override on the actual manager.
        let redirected = await restored.windowAction(.open(.workspace))
        #expect(redirected.error == nil)
        #expect(redirected.windows.count == 2)
        #expect(redirected.windows.filter { $0.kind == .workspace }.isEmpty)
        let transcript = try #require(redirected.windows.first { $0.kind == .transcript })
        #expect(redirected.activeWindowID == transcript.id)
        let reused = await restored.windowAction(.open(.workspace))
        #expect(reused.windows.count == 2)
        #expect(reused.activeWindowID == transcript.id)
    }
}
