import Foundation
import Testing
@testable import SmalltalkCore

struct WindowArchitectureTests {
    private func event(_ snapshot: EvaluationResult, _ sequence: Int64, _ kind: NativeWindowEvent.Kind) -> NativeWindowEvent {
        NativeWindowEvent(epoch: snapshot.windowCommands.epoch, sequence: sequence, kind: kind)
    }
    private func screen(_ id: String, _ x: Int64, _ y: Int64, _ width: Int64, _ height: Int64) -> ScreenInfo {
        ScreenInfo(id: id, frame: WindowRect(x: x, y: y, width: width, height: height))
    }

    @Test func toolsArrangeIntoColumnsWithinTheAvailableDisplay() async throws {
        let session = SmalltalkSession()
        let initial = await session.snapshot()
        let display = screen("offset", -1440, 120, 1440, 900)
        let connected = await session.windowEvents([event(initial, 1, .screens([display]))])
        #expect(connected.error == nil)
        let oldBrowser = try #require(connected.windows.first { $0.kind == .browser })
        _ = await session.windowAction(.minimize(oldBrowser.id, true))
        let arranged = await session.windowAction(.arrangeTools)
        #expect(arranged.error == nil)
        #expect(arranged.activeWindowID == connected.activeWindowID)
        #expect(arranged.windows.count == connected.windows.count)
        #expect(arranged.windows.allSatisfy { !$0.minimized })
        for window in arranged.windows {
            #expect(window.text == connected.windows.first { $0.id == window.id }?.text)
            #expect(window.x >= display.frame.x)
            #expect(window.y >= display.frame.y)
            #expect(window.x + window.width <= display.frame.x + display.frame.width)
            #expect(window.y + window.height <= display.frame.y + display.frame.height)
        }
        let browser = try #require(arranged.windows.first { $0.kind == .browser })
        let workspace = try #require(arranged.windows.first { $0.kind == .workspace })
        let transcript = try #require(arranged.windows.first { $0.kind == .transcript })
        #expect(browser.width >= 750)
        #expect(workspace.width >= 480)
        #expect(browser.x + browser.width < workspace.x)
        #expect(workspace.x == transcript.x)
        #expect(workspace.width == transcript.width)
        #expect(transcript.y + transcript.height < workspace.y)
        #expect(browser.y == transcript.y)
        #expect(browser.y + browser.height == workspace.y + workspace.height)
    }

    @Test func arrangingAnOlderImageInstallsOnlyTheMissingMethodOnce() async throws {
        let original = SmalltalkSession()
        let customFrame = WindowRect(x: 220, y: 180, width: 640, height: 420)
        _ = await original.windowAction(.frame(1, x: customFrame.x, y: customFrame.y, width: customFrame.width, height: customFrame.height))
        var archive = try JSONDecoder().decode(ImageArchive.self, from: await original.imageData())
        let manager = try #require(archive.classes.firstIndex { $0.name == "DesktopManager" })
        let removedSource = archive.classes[manager].methods.removeValue(forKey: "arrangeTools")
        let missingSource = try #require(removedSource)
        let missingCode = archive.executableMethods?["DesktopManager"]?.removeValue(forKey: "arrangeTools")
        #expect(missingCode != nil)

        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(JSONEncoder().encode(archive))
        #expect(loaded.evaluation.windows.first { $0.id == 1 }?.frame == customFrame)
        #expect(loaded.evaluation.changes.isEmpty)
        let arranged = await restored.windowAction(.arrangeTools)
        #expect(arranged.error == nil)
        #expect(arranged.windows.first { $0.id == 1 }?.frame != customFrame)
        #expect(arranged.changes.count == 1)
        let installation = try #require(arranged.changes.first)
        #expect(installation.kind == .method)
        #expect(installation.className == "DesktopManager")
        #expect(installation.selector == "arrangeTools")
        #expect(installation.source == missingSource)

        let repeated = await restored.windowAction(.arrangeTools)
        #expect(repeated.error == nil)
        #expect(repeated.changes.map(\.id) == arranged.changes.map(\.id))
    }

    @Test func arrangeToolsHonorsAnExistingCustomMethod() async throws {
        let session = SmalltalkSession()
        let custom = await session.evaluate("DesktopManager compile: 'arrangeTools self activeWindow title: ''My arrangement'''")
        #expect(custom.error == nil)
        let arranged = await session.windowAction(.arrangeTools)
        #expect(arranged.error == nil)
        #expect(arranged.windows.first { $0.id == arranged.activeWindowID }?.title == "My arrangement")
        #expect(arranged.changes.map(\.id) == custom.changes.map(\.id))
        #expect(arranged.windows.map(\.frame) == custom.windows.map(\.frame))
    }

