import Testing
@testable import SmalltalkCore

struct ToolWindowTests {
    private func element(_ id: String, in root: UIElementInfo?) -> UIElementInfo? {
        guard let root else { return nil }
        if root.accessibilityID == id { return root }
        return root.children.lazy.compactMap { element(id, in: $0) }.first
    }

    @Test func toolLayoutsAndActionsRunFromTheImage() async throws {
        let session = SmalltalkSession()
        let snapshot = await session.snapshot()
        #expect(snapshot.error == nil)
        let workspace = try #require(snapshot.windows.first(where: { $0.kind == .workspace }))
        let browser = try #require(snapshot.windows.first(where: { $0.kind == .browser }))
        let transcript = try #require(snapshot.windows.first(where: { $0.kind == .transcript }))
        let editor = try #require(element("workspaceEditor", in: workspace.content))
        let execute = try #require(element("executeButton", in: workspace.content))
        #expect(editor.kind == .codeEditor)
        #expect(execute.selectionSource == editor.id)

        let edited = await session.uiAction(.text(windowID: workspace.id, elementID: editor.id, value: "Object subclass: #ToolExample instanceVariableNames: ''. Transcript show: 'live'"))
        #expect(edited.windows.first(where: { $0.id == workspace.id })?.text.contains("ToolExample") == true)
        let selected = await session.uiAction(.click(windowID: workspace.id, elementID: execute.id, selection: "6 * 7"))
        #expect(element("evaluationResult", in: selected.windows.first(where: { $0.id == workspace.id })?.content)?.text == "42")
        let executed = await session.uiAction(.click(windowID: workspace.id, elementID: execute.id))
        #expect(executed.error == nil)
        #expect(element("transcriptOutput", in: executed.windows.first(where: { $0.id == transcript.id })?.content)?.text == "live")
        let classes = try #require(element("classList", in: executed.windows.first(where: { $0.id == browser.id })?.content))
        #expect(classes.items.contains("ToolExample"))

        _ = await session.uiAction(.select(windowID: browser.id, elementID: classes.id, value: "ToolExample"))
        let methodEditor = try #require(element("methodEditor", in: browser.content))
        let accept = try #require(element("executeButton", in: browser.content))
        _ = await session.uiAction(.text(windowID: browser.id, elementID: methodEditor.id, value: "answer ^ 73"))
        let accepted = await session.uiAction(.click(windowID: browser.id, elementID: accept.id))
        #expect(accepted.error == nil)
        let methodList = element("methodList", in: accepted.windows.first(where: { $0.id == browser.id })?.content)
        #expect(methodList?.selection == "answer")
        #expect(await session.evaluate("ToolExample new answer").value == "73")

        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(session.imageData())
        #expect(element("transcriptOutput", in: loaded.evaluation.windows.first(where: { $0.id == transcript.id })?.content)?.text == "live")
        #expect(element("methodList", in: loaded.evaluation.windows.first(where: { $0.id == browser.id })?.content)?.selection == "answer")
    }
}
