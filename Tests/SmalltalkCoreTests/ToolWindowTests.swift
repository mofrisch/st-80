import Testing
@testable import SmalltalkCore

struct ToolWindowTests {
    private func element(_ id: String, in root: UIElementInfo?) -> UIElementInfo? {
        guard let root else { return nil }
        if root.accessibilityID == id { return root }
        return root.children.lazy.compactMap { element(id, in: $0) }.first
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
        let examples = await select(categories, "Examples")
        #expect(element("classList", in: examples)?.items == ["Counter"])
        let counter = await select(classes, "Counter")
        #expect(element("protocolList", in: counter)?.items == ["All", "Initialization", "Accessing", "Counting"])
        let counting = await select(protocols, "Counting")
        #expect(element("methodList", in: counting)?.items == ["add:", "increment"])
        let increment = await select(methods, "increment")
        #expect(element("methodEditor", in: increment)?.text == "increment count := count + 1")

        _ = await session.uiAction(.text(windowID: browser.id, elementID: editor.id, value: "adjusted: amount ^ count + amount"))
        let accepted = await session.uiAction(.click(windowID: browser.id, elementID: accept.id))
        #expect(accepted.error == nil)
        let content = accepted.windows.first(where: { $0.id == browser.id })?.content
        #expect(element("protocolList", in: content)?.selection == "Counting")
        #expect(element("methodList", in: content)?.items == ["add:", "adjusted:", "increment"])
        #expect(element("methodList", in: content)?.selection == "adjusted:")
    }

    @Test func browserOrganizationEditsSurviveClosingTheBrowserAndLoadingAnImage() async throws {
        let session = SmalltalkSession()
        let snapshot = await session.snapshot()
        let browser = try #require(snapshot.windows.first(where: { $0.kind == .browser }))
        var content = try #require(browser.content)

        func perform(_ identifier: String, _ action: (String) -> UIAction) async throws {
            let control = try #require(element(identifier, in: content))
            let result = await session.uiAction(action(control.id))
            try #require(result.error == nil, "\(identifier): \(result.error ?? "")")
            content = try #require(result.windows.first(where: { $0.id == browser.id })?.content)
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
        let protocolList = element("protocolList", in: accepted.windows.first(where: { $0.id == browser.id })?.content)
        #expect(protocolList?.items == ["All", "Unclassified"])
        #expect(await session.evaluate("ToolExample new answer").value == "73")

        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(session.imageData())
        #expect(element("transcriptOutput", in: loaded.evaluation.windows.first(where: { $0.id == transcript.id })?.content)?.text == "live")
        #expect(element("methodList", in: loaded.evaluation.windows.first(where: { $0.id == browser.id })?.content)?.selection == "answer")
    }
}
