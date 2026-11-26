import Foundation
import Testing
@testable import SmalltalkCore

func openTools(_ kinds: ToolKind..., in session: SmalltalkSession) async throws -> EvaluationResult {
    var snapshot = await session.snapshot()
    for kind in kinds {
        snapshot = await session.windowAction(.open(kind))
        try #require(snapshot.error == nil)
    }
    return snapshot
}

@MainActor
struct DesktopTests {
    private func value(_ source: String, in session: SmalltalkSession) async -> String? {
        let evaluation = await session.evaluate(source)
        #expect(evaluation.error == nil, "\(evaluation.error ?? "")")
        return evaluation.value
    }

    @Test func desktopDecidesWhichToolsRefreshAtTheEvaluationBoundary() async throws {
        let session = SmalltalkSession()
        let configured = await session.evaluate("""
        catalogNotifications := 0.
        UIWindow subclass: #CatalogProbe instanceVariableNames: ''.
        CatalogProbe compile: 'refreshTools self text: self text , ''r'''.
        selectedTool := CatalogProbe new title: 'Selected Tool'; yourself.
        otherTool := CatalogProbe new title: 'Other Tool'; yourself.
        selectedTool open.
        otherTool open.
        DesktopManager compile: 'catalogChanged
            catalogNotifications := catalogNotifications + 1.
            selectedTool refreshTools'.
        """)
        try #require(configured.error == nil)
        #expect(configured.bindings.first { $0.name == "catalogNotifications" }?.value == "1")
        #expect(configured.windows.first { $0.title == "Selected Tool" }?.text == "r")
        #expect(configured.windows.first { $0.title == "Other Tool" }?.text == "")

        let changed = await session.evaluate("Counter compile: 'catalogFirst ^ 1'; compile: 'catalogSecond ^ 2'")
        try #require(changed.error == nil)
        #expect(changed.bindings.first { $0.name == "catalogNotifications" }?.value == "2")
        #expect(changed.windows.first { $0.title == "Selected Tool" }?.text == "rr")
        #expect(changed.windows.first { $0.title == "Other Tool" }?.text == "")

        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(session.imageData())
        #expect(loaded.evaluation.bindings.first { $0.name == "catalogNotifications" }?.value == "2")
        let snapshot = await restored.snapshot()
        #expect(snapshot.bindings.first { $0.name == "catalogNotifications" }?.value == "2")
        #expect(snapshot.windows.first { $0.title == "Selected Tool" }?.text == "rr")
        let next = await restored.compile("catalogThird ^ 3", in: "Counter")
        #expect(next.bindings.first { $0.name == "catalogNotifications" }?.value == "3")
        #expect(next.windows.first { $0.title == "Selected Tool" }?.text == "rrr")
        #expect(next.windows.first { $0.title == "Other Tool" }?.text == "")
    }

    @Test func imagesWithoutTheCatalogHookUseTheBundledSmalltalkPolicy() async throws {
        let original = SmalltalkSession()
        _ = try await openTools(.browser, in: original)
        await original.worker.submit { runtime in
            runtime.classes["DesktopManager"]?.methods["catalogChanged"] = nil
        }
        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(original.imageData())
        #expect(loaded.evaluation.error == nil)
        let browser = try #require(loaded.evaluation.windows.first { $0.kind == .browser })

        let changed = await restored.compile("addedAfterLoading ^ 42", in: "Counter")
        #expect(changed.error == nil)
        let updated = try #require(changed.windows.first { $0.id == browser.id })
        let methods = try #require(updated.content?.firstVisible { $0.accessibilityID == "methodList" })
        #expect(methods.items.contains("addedAfterLoading"))
        let desktopClass = try #require(changed.classes.first { $0.name == "DesktopManager" })
        #expect(!desktopClass.methods.contains { $0.selector == "catalogChanged" })
    }

