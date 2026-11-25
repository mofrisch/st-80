import SmalltalkCore
import Testing
@testable import Smalltalk80

@MainActor
struct BrowserAcceptTests {
    private func selectMethod(in controller: AppController) async throws -> (windowID: Int64, editor: UIElementInfo, accept: UIElementInfo) {
        let session = controller.session
        let initial = await session.snapshot()
        let browser = try #require(initial.windows.first { $0.kind == .browser })
        let methods = try #require(browser.content?.firstVisible { $0.accessibilityID == "methodList" })
        _ = await session.windowAction(.activate(browser.id))
        let selected = await session.uiAction(.select(windowID: browser.id, elementID: methods.id, value: "value"))
        try #require(selected.error == nil)
        controller.apply(selected, replacingWindows: true)
        let content = try #require(selected.windows.first { $0.id == browser.id }?.content)
        let editor = try #require(content.firstVisible { $0.accessibilityID == "methodEditor" })
        let accept = try #require(content.firstVisible { $0.command == "acceptMethod" })
        return (browser.id, editor, accept)
    }

    @Test func acceptShortcutChecksAvailabilityAfterSendingThePendingDraft() async throws {
        let controller = AppController()
        let browser = try await selectMethod(in: controller)
        #expect(!browser.accept.enabled)
        #expect(!controller.hasCommand("acceptMethod"))

        controller.editInput(windowID: browser.windowID, elementID: browser.editor.id, text: "value ^ 42")
        #expect(!controller.canPerform(browser.accept, in: browser.windowID))
        #expect(controller.hasCommand("acceptMethod"))
        await controller.performCommand("acceptMethod")

        #expect(await controller.session.evaluate("Counter new value").value == "42")
        #expect(!controller.hasCommand("acceptMethod"))
    }

    @Test func acceptDoesNotInstallAnOlderDraftWhenThePendingEditIsRejected() async throws {
        let controller = AppController()
        let browser = try await selectMethod(in: controller)
        let session = controller.session
        let edited = await session.uiAction(.text(windowID: browser.windowID, elementID: browser.editor.id, value: "value ^ 42"))
        try #require(edited.error == nil)
        let configured = await session.compile(
            "editText: source self error: 'Rejected editor input' line: 1 column: 1",
            in: "UICodeEditor"
        )
        try #require(configured.error == nil)
        controller.apply(configured)
        #expect(controller.hasCommand("acceptMethod"))

        let draft = "value ^ 73"
        controller.editInput(windowID: browser.windowID, elementID: browser.editor.id, text: draft)
        await controller.performCommand("acceptMethod")

        #expect(controller.presentedWindow(browser.windowID)?.inputError?.contains("Rejected editor input") == true)
        #expect(controller.inputText(windowID: browser.windowID, element: browser.editor) == draft)
        let result = await session.evaluate("Counter new value")
        #expect(result.value == "0")
        #expect(result.changes.map(\.id) == configured.changes.map(\.id))
    }
}
