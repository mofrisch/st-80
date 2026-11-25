import Testing
@testable import SmalltalkCore

struct ToolExecutionBudgetTests {
    private func element(_ id: String, in root: UIElementInfo?) -> UIElementInfo? {
        guard let root else { return nil }
        if root.accessibilityID == id { return root }
        return root.children.lazy.compactMap { element(id, in: $0) }.first
    }

    @Test(arguments: ["evaluateSource:", "inspectSource:"])
    func repeatedToolSourcesShareTheEnclosingExecutionBudget(_ selector: String) async throws {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            count := 0.
            20 timesRepeat: [ ToolVM \(selector) '1000 timesRepeat: [ count := count + 1 ]' ].
            count
            """)
        #expect(result.executionError?.contains("100,000 steps") == true)
        let count = try #require(await session.evaluate("count").value.flatMap(Int.init))
        #expect(count > 0 && count < 20_000)
        #expect(await session.evaluate("6 * 7").value == "42")
    }

    @Test(arguments: ["evaluateSource:", "inspectSource:"])
    func deepToolSourcesCannotRefillTheCallDepthBudget(_ selector: String) async throws {
        let session = SmalltalkSession()
        #expect(await session.evaluate("Object subclass: #ToolDepthProbe instanceVariableNames: ''").error == nil)
        #expect(await session.compile("""
            plainDown: n
                n = 0 ifTrue: [ ^ 7 ].
                ^ self plainDown: n - 1
            """, in: "ToolDepthProbe").error == nil)
        #expect(await session.compile("""
            toolDown: n selector: aSelector
                n = 0 ifTrue: [
                    ^ ToolVM perform: aSelector with: 'ToolDepthProbe new plainDown: 60' ].
                ^ self toolDown: n - 1 selector: aSelector
            """, in: "ToolDepthProbe").error == nil)

        // Each recursion fits separately. Their real combined native stack
        // must still obey the one 128-level interpreter limit.
        #expect(await session.evaluate("ToolDepthProbe new plainDown: 60").value == "7")
        let deep = await session.evaluate("ToolDepthProbe new toolDown: 100 selector: #\(selector)")
        #expect(deep.executionError == nil)
        #expect(deep.value?.hasPrefix("#(false ") == true)
        #expect(deep.value?.contains("Maximum call depth") == true)
        #expect(await session.evaluate("ToolVM evaluateSource: '6 * 7'").value == "#(true '42')")
    }

    @Test(arguments: [false, true])
    func inspectorCreationRespectsTheCallingEvaluationBudget(depthLimit: Bool) async throws {
        let session = SmalltalkSession()
        let failure = await session.worker.submit { runtime -> String? in
            runtime.steps = depthLimit ? 0 : 99_999
            runtime.depth = depthLimit ? 127 : 0
            defer { runtime.steps = 0; runtime.depth = 0 }
            do {
                try runtime.requestInspection(.integer(42))
                return nil
            } catch { return error.localizedDescription }
        }
        #expect(failure?.contains(depthLimit ? "Maximum call depth" : "100,000 steps") == true)
        let result = await session.inspectSource("Counter new add: 7")
        #expect(result.executionError == nil)
        let inspector = try #require(result.toolRequests.compactMap { request -> InspectorSnapshot? in
            if case .openInspector(let snapshot) = request { return snapshot }
            return nil
        }.first)

        // Refresh is a separate worker command and retains its own fresh
        // budget, independently of the evaluation that opened the inspector.
        await session.worker.submit { $0.steps = 100_001 }
        let refreshed = await session.inspect(inspector.id, action: .refresh)
        #expect(refreshed?.rows.first { $0.id == .field("count") }?.preview == "7")
    }

    @Test func normalWorkspaceExecutionKeepsAnAmpleSourceBudget() async throws {
        let session = SmalltalkSession()
        let initial = await session.snapshot()
        let workspace = try #require(initial.windows.first { $0.kind == .workspace })
        let editor = try #require(element("workspaceEditor", in: workspace.content))
        let execute = try #require(element("executeButton", in: workspace.content))
        let source = "withinBudget := 0. 3000 timesRepeat: [ withinBudget := withinBudget + 1 ]. withinBudget"
        #expect(await session.uiAction(.text(windowID: workspace.id, elementID: editor.id, value: source)).executionError == nil)
        let executed = await session.uiAction(.click(windowID: workspace.id, elementID: execute.id))
        #expect(executed.executionError == nil)
        #expect(element("evaluationResult", in: executed.windows.first { $0.id == workspace.id }?.content)?.text == "3000")
        #expect(await session.evaluate("withinBudget").value == "3000")
    }
}
