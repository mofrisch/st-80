import Testing
@testable import SmalltalkCore

struct ToolWindowTests {
    private func element(_ id: String, in root: UIElementInfo?) -> UIElementInfo? {
        guard let root else { return nil }
        if root.accessibilityID == id { return root }
        return root.children.lazy.compactMap { element(id, in: $0) }.first
    }

    @Test func examplesMenuUsesTheCatalogStoredInTheImage() async throws {
        let original = SmalltalkSession()
        let edited = await original.evaluate("""
        WorkspaceExamples compileClass: 'workspace ^ ''exampleWasRun := true. 6 * 7'''.
        WorkspaceExamples compileClass: 'menuEntries ^ #((#workspace ''Edited Counter''))'.
        Desktop openWorkspace
        """)
        try #require(edited.error == nil)
        let lastWorkspace = try #require(edited.windows.first { $0.id == edited.activeWindowID && $0.kind == .workspace })
        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(original.imageData())
        let window = try #require(loaded.evaluation.windows.first { $0.id == lastWorkspace.id })
        let menu = try #require(window.content?.children.first { $0.role == "applicationMenu" })
        #expect(menu.children.map(\.text) == ["Edited Counter"])

        let example = try #require(menu.children.first)
        let opened = await restored.uiAction(.click(windowID: window.id, elementID: example.id))
        try #require(opened.error == nil)
        let workspace = try #require(opened.windows.first { $0.id == opened.activeWindowID && $0.kind == .workspace })
        #expect(workspace.id != window.id)
        #expect(workspace.text == "exampleWasRun := true. 6 * 7")
        #expect(!opened.bindings.contains { $0.name == "exampleWasRun" })
    }

    @Test func workspacePublishesApplicationCommandsIndependentlyOfTheEditorMenu() async throws {
        let session = SmalltalkSession()
        let snapshot = try await openTools(.workspace, in: session)
        let workspace = try #require(snapshot.windows.first { $0.kind == .workspace })
        let editor = try #require(element("workspaceEditor", in: workspace.content))
        let menu = try #require(workspace.content?.children.first { $0.role == "applicationCommands" })
        #expect(menu.children.map(\.command) == ["doIt", "printIt", "inspectIt", "debugIt"])
        #expect(menu.children.allSatisfy { $0.enabled && $0.selectionSource == editor.id })
        let print = try #require(menu.children.first { $0.command == "printIt" })
        #expect(print.id != editor.contextMenuItems?.first { $0.command == "printIt" }?.id)

        _ = await session.uiAction(.text(windowID: workspace.id, elementID: editor.id, value: "1 / 0"))
        let printed = await session.uiAction(.click(windowID: workspace.id, elementID: print.id, selection: "3 + 4"))
        #expect(printed.error == nil)
        #expect(printed.transcript == "→ 7\n")
    }

