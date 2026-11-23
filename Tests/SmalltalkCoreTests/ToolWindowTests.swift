import Testing
@testable import SmalltalkCore

struct ToolWindowTests {
    private func element(_ id: String, in root: UIElementInfo?) -> UIElementInfo? {
        guard let root else { return nil }
        if root.accessibilityID == id { return root }
        return root.children.lazy.compactMap { element(id, in: $0) }.first
    }

    @Test func browserFiltersClassesAndMethodsThroughFourPanes() async throws {
        let session = SmalltalkSession()
        let snapshot = await session.snapshot()
        let browser = try #require(snapshot.windows.first(where: { $0.kind == .browser }))
        let navigation = try #require(element("browserNavigation", in: browser.content))
        #expect(navigation.children.map { $0.children.last?.accessibilityID } == ["categoryList", "classList", "protocolList", "methodList"])

        let categories = try #require(element("categoryList", in: browser.content))
        let classes = try #require(element("classList", in: browser.content))
        let protocols = try #require(element("protocolList", in: browser.content))
        let methods = try #require(element("methodList", in: browser.content))
        let editor = try #require(element("methodEditor", in: browser.content))
        let accept = try #require(element("executeButton", in: browser.content))

        func select(_ list: UIElementInfo, _ entry: String) async -> UIElementInfo? {
            let result = await session.uiAction(.select(windowID: browser.id, elementID: list.id, value: entry))
            #expect(result.error == nil)
            return result.windows.first(where: { $0.id == browser.id })?.content
        }

        let kernel = await select(categories, "Kernel")
        #expect(element("classList", in: kernel)?.items.contains("Object") == true)
        #expect(element("classList", in: kernel)?.selection == nil)
        let examples = await select(categories, "Beispiele")
        #expect(element("classList", in: examples)?.items == ["Counter"])
        let counter = await select(classes, "Counter")
        #expect(element("protocolList", in: counter)?.items == ["Alle", "Initialisierung", "Unär", "Schlüsselwort"])
        let unary = await select(protocols, "Unär")
        #expect(element("methodList", in: unary)?.items == ["increment", "value"])
        let value = await select(methods, "value")
        #expect(element("methodEditor", in: value)?.text == "value ^ count")

        _ = await session.uiAction(.text(windowID: browser.id, elementID: editor.id, value: "adjusted: amount ^ count + amount"))
        let accepted = await session.uiAction(.click(windowID: browser.id, elementID: accept.id))
        #expect(accepted.error == nil)
        let content = accepted.windows.first(where: { $0.id == browser.id })?.content
        #expect(element("protocolList", in: content)?.selection == "Alle")
        #expect(element("methodList", in: content)?.selection == "adjusted:")
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