    @Test func freshDesktopIsEmptyAndItsOpenCommandsDispatchThroughSmalltalk() async throws {
        let session = SmalltalkSession()
        let snapshot = await session.snapshot()
        #expect(snapshot.error == nil)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.activeWindowID == nil)
        let loaded = try await SmalltalkSession().loadImage(session.imageData())
        #expect(loaded.evaluation.windows.isEmpty)
        #expect(loaded.evaluation.activeWindowID == nil)
        #expect(await value("Desktop class name", in: session) == "#DesktopManager")
        #expect(await value("Desktop windows size", in: session) == "0")

        // Native menu commands must dispatch the live Smalltalk method as well.
        #expect(await value("DesktopManager compile: 'openWorkspace ^ self openBrowser'", in: session) == "#openWorkspace")
        let redirected = await session.windowAction(.open(.workspace))
        #expect(redirected.error == nil)
        #expect(redirected.windows.count == 1)
        let browser = try #require(redirected.windows.first { $0.kind == .browser })
        #expect(redirected.activeWindowID == browser.id)
    }

    @Test func workspacesKeepIndependentBuffersAndShareTheObjectSpace() async throws {
        let session = SmalltalkSession()
        let initial = try await openTools(.workspace, in: session)
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

    @Test(arguments: [ToolKind.workspace, .browser])
    func independentToolsCanBeOpenedActivatedAndClosedSeparately(_ kind: ToolKind) async throws {
        let session = SmalltalkSession()
        let initial = try await openTools(kind, .transcript, in: session)
        let first = try #require(initial.windows.first { $0.kind == kind })
        let transcript = try #require(initial.windows.first { $0.kind == .transcript })
        let opened = try await openTools(kind, in: session)
        let second = try #require(opened.windows.first { $0.id == opened.activeWindowID })
        #expect(opened.windows.filter { $0.kind == kind }.count == 2)
        #expect(second.id != first.id)
        #expect(second.frame != first.frame)

        let minimized = await session.windowAction(.minimize(first.id, true))
        #expect(minimized.error == nil)
        #expect(minimized.windows.first { $0.id == first.id }?.minimized == true)
        let activated = await session.windowAction(.activate(first.id))
        #expect(activated.error == nil)
        #expect(activated.activeWindowID == first.id)
        #expect(activated.windows.last?.id == first.id)
        #expect(activated.windows.last?.minimized == false)
        let closed = await session.windowAction(.close(first.id))
        #expect(closed.error == nil)
        #expect(closed.windows.map(\.id) == [transcript.id, second.id])
        #expect(closed.activeWindowID == second.id)
    }

    @Test func workspaceStartsWithTheTranscriptExampleAndTranscriptReusesItsWindow() async throws {
        let session = SmalltalkSession()
        let started = try await openTools(.workspace, .transcript, in: session)
        let workspace = try #require(started.windows.first { $0.kind == .workspace })
        let transcript = try #require(started.windows.first { $0.kind == .transcript })
        #expect(workspace.text == "Transcript show: 'Hello'; cr.")
        #expect(workspace.content?.firstVisible { $0.accessibilityID == "workspaceEditor" }?.text == workspace.text)
        #expect(transcript.content?.firstVisible { $0.accessibilityID == "transcriptOutput" }?.text == "")
        let minimized = await session.windowAction(.minimize(transcript.id, true))
        #expect(minimized.activeWindowID == workspace.id)
        let reused = try await openTools(.transcript, in: session)
        #expect(reused.activeWindowID == transcript.id)
        #expect(reused.windows.filter { $0.kind == .transcript }.map(\.id) == [transcript.id])
        let execute = try #require(workspace.content?.firstVisible { $0.command == "doIt" })
        let executed = await session.uiAction(.click(windowID: workspace.id, elementID: execute.id))
        #expect(executed.error == nil)
        _ = await session.windowAction(.close(transcript.id))
        let reopened = try await openTools(.transcript, in: session)
        let output = reopened.windows.first { $0.kind == .transcript }?.content?.firstVisible { $0.accessibilityID == "transcriptOutput" }
        #expect(output?.text == "Hello\n")
        #expect(reopened.changes.isEmpty)
    }

    @Test func newTranscriptUsesTheBottomRightOfTheActiveDisplay() async throws {
        let session = SmalltalkSession()
        let initial = await session.snapshot()
        let screens = [
            ScreenInfo(id: "primary", frame: WindowRect(x: 0, y: 60, width: 1_440, height: 840)),
            ScreenInfo(id: "secondary", frame: WindowRect(x: 1_440, y: -120, width: 1_280, height: 800)),
        ]
        let configured = await session.windowEvents([
            NativeWindowEvent(epoch: initial.windowCommands.epoch, sequence: 1, kind: .screens(screens)),
        ])
        try #require(configured.error == nil)

        let opened = try await openTools(.transcript, in: session)
        let transcript = try #require(opened.windows.first)
        #expect(transcript.frame == WindowRect(x: 696, y: 84, width: 720, height: 260))

        let moved = WindowRect(x: 100, y: 100, width: 640, height: 300)
        _ = await session.windowAction(.frame(transcript.id, x: moved.x, y: moved.y, width: moved.width, height: moved.height))
        let reused = try await openTools(.transcript, in: session)
        #expect(reused.windows.first?.frame == moved)

        _ = await session.windowAction(.close(transcript.id))
        let workspace = try await openTools(.workspace, in: session)
        let workspaceID = try #require(workspace.activeWindowID)
        _ = await session.windowAction(.frame(workspaceID, x: 1_500, y: 0, width: 720, height: 600))
        let reopened = try await openTools(.transcript, in: session)
        #expect(reopened.windows.first { $0.kind == .transcript }?.frame == WindowRect(x: 1_976, y: -96, width: 720, height: 260))
    }

    @Test func legacyOpenersUpgradeOnFirstUseWithoutReplacingAuthoredMethods() async throws {
        let original = SmalltalkSession()
        _ = try await openTools(.browser, .transcript, in: original)
        let configured = await original.evaluate("""
        DesktopManager compile: 'openBrowser
            | existing | existing := self windowOfKind: #browser.
            existing notNil ifTrue: [ ^ self activate: existing ].
            ^ self createKind: #browser title: ''System Browser'''.
        DesktopManager compile: 'openTranscript ^ self activate: (self windowOfKind: #transcript)'.
        """)
        try #require(configured.error == nil)
        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(original.imageData())
        #expect(loaded.evaluation.windows.map(\.id) == configured.windows.map(\.id))
        #expect(loaded.evaluation.changes.isEmpty)
        let opened = try await openTools(.browser, .transcript, .browser, in: restored)
        #expect(opened.windows.filter { $0.kind == .browser }.count == 3)
        #expect(opened.windows.filter { $0.kind == .transcript }.count == 1)
        #expect(opened.changes.map(\.selector) == ["openBrowser"])
    }

    @Test func previousToolDefaultsUpdateOnUseAfterLoadingAnImage() async throws {
        let original = SmalltalkSession()
        let configured = await original.evaluate("""
        DesktopManager compile: 'openWorkspace
            ^ self createKind: #workspace title: ''Workspace'''.
        DesktopManager compile: 'openTranscript
            ^ self createKind: #transcript title: ''Transcript'''.
        TranscriptModel compile: 'text
            contents size = 0 ifTrue: [ ^ ''Transcript show: ''''Hello''''; cr.'' ].
            ^ contents'.
        Desktop openWorkspace.
        Desktop openTranscript.
        Desktop openTranscript
        """)
        try #require(configured.error == nil)
        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(original.imageData())
        #expect(loaded.evaluation.changes.isEmpty)
        let existingTranscripts = loaded.evaluation.windows.filter { $0.kind == .transcript }
        try #require(existingTranscripts.count == 2)
        let reused = try await openTools(.transcript, .transcript, in: restored)
        let transcripts = reused.windows.filter { $0.kind == .transcript }
        #expect(transcripts.map(\.id) == existingTranscripts.map(\.id))
        #expect(reused.activeWindowID == existingTranscripts.last?.id)
        for window in transcripts {
            #expect(window.content?.firstVisible { $0.accessibilityID == "transcriptOutput" }?.text == "")
        }
        let opened = try await openTools(.workspace, in: restored)
        #expect(opened.windows.first { $0.kind == .workspace }?.text == "")
        #expect(opened.windows.last?.text == "Transcript show: 'Hello'; cr.")
        #expect(opened.changes.map(\.selector) == ["openTranscript", "text", "openWorkspace"])
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
        let image = try await session.imageData()
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
        _ = try await openTools(.workspace, .browser, .transcript, in: donor)
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
                #expect(error.localizedDescription.contains("window"))
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
        let next = await restored.windowAction(.open(.workspace))
        #expect(next.windows.filter { $0.kind == .transcript }.count == 1)
        #expect(next.activeWindowID == transcript.id)
    }
}
