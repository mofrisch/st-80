import Foundation
import SmalltalkCore
import Testing
@testable import Smalltalk80

struct WindowRecoveryPresentationTests {
    @Test func aNewValidWorkspaceCanBeAdoptedWhenNoRepairEditorWasRetained() async throws {
        let session = SmalltalkSession()
        _ = await session.windowAction(.close(1))
        let initial = await session.snapshot()
        var presentation = WindowPresentation()
        presentation.update(from: initial, replacingWindows: true)
        #expect(presentation.workspace == nil)
        let damaged = await session.evaluate("heldBrowser := (Desktop windowAt: 2) content. (Desktop windowAt: 2) content: 7")
        #expect(!damaged.hasCompleteWindowProjection)
        presentation.update(from: damaged, replacingWindows: false)
        #expect(presentation.workspace == nil)
        let opened = await session.windowAction(.showWorkspace)
        #expect(!opened.hasCompleteWindowProjection)
        presentation.update(from: opened, replacingWindows: false)
        let workspace = try #require(presentation.workspace?.info)
        #expect(presentation.isRecovering)
        #expect(presentation.activeID == workspace.id)
        let repaired = await session.recoverWorkspace(source: "(Desktop windowAt: 2) content: heldBrowser. 42", action: .evaluate,
                                                      windowID: workspace.id, identity: workspace.identity,
                                                      epoch: opened.windowCommands.epoch)
        #expect(repaired.error == nil)
        #expect(repaired.value == "42")
        presentation.update(from: repaired, replacingWindows: false)
        #expect(!presentation.isRecovering)
        #expect(presentation.workspace?.info.identity == workspace.identity)
    }

    @Test func invalidProjectionPreservesWindowsDocumentsDraftsAndSelectionUntilRepair() async throws {
        let session = SmalltalkSession()
        let initial = await session.snapshot()
        let workspace = try #require(initial.windows.first { $0.kind == .workspace })
        let editor = try #require(workspace.content?.firstVisible { $0.accessibilityID == "workspaceEditor" })
        var presentation = WindowPresentation()
        presentation.update(from: initial, replacingWindows: true)
        let document = URL(fileURLWithPath: "/private/tmp/Recovery.st")
        presentation.setDocumentURL(document, for: workspace.id)
        var edits = ControlEdits()
        edits.reconcile(with: presentation.windows.map(\.info))
        let address = ControlAddress(windowID: workspace.id, elementID: editor.id)
        let draft = "Desktop model windows: heldWindows. 6 * 7"
        edits.recordText(draft, at: address)
        edits.recordSelection(NSRange(location: 0, length: 7), at: address)

        let broken = await session.evaluate("heldWindows := Desktop windows. Desktop model windows: nil")
        #expect(!broken.hasCompleteWindowProjection)
        #expect(broken.windows.isEmpty)
        #expect(broken.windowProjectionError == "Desktop has no valid window list.")
        let nativeFailure = await session.windowEvents([
            NativeWindowEvent(epoch: initial.windowCommands.epoch, sequence: 1, kind: .activated(workspace.id))
        ])
        #expect(nativeFailure.executionError != nil)
        #expect(nativeFailure.windowProjectionError == broken.windowProjectionError)
        presentation.update(from: broken, replacingWindows: false)
        edits.reconcile(with: presentation.windows.map(\.info))
        #expect(presentation.isRecovering)
        #expect(presentation.windows.map { $0.info.identity } == initial.windows.map(\.identity))
        #expect(presentation.activeID == initial.activeWindowID)
        #expect(presentation.window(workspace.id)?.documentURL == document)
        #expect(edits.text(at: address, fallback: "") == draft)
        #expect(edits.selection(at: address) == NSRange(location: 0, length: 7))
        #expect(edits.hasPendingEdits)

        let repaired = await session.recoverWorkspace(source: draft, action: .evaluate, windowID: workspace.id,
                                                      identity: workspace.identity, epoch: initial.windowCommands.epoch)
        #expect(repaired.error == nil)
        #expect(repaired.value == "42")
        #expect(repaired.windowProjectionError == nil)
        presentation.update(from: repaired, replacingWindows: false)
        edits.reconcile(with: presentation.windows.map(\.info))
        #expect(!presentation.isRecovering)
        #expect(presentation.window(workspace.id)?.documentURL == document)
        #expect(edits.text(at: address, fallback: "") == draft)
        let edit = try #require(edits.pendingEdits.first)
        let acknowledged = await session.uiAction(.text(windowID: workspace.id, elementID: editor.id, value: draft))
        #expect(acknowledged.error == nil)
        presentation.update(from: acknowledged, replacingWindows: false)
        edits.reconcile(with: presentation.windows.map(\.info))
        edits.acknowledge(edit)
        #expect(!edits.hasPendingEdits)
        #expect(edits.text(at: address, fallback: "") == draft)
    }

    @Test func partialProjectionCannotRemoveTheDamagedWindowOrPublishItsBrokenControls() async throws {
        let session = SmalltalkSession()
        let initial = await session.snapshot()
        let workspace = try #require(initial.windows.first { $0.kind == .workspace })
        var presentation = WindowPresentation()
        presentation.update(from: initial, replacingWindows: true)
        let broken = await session.windowAction(.frame(workspace.id, x: workspace.x, y: workspace.y,
                                                       width: 0, height: workspace.height))
        #expect(!broken.hasCompleteWindowProjection)
        #expect(!broken.windows.isEmpty)
        #expect(!broken.windows.contains { $0.id == workspace.id })
        presentation.update(from: broken, replacingWindows: false)
        #expect(presentation.isRecovering)
        #expect(presentation.window(workspace.id)?.info.frame == workspace.frame)
        #expect(presentation.window(workspace.id)?.info.content?.id == workspace.content?.id)
    }

    @Test func ordinaryExecutionErrorsAndValidWindowClosuresRemainAuthoritative() async throws {
        let session = SmalltalkSession()
        let initial = await session.snapshot()
        let workspace = try #require(initial.windows.first { $0.kind == .workspace })
        var presentation = WindowPresentation()
        presentation.update(from: initial, replacingWindows: true)
        let failed = await session.evaluate("missingRecoveryVariable")
        #expect(failed.executionError != nil)
        #expect(failed.hasCompleteWindowProjection)
        presentation.update(from: failed, replacingWindows: false)
        #expect(!presentation.isRecovering)
        #expect(presentation.window(workspace.id) != nil)

        let closed = await session.windowAction(.close(workspace.id))
        #expect(closed.error == nil)
        presentation.update(from: closed, replacingWindows: false)
        #expect(!presentation.isRecovering)
        #expect(presentation.window(workspace.id) == nil)
    }

    @Test func replacementNeverRetainsThePreviousWorldsWindows() async throws {
        let session = SmalltalkSession()
        var presentation = WindowPresentation()
        presentation.update(from: await session.snapshot(), replacingWindows: true)
        let invalid = await session.evaluate("Desktop model windows: nil")
        presentation.update(from: invalid, replacingWindows: true)
        #expect(presentation.isRecovering)
        #expect(presentation.windows.isEmpty)
        #expect(presentation.workspace == nil)
    }
}