    @Test func workspaceContextMenuDispatchesTheSelectedSourceAndSurvivesImageLoad() async throws {
        let session = SmalltalkSession()
        let snapshot = try await openTools(.workspace, in: session)
        let workspace = try #require(snapshot.windows.first { $0.kind == .workspace })
        let editor = try #require(element("workspaceEditor", in: workspace.content))
        let menu = try #require(editor.contextMenuItems)
        #expect(menu.map(\.text) == ["Do it", "Print it", "Inspect it", "Debug it"])
        #expect(menu.map(\.command) == ["doIt", "printIt", "inspectIt", "debugIt"])
        #expect(menu.allSatisfy { $0.enabled && $0.selectionSource == editor.id })

        func click(_ command: String, selection: String) async throws -> EvaluationResult {
            let item = try #require(menu.first { $0.command == command })
            let result = await session.uiAction(.click(windowID: workspace.id, elementID: item.id, selection: selection))
            #expect(result.executionError == nil)
            return result
        }

        // Evaluating the full buffer would fail. Each item must use just
        // the source passed along with the context-menu event.
        _ = await session.uiAction(.text(windowID: workspace.id, elementID: editor.id, value: "1 / 0"))
        let executed = try await click("doIt", selection: "6 * 7")
        let updatedWorkspace = executed.windows.first { $0.id == workspace.id }
        #expect(element("evaluationResult", in: updatedWorkspace?.content)?.text == "42")
        let printed = try await click("printIt", selection: "3 + 4")
        #expect(printed.transcript == "→ 7\n")
        let debug = try await click("debugIt", selection: "20 + 22")
        #expect(debug.toolRequests.contains { request in
            if case .debugWorkspace(let id, let identity, let source) = request {
                return id == workspace.id && identity == workspace.identity && source == "20 + 22"
            }
            return false
        })

        _ = await session.evaluate("inspectionRuns := 0")
        let inspected = try await click("inspectIt", selection: "inspectionRuns := inspectionRuns + 1. Counter new add: inspectionRuns")
        let inspectors = inspected.toolRequests.compactMap { request -> InspectorSnapshot? in
            if case .openInspector(let inspector) = request { return inspector }
            return nil
        }
        let inspector = try #require(inspectors.first)
        #expect(inspectors.count == 1)
        #expect(inspector.className == "Counter")
        #expect(inspector.rows.first { $0.id == .field("count") }?.preview == "1")
        #expect(await session.evaluate("inspectionRuns").value == "1")

        let restored = SmalltalkSession()
        let image = try await session.imageData()
        let loaded = try await restored.loadImage(image)
        let loadedWorkspace = try #require(loaded.evaluation.windows.first { $0.kind == .workspace })
        let loadedEditor = try #require(element("workspaceEditor", in: loadedWorkspace.content))
        let loadedMenu = try #require(loadedEditor.contextMenuItems)
        #expect(loadedMenu.map(\.command) == menu.map(\.command))
        #expect(loadedMenu.allSatisfy { $0.selectionSource == loadedEditor.id })
        let oldInspect = try #require(menu.first { $0.command == "inspectIt" })
        let stale = await restored.uiAction(.click(windowID: loadedWorkspace.id, elementID: oldInspect.id, selection: "1"))
        #expect(stale.toolRequests.isEmpty)
        let restoredInspect = try #require(loadedMenu.first { $0.command == "inspectIt" })
        let live = await restored.uiAction(.click(windowID: loadedWorkspace.id, elementID: restoredInspect.id, selection: "inspectionRuns"))
        #expect(live.toolRequests.contains {
            if case .openInspector(let inspector) = $0 { return inspector.summary == "1" }
            return false
        })
    }

    @Test func everyShippedBrowserMethodBelongsToExactlyOneProtocol() throws {
        let runtime = SmalltalkRuntime()
        let organization = try #require(runtime.globals["SystemOrganization"])

        func elements(_ value: Value) throws -> [Value] {
            guard case .array(let array) = value else {
                throw SmalltalkError("Expected an array in the shipped protocol declarations.")
            }
            return array.elements
        }

        let declarations = try elements(runtime.send(organization, "shippedProtocols", []))
        var selectorsByClass: [String: Set<String>] = [:]
        for declaration in declarations {
            let classEntry = try elements(declaration)
            try #require(classEntry.count == 2)
            let className = try runtime.string(classEntry[0])
            #expect(selectorsByClass[className] == nil, "Repeated class \(className)")
            var protocolNames: Set<String> = []
            var selectors: Set<String> = []
            for specification in try elements(classEntry[1]) {
                let protocolEntry = try elements(specification)
                try #require(protocolEntry.count == 2)
                let title = try runtime.string(protocolEntry[0])
                #expect(protocolNames.insert(title).inserted, "Repeated protocol \(className) » \(title)")
                for value in try elements(protocolEntry[1]) {
                    let selector = try runtime.string(value)
                    #expect(selectors.insert(selector).inserted, "Repeated selector \(className) » \(selector)")
                }
            }
            selectorsByClass[className] = selectors
        }

        var shippedClasses: Set<String> = []
        for (name, stClass) in runtime.classes {
            let reflected = try elements(runtime.send(.classObject(stClass), "methodNames", [])).map(runtime.string)
            if !reflected.isEmpty { shippedClasses.insert(name) }
            let expected = Set(reflected)
            let assigned = selectorsByClass[name] ?? []
            #expect(expected.subtracting(assigned).isEmpty, "Unclassified on \(name): \(expected.subtracting(assigned).sorted())")
            #expect(assigned.subtracting(expected).isEmpty, "Unknown on \(name): \(assigned.subtracting(expected).sorted())")
        }
        #expect(Set(selectorsByClass.keys) == shippedClasses)
    }

    @Test func browserFiltersClassesAndMethodsThroughFourPanes() async throws {
        let session = SmalltalkSession()
        let snapshot = try await openTools(.browser, in: session)
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
        let examples = await select(categories, "Examples")
        #expect(element("classList", in: examples)?.items == ["Counter", "WorkspaceExamples"])
        let counter = await select(classes, "Counter")
        #expect(element("protocolList", in: counter)?.items == ["All", "Initialization", "Accessing", "Counting"])
        let counting = await select(protocols, "Counting")
        #expect(element("methodList", in: counting)?.items == ["add:", "increment"])
        let increment = await select(methods, "increment")
        #expect(element("methodEditor", in: increment)?.text == "increment\n    count := count + 1")

        _ = await session.uiAction(.text(windowID: browser.id, elementID: editor.id, value: "adjusted: amount ^ count + amount"))
        let accepted = await session.uiAction(.click(windowID: browser.id, elementID: accept.id))
        #expect(accepted.error == nil)
        let content = accepted.windows.first(where: { $0.id == browser.id })?.content
        #expect(element("protocolList", in: content)?.selection == "Counting")
        #expect(element("methodList", in: content)?.items == ["add:", "adjusted:", "increment"])
        #expect(element("methodList", in: content)?.selection == "adjusted:")
    }

    @Test func browserSwitchesSidesWithoutLosingDraftsOrMixingProtocols() async throws {
        let session = SmalltalkSession()
        let snapshot = try await openTools(.browser, in: session)
        let browser = try #require(snapshot.windows.first { $0.kind == .browser })
        var content = try #require(browser.content)

        @discardableResult
        func perform(_ identifier: String, _ action: (String) -> UIAction) async throws -> EvaluationResult {
            let control = try #require(element(identifier, in: content))
            let result = await session.uiAction(action(control.id))
            try #require(result.error == nil, "\(identifier): \(result.error ?? "")")
            content = try #require(result.windows.first { $0.id == browser.id }?.content)
            return result
        }

        @discardableResult
        func click(_ identifier: String) async throws -> EvaluationResult {
            try await perform(identifier) { .click(windowID: browser.id, elementID: $0) }
        }

        try await perform("methodList") { .select(windowID: browser.id, elementID: $0, value: "value") }
        try await perform("methodEditor") { .text(windowID: browser.id, elementID: $0, value: "value ^ count + 10") }
        try await click("classMethodSide")
        #expect(element("methodList", in: content)?.items == [])
        #expect(element("methodEditor", in: content)?.text == "Object subclass: #Counter\n    instanceVariableNames: 'count'")

        try await click("newProtocol")
        try await perform("organizationName") { .text(windowID: browser.id, elementID: $0, value: "Factories") }
        try await click("applyOrganizationEdit")
        try await click("newMethod")
        try await perform("methodEditor") { .text(windowID: browser.id, elementID: $0, value: "value ^ 73") }
        let installed = try await click("executeButton")
        #expect(element("protocolList", in: content)?.items == ["All", "Factories"])
        #expect(element("methodList", in: content)?.selection == "value")
        #expect(installed.changes.last?.side == .classSide)
        let history = try await click("methodVersionsButton")
        let historyWindow = try #require(history.windows.first { $0.kind == .changes })
        let historyList = try #require(element("changesList", in: historyWindow.content))
        #expect(historyList.historyEntries.map(\.title) == ["Counter class » value"])
        #expect(history.activeWindowID == historyWindow.id)
        #expect(history.toolRequests.isEmpty)

        try await click("instanceMethodSide")
        #expect(element("methodList", in: content)?.selection == "value")
        #expect(element("methodEditor", in: content)?.text == "value ^ count + 10")
        #expect(element("protocolList", in: content)?.items.contains("Factories") == false)
        #expect(await session.evaluate("Counter value + Counter new value").value == "73")

        try await click("classMethodSide")
        #expect(element("protocolList", in: content)?.selection == "Factories")
        #expect(element("methodEditor", in: content)?.text == "value ^ 73")
        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(session.imageData())
        let restoredContent = loaded.evaluation.windows.first { $0.kind == .browser }?.content
        #expect(element("classMethodSide", in: restoredContent)?.role == "primary")
        #expect(element("methodEditor", in: restoredContent)?.text == "value ^ 73")
    }

    @Test func browserBytecodeReflectsTheSelectedCompiledMethod() async throws {
        let session = SmalltalkSession()
        _ = try await openTools(.browser, in: session)
        let prepared = await session.compile("value ^ 73", in: "Counter", side: .classSide)
        #expect(prepared.error == nil)
        let browser = try #require(prepared.windows.first { $0.kind == .browser })
        #expect(browser.browserMethod == nil)
        let methodList = try #require(element("methodList", in: browser.content))
        let classList = try #require(element("classList", in: browser.content))
        let classSideButton = try #require(element("classMethodSide", in: browser.content))
        let instanceSideButton = try #require(element("instanceMethodSide", in: browser.content))

        func selection(in result: EvaluationResult) throws -> BrowserMethodSelection {
            #expect(result.error == nil)
            return try #require(result.windows.first { $0.id == browser.id }?.browserMethod)
        }

        let instanceMethod = try await selection(in: session.uiAction(.select(
            windowID: browser.id, elementID: methodList.id, value: "value"
        )))
        #expect(instanceMethod.className == "Counter")
        #expect(instanceMethod.selector == "value")
        #expect(instanceMethod.side == .instance)
        #expect(await session.browserBytecode(windowID: browser.id, method: instanceMethod)?.contains("LOAD count") == true)
        let toggle = try #require(element("methodBytecodeToggle", in: browser.content))
        let opened = await session.uiAction(.click(windowID: browser.id, elementID: toggle.id))
        let listing = try #require(element("bytecodeEditor", in: opened.windows.first { $0.id == browser.id }?.content))
        #expect(listing.visible && listing.readOnly)
        #expect(listing.text.contains("LOAD count"))


        _ = await session.uiAction(.click(windowID: browser.id, elementID: classSideButton.id))
        #expect(await session.browserBytecode(windowID: browser.id, method: instanceMethod) == nil)
        let classMethod = try await selection(in: session.uiAction(.select(
            windowID: browser.id, elementID: methodList.id, value: "value"
        )))
        #expect(classMethod.side == .classSide)
        #expect(await session.browserBytecode(windowID: browser.id, method: classMethod)?.contains("PUSH_LITERAL 73") == true)

        let replaced = try await selection(in: session.compile(
            "value ^ [ :item | item ] value: 94", in: "Counter", side: .classSide
        ))
        #expect(replaced != classMethod)
        #expect(await session.browserBytecode(windowID: browser.id, method: classMethod) == nil)
        let refreshedBytecode = try #require(await session.browserBytecode(windowID: browser.id, method: replaced))
        #expect(refreshedBytecode.contains("PUSH_LITERAL 94"))
        #expect(refreshedBytecode.contains("MAKE_BLOCK (item)\n    0000  LOAD item\n    0001  FINISH"))

        _ = await session.uiAction(.click(windowID: browser.id, elementID: instanceSideButton.id))
        _ = await session.uiAction(.select(windowID: browser.id, elementID: classList.id, value: "Object"))
        let primitive = try await selection(in: session.uiAction(.select(
            windowID: browser.id, elementID: methodList.id, value: "class"
        )))
        #expect(primitive.className == "Object")
        #expect(primitive.isPrimitive)
        #expect(await session.browserBytecode(windowID: browser.id, method: primitive) == nil)
    }

    @Test func rejectingABrowserDraftKeepsTheInstalledCodeAndJournalUnchanged() async throws {
        let session = SmalltalkSession()
        let initial = try await openTools(.browser, in: session)
        let browser = try #require(initial.windows.first { $0.kind == .browser })
        let methods = try #require(element("methodList", in: browser.content))
        let chosen = await session.uiAction(.select(windowID: browser.id, elementID: methods.id, value: "value"))
        let selected = try #require(chosen.windows.first { $0.id == browser.id })
        let method = try #require(selected.browserMethod)
        let source = try #require(element("methodEditor", in: selected.content))
        let accept = try #require(element("executeButton", in: selected.content))
        let installed = try #require(await session.browserBytecode(windowID: browser.id, method: method))

        let draft = "value\n    ^ ("
        _ = await session.uiAction(.text(windowID: browser.id, elementID: source.id, value: draft))
        let rejected = await session.uiAction(.click(windowID: browser.id, elementID: accept.id))
        let afterFailure = try #require(rejected.windows.first { $0.id == browser.id })
        let result = try #require(element("evaluationResult", in: afterFailure.content))
        #expect(result.role == "error")
        #expect(result.text.contains("Line 2"))
        #expect(element("methodEditor", in: afterFailure.content)?.text == draft)
        #expect(afterFailure.browserMethod == method)
        #expect(rejected.changes.map(\.id) == chosen.changes.map(\.id))
        #expect(await session.browserBytecode(windowID: browser.id, method: method) == installed)
        #expect(await session.evaluate("Counter new value").value == "0")

        let corrected = "value\n    ^ 42"
        _ = await session.uiAction(.text(windowID: browser.id, elementID: source.id, value: corrected))
        let accepted = await session.uiAction(.click(windowID: browser.id, elementID: accept.id))
        #expect(accepted.error == nil)
        #expect(accepted.changes.count == chosen.changes.count + 1)
        #expect(accepted.changes.last?.source == corrected)
        #expect(await session.browserBytecode(windowID: browser.id, method: method) == nil)
        #expect(await session.evaluate("Counter new value").value == "42")
    }

    @Test func transcriptKeepsAUnicodeSuffixAcrossAnImageRoundTripAndClearsThroughItsMenu() async throws {
        let session = SmalltalkSession()
        let initial = try await openTools(.transcript, in: session)
        let initialWindow = try #require(initial.windows.first { $0.kind == .transcript })
        #expect(element("transcriptOutput", in: initialWindow.content)?.text == "")
        let firstHalf = await session.evaluate("""
        chunk := '🌍'.
        1 to: 13 do: [ :index | chunk := chunk , chunk ].
        Transcript show: chunk
        """)
        try #require(firstHalf.error == nil)
        let full = await session.evaluate("Transcript show: chunk")
        let fullText = element("transcriptOutput", in: full.windows.first { $0.kind == .transcript }?.content)?.text
        #expect(full.error == nil)
        #expect(fullText?.utf8.count == 65_536)

        let appended = await session.evaluate("Transcript show: '✓'")
        try #require(appended.error == nil)
        let restored = try await session.loadImage(session.imageData())
        let window = try #require(restored.evaluation.windows.first { $0.kind == .transcript })
        let output = try #require(element("transcriptOutput", in: window.content)?.text)
        #expect(output.utf8.count == 65_535)
        #expect(output.first == "🌍")
        #expect(output.last == "✓")
        #expect(output.count == 16_384)

        let clear = try #require(window.content?.contextMenuItems?.first { $0.command == "clearTranscript" })
        let cleared = await session.uiAction(.click(windowID: window.id, elementID: clear.id))
        #expect(cleared.error == nil)
        #expect(element("transcriptOutput", in: cleared.windows.first { $0.id == window.id }?.content)?.text == "")
    }

    @Test func browserOrganizationEditsSurviveClosingTheBrowserAndLoadingAnImage() async throws {
        let session = SmalltalkSession()
        let snapshot = try await openTools(.browser, .browser, in: session)
        let browser = try #require(snapshot.windows.first { $0.kind == .browser })
        let otherBrowser = try #require(snapshot.windows.first { $0.kind == .browser && $0.id != browser.id })
        var content = try #require(browser.content)
        var otherContent = try #require(otherBrowser.content)

        func perform(_ identifier: String, _ action: (String) -> UIAction) async throws {
            let control = try #require(element(identifier, in: content))
            let result = await session.uiAction(action(control.id))
            try #require(result.error == nil, "\(identifier): \(result.error ?? "")")
            content = try #require(result.windows.first(where: { $0.id == browser.id })?.content)
            otherContent = try #require(result.windows.first(where: { $0.id == otherBrowser.id })?.content)
        }

        func click(_ identifier: String) async throws {
            try await perform(identifier) { .click(windowID: browser.id, elementID: $0) }
        }

        func select(_ identifier: String, _ value: String) async throws {
            try await perform(identifier) { .select(windowID: browser.id, elementID: $0, value: value) }
        }

        func edit(_ identifier: String, _ value: String) async throws {
            try await perform(identifier) { .text(windowID: browser.id, elementID: $0, value: value) }
        }

        func submitName(_ value: String) async throws {
            try await edit("organizationName", value)
            try await click("applyOrganizationEdit")
        }

        try await click("newCategory")
        try await submitName("Domain")
        #expect(element("categoryList", in: content)?.selection == "Domain")
        #expect(element("classList", in: content)?.items == [])
        #expect(element("categoryList", in: otherContent)?.items.contains("Domain") == true)

        try await click("newCategory")
        try await submitName("Domain")
        #expect(element("evaluationResult", in: content)?.text == "That name is already in use.")
        try await click("cancelOrganizationEdit")

        try await select("categoryList", "Examples")
        try await select("classList", "Counter")
        try await click("moveClass")
        try await select("organizationDestinations", "Domain")
        try await click("applyOrganizationEdit")
        try await click("renameCategory")
        try await submitName("Domain Models")
        #expect(element("categoryList", in: content)?.selection == "Domain Models")
        #expect(element("classList", in: content)?.items == ["Counter"])

        try await click("newProtocol")
        try await submitName("Reading")
        #expect(element("protocolList", in: content)?.selection == "Reading")
        #expect(element("methodList", in: content)?.items == [])
        #expect(element("protocolList", in: otherContent)?.items.contains("Reading") == true)
        try await click("newMethod")
        try await edit("methodEditor", "answer ^ 42")
        try await click("executeButton")
        #expect(element("methodList", in: content)?.items == ["answer"])

        try await click("renameProtocol")
        try await submitName("Queries")
        try await select("protocolList", "Accessing")
        try await select("methodList", "value")
        try await click("moveMethod")
        try await select("organizationDestinations", "Queries")
        try await click("applyOrganizationEdit")
        #expect(element("protocolList", in: content)?.selection == "Queries")
        #expect(element("methodList", in: content)?.items == ["answer", "value"])
        #expect(element("methodList", in: content)?.selection == "value")
        #expect(await session.evaluate("Counter new answer").value == "42")
        #expect(await session.evaluate("(SystemOrganization protocolsOf: String) names includes: 'Queries'").value == "false")

        try await click("newProtocol")
        try await submitName("Editing")
        #expect(element("methodList", in: content)?.items == [])

        _ = await session.windowAction(.close(otherBrowser.id))
        let closed = await session.windowAction(.close(browser.id))
        #expect(closed.windows.allSatisfy { $0.kind != .browser })
        let restored = SmalltalkSession()
        _ = try await restored.loadImage(session.imageData())
        let reopened = await restored.windowAction(.open(.browser))
        let restoredBrowser = try #require(reopened.windows.first(where: { $0.kind == .browser }))
        let restoredCategories = try #require(element("categoryList", in: restoredBrowser.content))
        #expect(restoredCategories.items.contains("Domain Models"))
        #expect(!restoredCategories.items.contains("Domain"))
        let restoredProtocols = try #require(element("protocolList", in: restoredBrowser.content))
        #expect(restoredProtocols.items.contains("Queries"))
        #expect(restoredProtocols.items.contains("Editing"))
        let filtered = await restored.uiAction(.select(windowID: restoredBrowser.id, elementID: restoredProtocols.id, value: "Queries"))
        #expect(element("methodList", in: filtered.windows.first(where: { $0.kind == .browser })?.content)?.items == ["answer", "value"])
    }

    @Test func toolLayoutsAndActionsRunFromTheImage() async throws {
        let session = SmalltalkSession()
        let snapshot = try await openTools(.workspace, .browser, .transcript, in: session)
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
        let newMethod = try #require(element("newMethod", in: browser.content))
        let accept = try #require(element("executeButton", in: browser.content))
        _ = await session.uiAction(.click(windowID: browser.id, elementID: newMethod.id))
        _ = await session.uiAction(.text(windowID: browser.id, elementID: methodEditor.id, value: "answer ^ 73"))
        let accepted = await session.uiAction(.click(windowID: browser.id, elementID: accept.id))
        #expect(accepted.error == nil)
        let methodList = element("methodList", in: accepted.windows.first(where: { $0.id == browser.id })?.content)
        #expect(methodList?.selection == "answer")
        let protocolList = element("protocolList", in: accepted.windows.first(where: { $0.id == browser.id })?.content)
        #expect(protocolList?.items == ["All", "Unclassified"])
        #expect(await session.evaluate("ToolExample new answer").value == "73")

        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(session.imageData())
        #expect(element("transcriptOutput", in: loaded.evaluation.windows.first(where: { $0.id == transcript.id })?.content)?.text == "live")
        #expect(element("methodList", in: loaded.evaluation.windows.first(where: { $0.id == browser.id })?.content)?.selection == "answer")
    }

    @Test func browserEditsTheSelectedClassDefinitionAndPreservesLiveInstances() async throws {
        let session = SmalltalkSession()
        _ = try await openTools(.browser, in: session)
        let setup = await session.evaluate("""
            Object subclass: #DefinitionParent instanceVariableNames: 'inherited'.
            Object subclass: #DefinitionExample instanceVariableNames: 'count'.
            DefinitionExample subclass: #DefinitionChild instanceVariableNames: 'child'.
            DefinitionExample compile: 'count ^ count'.
            DefinitionExample compile: 'count: value count := value'.
            live := DefinitionChild new count: 42; yourself.
            identity := DefinitionExample
            """)
        #expect(setup.error == nil)
        let browser = try #require(setup.windows.first { $0.kind == .browser })
        let classes = try #require(element("classList", in: browser.content))
        let selected = await session.uiAction(.select(windowID: browser.id, elementID: classes.id, value: "DefinitionExample"))
        let content = selected.windows.first { $0.id == browser.id }?.content
        let editor = try #require(element("methodEditor", in: content))
        let accept = try #require(element("executeButton", in: content))
        #expect(editor.label == "Class Definition")
        #expect(editor.text == "Object subclass: #DefinitionExample\n    instanceVariableNames: 'count'")
        #expect(!accept.enabled)

        func submit(_ source: String) async -> EvaluationResult {
            _ = await session.uiAction(.text(windowID: browser.id, elementID: editor.id, value: source))
            return await session.uiAction(.click(windowID: browser.id, elementID: accept.id))
        }

        let cycle = await submit("DefinitionChild subclass: #DefinitionExample instanceVariableNames: 'count'")
        let cycleContent = cycle.windows.first { $0.id == browser.id }?.content
        #expect(element("evaluationResult", in: cycleContent)?.text.contains("inherit from itself") == true)
        #expect(cycle.changes.count == setup.changes.count)
        let removal = await submit("Object subclass: #DefinitionExample instanceVariableNames: ''")
        #expect(element("evaluationResult", in: removal.windows.first { $0.id == browser.id }?.content)?.text.contains("still uses instance variable count") == true)
        #expect(removal.changes.count == setup.changes.count)

        let changed = await submit("DefinitionParent subclass: #DefinitionExample instanceVariableNames: 'label count'")
        #expect(changed.error == nil)
        #expect(changed.changes.last?.kind == .classDefinition)
        #expect(changed.classes.first { $0.name == "DefinitionChild" }?.fields == ["inherited", "label", "count", "child"])
        #expect(await session.evaluate("identity == DefinitionExample and: [ live count = 42 ]").value == "true")

        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(session.imageData())
        #expect(await restored.evaluate("live count").value == "42")
        #expect(await restored.evaluate("DefinitionExample superclass name").value == "#DefinitionParent")
        let restoredContent = loaded.evaluation.windows.first { $0.id == browser.id }?.content
        let restoredClasses = try #require(element("classList", in: restoredContent))
        let selectedPrimitive = await restored.uiAction(.select(windowID: browser.id, elementID: restoredClasses.id, value: "Integer"))
        let primitiveSource = element("methodEditor", in: selectedPrimitive.windows.first { $0.id == browser.id }?.content)
        #expect(primitiveSource?.text.contains("Number subclass: #Integer") == true)
        #expect(primitiveSource?.readOnly == true)
    }
}
