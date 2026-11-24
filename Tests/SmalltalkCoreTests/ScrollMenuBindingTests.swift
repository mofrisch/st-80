import Testing
@testable import SmalltalkCore

struct ScrollMenuBindingTests {
    private func openMenu(in session: SmalltalkSession, subclass: Bool = false) async throws -> EvaluationResult {
        let scrollClass = subclass ? "BoundMenuScroll" : "UIScroll"
        let result = await session.evaluate("""
            Model subclass: #ScrollMenuModel instanceVariableNames: 'title available shown'.
            ScrollMenuModel compile: 'initialize super initialize. title := ''Initial''. available := true. shown := true'.
            ScrollMenuModel compile: 'title ^ title'.
            ScrollMenuModel compile: 'available ^ available'.
            ScrollMenuModel compile: 'shown ^ shown'.
            ScrollMenuModel compile: 'title: text available: enabled shown: visible
                title := text. available := enabled. shown := visible. self changed'.
            UIScroll subclass: #BoundMenuScroll instanceVariableNames: ''.
            menuModel := ScrollMenuModel new.
            menuClicks := 0.
            menuButton := UIButton new identifier: 'boundMenuAction'; action: [ menuClicks := menuClicks + 1 ]; yourself.
            menuButton bind: #title to: menuModel aspect: #title;
                bind: #enabled to: menuModel aspect: #available;
                bind: #visible to: menuModel aspect: #shown.
            menu := UIMenu new add: menuButton; yourself.
            menuScroll := \(scrollClass) new contextMenu: menu; yourself.
            menuWindow := UIWindow new title: 'Bound Scroll Menu'; content: menuScroll; open.
            nil
            """)
        try #require(result.error == nil, "\(result.error ?? "")")
        return result
    }

    private func scroll(in result: EvaluationResult) throws -> UIElementInfo {
        try #require(result.windows.first { $0.title == "Bound Scroll Menu" }?.content)
    }

    private func button(in result: EvaluationResult) throws -> UIElementInfo {
        try #require(scroll(in: result).contextMenuItems?.first { $0.kind == .button })
    }

    @Test(arguments: [false, true])
    func scrollMenuBindingsTrackTitleEnabledAndVisibleIncludingSubclasses(subclass: Bool) async throws {
        let session = SmalltalkSession()
        let opened = try await openMenu(in: session, subclass: subclass)
        #expect(try button(in: opened).text == "Initial")
        #expect(await session.evaluate("menuModel dependents size").value == "3")

        let disabled = await session.evaluate("menuModel title: 'Updated' available: false shown: true")
        try #require(disabled.error == nil)
        let disabledButton = try button(in: disabled)
        #expect(disabledButton.text == "Updated")
        #expect(!disabledButton.enabled)
        let windowID = try #require(disabled.windows.first { $0.title == "Bound Scroll Menu" }?.id)
        _ = await session.uiAction(.click(windowID: windowID, elementID: disabledButton.id))
        #expect(await session.evaluate("menuClicks").value == "0")

        let hidden = await session.evaluate("menuModel title: 'Hidden update' available: true shown: false")
        try #require(hidden.error == nil)
        #expect(try scroll(in: hidden).contextMenuItems?.isEmpty == true)
        #expect(await session.evaluate("menuModel dependents size").value == "3")

        let shown = await session.evaluate("menuModel title: 'Visible again' available: true shown: true")
        try #require(shown.error == nil)
        let shownButton = try button(in: shown)
        #expect(shownButton.text == "Visible again")
        #expect(shownButton.enabled)
        let clicked = await session.uiAction(.click(windowID: windowID, elementID: shownButton.id))
        #expect(clicked.error == nil)
        #expect(await session.evaluate("menuClicks").value == "1")
    }