    @Test func smalltalkOwnsScreenSelectionLimitsAndRemovedDisplayRecovery() async throws {
        let session = SmalltalkSession()
        let initial = await session.snapshot()
        let screens = [screen("left", -1600, 0, 1600, 1000), screen("main", 0, 0, 1440, 900)]
        let connected = await session.windowEvents([event(initial, 1, .screens(screens))])
        #expect(connected.error == nil)
        let moved = await session.evaluate("""
        window := Desktop windowAt: 1.
        window moveToX: -1400 y: 200; resizeWidth: 900 height: 600
        """)
        #expect(moved.error == nil)
        #expect(moved.windows.first { $0.id == 1 }?.x == -1400)
        let shrunk = await session.evaluate("window minimumWidth: 610 height: 410; resizeWidth: 50 height: 20")
        #expect(shrunk.windows.first { $0.id == 1 }?.width == 610)
        #expect(shrunk.windows.first { $0.id == 1 }?.height == 410)
        let disconnected = await session.windowEvents([event(initial, 2, .screens([screens[1]]))])
        #expect(disconnected.error == nil)
        #expect(disconnected.windows.first { $0.id == 1 }?.x == 0)
        let smallDisplay = await session.windowEvents([event(initial, 3, .screens([screen("small", 20, 30, 300, 180)]))])
        let fitted = try #require(smallDisplay.windows.first { $0.id == 1 })
        #expect(fitted.frame == WindowRect(x: 20, y: 30, width: 300, height: 180))
        #expect(fitted.minimumWidth == 300 && fitted.minimumHeight == 180)
        let modelLimits = await session.evaluate("window minimumWidth")
        #expect(modelLimits.value == "610")
    }

    @Test func placementAndCloseRulesAreEditableInTheLiveImage() async throws {
        let session = SmalltalkSession()
        let edited = await session.evaluate("""
        DesktopManager compile: 'screenFor: aWindow ^ nil'.
        SystemWindow compile: 'canClose ^ self title ~= ''Keep me'''.
        window := Desktop openWorkspace.
        window title: 'Keep me'; moveToX: -900 y: 300
        """)
        #expect(edited.error == nil)
        let id = try #require(edited.activeWindowID)
        let keep = await session.windowEvents([event(edited, 1, .closeRequested(id))])
        #expect(keep.windows.contains { $0.id == id })
        #expect(keep.windows.first { $0.id == id }?.x == -900)
        _ = await session.evaluate("window title: 'Now close'")
        let close = await session.windowEvents([event(edited, 2, .closeRequested(id))])
        #expect(!close.windows.contains { $0.id == id })
        #expect(close.error == nil)
    }

    @Test func nativeFactsDoNotInvokeRequestsAndStaleRepliesCannotUndoNewGeometry() async throws {
        let session = SmalltalkSession()
        let initial = await session.evaluate("""
        requests := 0.
        DesktopManager compile: 'activate: aWindow requests := requests + 1. model requestFocus. ^ self bringToFront: aWindow'.
        Desktop activeWindow moveToX: 500 y: 400
        """)
        let window = try #require(initial.windows.first { $0.id == 1 })
        let changed = await session.windowEvents([
            event(initial, 1, .activated(2)),
            event(initial, 2, .frameApplied(1, request: window.frameRevision - 1, WindowRect(x: 1, y: 2, width: 600, height: 400)))
        ])
        #expect(changed.activeWindowID == 2)
        #expect(changed.windows.first { $0.id == 1 }?.x == 500)
        let requests = await session.evaluate("requests")
        #expect(requests.value == "0")
        let observed = WindowRect(x: 333, y: 222, width: 699, height: 499)
        let facts = await session.windowEvents([event(initial, 3, .frame(1, observed))])
        #expect(facts.windows.first { $0.id == 1 }?.frame == observed)
        let ignored = await session.windowEvents([event(initial, 2, .frame(1, WindowRect(x: 0, y: 0, width: 1, height: 1)))])
        #expect(ignored.windows.first { $0.id == 1 }?.frame == observed)
        let restarted = await session.reset()
        let stale = await session.windowEvents([event(initial, 999, .closeRequested(1))])
        #expect(stale.windows.count == restarted.windows.count)
        #expect(stale.windowCommands.acknowledgedEvent == 0)
    }

    @Test func windowAndDesktopModelsNotifyOrdinarySmalltalkObservers() async throws {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
        Object subclass: #WindowObserver instanceVariableNames: 'updates'.
        WindowObserver compile: 'initialize updates := 0'.
        WindowObserver compile: 'update: aspect updates := updates + 1'.
        WindowObserver compile: 'updates ^ updates'.
        observer := WindowObserver new.
        Desktop model addDependent: observer.
        Desktop activeWindow addDependent: observer.
        Desktop activeWindow title: 'Observed'.
        Desktop openWorkspace.
        observer updates
        """)
        #expect(result.error == nil)
        #expect((Int(result.value ?? "0") ?? 0) > 1)
        let type = await session.evaluate("Desktop model class superclass name")
        #expect(type.value == "#Model")
        let controller = await session.evaluate("Desktop class superclass name")
        #expect(controller.value == "#Controller")
    }

    @Test func replacingTheDesktopCannotRetargetCallbacksFromOldWindowObjects() async throws {
        let session = SmalltalkSession()
        let initial = await session.snapshot()
        let old = try #require(initial.windows.first { $0.id == 1 })
        let replacement = await session.evaluate("Desktop := DesktopManager new. Desktop openWorkspace")
        let current = try #require(replacement.windows.first)
        #expect(current.id == old.id && current.identity != old.identity)
        let stale = NativeWindowEvent(epoch: initial.windowCommands.epoch, sequence: 1, kind: .closeRequested(1), windowIdentity: old.identity)
        let ignored = await session.windowEvents([stale])
        #expect(ignored.windows.first?.identity == current.identity)
        #expect(ignored.windows.count == 1)
    }


}