    @Test func replacingAndRemovingScrollMenusDisconnectsTheirBindings() async throws {
        let session = SmalltalkSession()
        _ = try await openMenu(in: session)
        let replaced = await session.evaluate("""
            replacementButton := UIButton new identifier: 'replacementMenuAction'; yourself.
            replacementButton bind: #title to: menuModel aspect: #title;
                bind: #enabled to: menuModel aspect: #available;
                bind: #visible to: menuModel aspect: #shown.
            replacementMenu := UIMenu new add: replacementButton; yourself.
            menuScroll contextMenu: replacementMenu
            """)
        try #require(replaced.error == nil)
        #expect(try button(in: replaced).accessibilityID == "replacementMenuAction")
        #expect(await session.evaluate("menuModel dependents size").value == "3")

        let changed = await session.evaluate("menuModel title: 'Replacement updated' available: true shown: true")
        #expect(try button(in: changed).text == "Replacement updated")
        #expect(await session.evaluate("menuButton title").value == "'Initial'")

        let removed = await session.evaluate("menuScroll contextMenu: nil")
        try #require(removed.error == nil)
        #expect(try scroll(in: removed).contextMenuItems?.isEmpty == true)
        #expect(await session.evaluate("menuModel dependents size").value == "0")
        _ = await session.evaluate("menuModel title: 'Detached update' available: true shown: true")
        #expect(await session.evaluate("replacementButton title").value == "'Replacement updated'")

        let reattached = await session.evaluate("menuScroll contextMenu: replacementMenu")
        try #require(reattached.error == nil)
        #expect(try button(in: reattached).text == "Detached update")
        #expect(await session.evaluate("menuModel dependents size").value == "3")
    }

    @Test func scrollMenuBindingsDisconnectOnCloseAndReconnectOnReopen() async throws {
        let session = SmalltalkSession()
        let opened = try await openMenu(in: session)
        let windowID = try #require(opened.windows.first { $0.title == "Bound Scroll Menu" }?.id)
        let closed = await session.windowAction(.close(windowID))
        try #require(closed.error == nil)
        #expect(await session.evaluate("menuModel dependents size").value == "0")
        _ = await session.evaluate("menuModel title: 'While closed' available: false shown: true")
        #expect(await session.evaluate("menuButton title").value == "'Initial'")

        let reopened = await session.evaluate("menuWindow open")
        try #require(reopened.error == nil)
        #expect(try button(in: reopened).text == "While closed")
        #expect(try !button(in: reopened).enabled)
        #expect(await session.evaluate("menuModel dependents size").value == "3")
    }

    @Test func scrollMenuBindingsSurviveAnImageRoundTrip() async throws {
        let original = SmalltalkSession()
        _ = try await openMenu(in: original, subclass: true)
        let changed = await original.evaluate("menuModel title: 'Saved title' available: false shown: true")
        try #require(changed.error == nil)
        let data = try await original.imageData()
        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(data)
        try #require(loaded.evaluation.error == nil)
        #expect(try button(in: loaded.evaluation).text == "Saved title")
        #expect(try !button(in: loaded.evaluation).enabled)
        #expect(await restored.evaluate("menuModel dependents size").value == "3")

        let updated = await restored.evaluate("menuModel title: 'After loading' available: true shown: true")
        try #require(updated.error == nil)
        #expect(try button(in: updated).text == "After loading")
        #expect(try button(in: updated).enabled)
    }

    @Test func scrollMenuBindingsWorkAtTheNativeInterfaceElementLimit() async throws {
        let session = SmalltalkSession()
        _ = try await openMenu(in: session)
        let filled = await session.evaluate("""
            menuScroll children: ((Array new: 509) collect: [ :unused | UILabel new ]).
            menuModel title: 'Full interface' available: true shown: true
            """)
        try #require(filled.error == nil, "\(filled.error ?? "")")
        // The scroll, its 509 children, the menu and its button total 512.
        #expect(try scroll(in: filled).children.count == 509)
        #expect(try button(in: filled).text == "Full interface")
        #expect(await session.evaluate("menuModel dependents size").value == "3")
    }
}
