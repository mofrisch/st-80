import AppKit
import XCTest

@MainActor
final class Smalltalk80UITests: XCTestCase {
    func testFreshToolsPlaceBrowserLeftAndStackWorkspaceAndTranscriptRight() {
        let app = launchFreshApp()
        let browser = app.windows["toolWindow-2"]
        let workspace = app.windows["toolWindow-1"]
        let transcript = app.windows["toolWindow-3"]
        XCTAssertTrue(browser.waitForExistence(timeout: 10))
        XCTAssertTrue(workspace.waitForExistence(timeout: 10))
        XCTAssertTrue(transcript.waitForExistence(timeout: 10))
        let arrangedPredicate = NSPredicate { _, _ in
            let left = browser.frame
            let upperRight = workspace.frame
            let lowerRight = transcript.frame
            return left.maxX < upperRight.minX && upperRight.maxY < lowerRight.minY
                && abs(left.minY - upperRight.minY) <= 1
                && abs(left.maxY - lowerRight.maxY) <= 1
        }
        let arranged = expectation(for: arrangedPredicate, evaluatedWith: nil)
        wait(for: [arranged], timeout: 10)
        XCTAssertEqual(workspace.frame.minX, transcript.frame.minX, accuracy: 1)
        XCTAssertEqual(workspace.frame.width, transcript.frame.width, accuracy: 1)
        let editor = workspace.textViews["workspaceEditor"]
        XCTAssertTrue(editor.isHittable)
        let initialFrame = workspace.frame
        replaceText(in: editor, with: "Desktop activeWindow moveToX: 100 y: 200")
        workspace.buttons["executeButton"].click()
        let moved = expectation(for: NSPredicate { _, _ in
            abs(workspace.frame.minX - initialFrame.minX) > 10
        }, evaluatedWith: nil)
        wait(for: [moved], timeout: 5)
        app.menuBars.menuBarItems["Smalltalk"].click()
        app.menuItems["Arrange Tools"].click()
        let rearranged = expectation(for: arrangedPredicate, evaluatedWith: nil)
        wait(for: [rearranged], timeout: 10)
        XCTAssertEqual(editor.value as? String, "Desktop activeWindow moveToX: 100 y: 200")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Browser left, workspace and transcript right"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testQuitSavesPendingWorkspaceDraftAndReopensCleanly() throws {
        continueAfterFailure = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("st80-quit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "dev.moritz.Smalltalk80UITests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let app = XCUIApplication()
        app.launchEnvironment["ST80_PREFERENCES_SUITE"] = suite
        app.launch()
        let editor = app.windows["toolWindow-1"].textViews["workspaceEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let initialSource = try XCTUnwrap(editor.value as? String)
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))

        app.launch()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let source = "Do not evaluate this draft"
        replaceText(in: editor, with: source)
        let save = app.buttons["Save"]
        let cancel = app.buttons["Cancel"]
        editor.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        cancel.click()
        XCTAssertTrue(editor.isHittable)
        XCTAssertEqual(editor.value as? String, source)

        editor.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.click()
        let panelSave = app.buttons["OKButton"]
        XCTAssertTrue(panelSave.waitForExistence(timeout: 5))
        cancel.click()
        XCTAssertTrue(editor.isHittable)
        XCTAssertEqual(editor.value as? String, source)

        let image = directory.appendingPathComponent("Smalltalk.stimage")
        let conflictingLog = directory.appendingPathComponent("Smalltalk.changes")
        try Data("another log".utf8).write(to: conflictingLog)
        editor.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.click()
        XCTAssertTrue(panelSave.waitForExistence(timeout: 5))
        navigateFilePanel(in: app, to: directory.path)
        panelSave.click()
        XCTAssertTrue(app.staticTexts["Could not save the image"].waitForExistence(timeout: 5))
        app.buttons["OK"].click()
        XCTAssertTrue(editor.isHittable)
        XCTAssertEqual(editor.value as? String, source)
        XCTAssertFalse(FileManager.default.fileExists(atPath: image.path))
        try FileManager.default.removeItem(at: conflictingLog)

        editor.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.click()
        XCTAssertTrue(panelSave.waitForExistence(timeout: 5))
        navigateFilePanel(in: app, to: directory.path)
        panelSave.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        XCTAssertTrue(FileManager.default.fileExists(atPath: image.path))

        // An earlier version remembered this path in the launch preferences.
        preferences.set(image.path, forKey: "lastImagePath")
        app.launch()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, initialSource)
        openImage(image, in: app)
        let restoredSource = expectation(for: NSPredicate(format: "value == %@", source), evaluatedWith: editor)
        wait(for: [restoredSource], timeout: 10)
        let revisedSource = "Save this to the same image"
        replaceText(in: editor, with: revisedSource)
        editor.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))

        app.launch()
        openImage(image, in: app)
        let restoredRevision = expectation(for: NSPredicate(format: "value == %@", revisedSource), evaluatedWith: editor)
        wait(for: [restoredRevision], timeout: 10)
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    }

    func testBrowserShowsAndAcceptsClassDefinitions() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let workspaceEditor = workspace.textViews["workspaceEditor"]
        XCTAssertTrue(workspaceEditor.waitForExistence(timeout: 10))
        replaceText(in: workspaceEditor, with: "live := Counter new add: 9; yourself. live value")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["9"].waitForExistence(timeout: 5))
        workspaceEditor.typeKey("2", modifierFlags: .command)

        let browser = app.windows["toolWindow-2"]
        let editor = browser.textViews["methodEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        browser.staticTexts["Array"].firstMatch.click()
        XCTAssertEqual(editor.value as? String, "Object subclass: #Array\n    instanceVariableNames: ''")
        browser.staticTexts["Examples"].firstMatch.click()
        let counter = browser.staticTexts["Counter"].firstMatch
        let visibleCounter = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: counter)
        wait(for: [visibleCounter], timeout: 5)
        counter.click()
        let counterDefinition = expectation(for: NSPredicate(format: "value == %@", "Object subclass: #Counter\n    instanceVariableNames: 'count'"), evaluatedWith: editor)
        wait(for: [counterDefinition], timeout: 5)
        browser.staticTexts["value"].firstMatch.click()
        XCTAssertEqual(editor.value as? String, "value ^ count")
        browser.buttons["classDefinition"].click()
        let definition = "Object subclass: #Counter\n    instanceVariableNames: 'count label'"
        replaceText(in: editor, with: definition)
        editor.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(browser.staticTexts["Counter definition accepted."].waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, definition)
        editor.typeKey("1", modifierFlags: .command)
        replaceText(in: workspaceEditor, with: "live value + Counter new value")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["9"].waitForExistence(timeout: 5))
    }

    func testBrowserCreatesAndEditsClassMethodsIndependently() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let workspaceEditor = workspace.textViews["workspaceEditor"]
        XCTAssertTrue(workspaceEditor.waitForExistence(timeout: 10))
        workspaceEditor.typeKey("2", modifierFlags: .command)

        let browser = app.windows["toolWindow-2"]
        XCTAssertTrue(browser.buttons["classMethodSide"].waitForExistence(timeout: 5))
        browser.buttons["classMethodSide"].click()
        browser.buttons["newMethod"].click()
        let source = browser.textViews["methodEditor"]
        replaceText(in: source, with: "value\n    ^ 70")
        source.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(browser.staticTexts["Counter class » value"].firstMatch.waitForExistence(timeout: 5))

        browser.buttons["instanceMethodSide"].click()
        browser.staticTexts["value"].firstMatch.click()
        XCTAssertEqual(source.value as? String, "value ^ count")
        browser.buttons["classMethodSide"].click()
        XCTAssertEqual(source.value as? String, "value\n    ^ 70")
        replaceText(in: source, with: "value\n    ^ 73")
        source.typeKey("s", modifierFlags: .command)
        source.typeKey("1", modifierFlags: .command)
        replaceText(in: workspaceEditor, with: "Counter value + Counter new value")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["73"].waitForExistence(timeout: 5))
    }

    func testBrowserShowsReadOnlyBytecodeAndPreservesSourceDraft() throws {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"].textViews["workspaceEditor"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 10))
        workspace.typeKey("2", modifierFlags: .command)

        let browser = app.windows["toolWindow-2"]
        let source = browser.textViews["methodEditor"]
        let bytecode = browser.textViews["bytecodeEditor"]
        let toggle = browser.buttons["methodBytecodeToggle"]
        let value = browser.staticTexts["value"].firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertFalse(toggle.isEnabled)
        XCTAssertFalse(bytecode.exists)
        value.click()

        let acceptedSource = "value ^ count"
        let originalValue = NSPredicate(format: "value == %@", acceptedSource)
        wait(for: [expectation(for: originalValue, evaluatedWith: source)], timeout: 5)
        let accept = browser.buttons["executeButton"]
        XCTAssertFalse(accept.isEnabled)
        let draft = "value\n    ^ count + 19"
        replaceText(in: source, with: draft)
        XCTAssertEqual(toggle.label, "Bytecode")
        toggle.click()
        let compiledValue = NSPredicate(format: "value CONTAINS %@", "LOAD count")
        wait(for: [expectation(for: compiledValue, evaluatedWith: bytecode)], timeout: 5)
        let listing = try XCTUnwrap(bytecode.value as? String)
        XCTAssertTrue(listing.contains("RETURN_FROM_HOME"), listing)
        XCTAssertFalse(listing.contains("PUSH_LITERAL 19"), listing)
        XCTAssertEqual(source.value as? String, draft)
        XCTAssertLessThanOrEqual(source.frame.maxY, bytecode.frame.minY + 1)
        XCTAssertTrue(accept.isEnabled)
        for heading in ["Class Categories", "Classes", "Protocols", "Methods"] {
            XCTAssertTrue(browser.staticTexts[heading].exists)
        }
        bytecode.click()
        bytecode.typeKey("x", modifierFlags: [])
        XCTAssertEqual(bytecode.value as? String, listing)

        XCTAssertEqual(toggle.label, "Bytecode")
        toggle.click()
        XCTAssertFalse(bytecode.exists)
        XCTAssertEqual(source.value as? String, draft)
        toggle.click()
        source.click()
        source.typeKey("z", modifierFlags: .command)
        wait(for: [expectation(for: originalValue, evaluatedWith: source)], timeout: 5)
        replaceText(in: source, with: draft)
        source.typeKey("s", modifierFlags: .command)
        let acceptedValue = NSPredicate(format: "value CONTAINS %@", "PUSH_LITERAL 19")
        wait(for: [expectation(for: acceptedValue, evaluatedWith: bytecode)], timeout: 5)
        XCTAssertFalse(accept.isEnabled)

        browser.staticTexts["increment"].firstMatch.click()
        let increment = NSPredicate(format: "value CONTAINS %@", "STORE count")
        wait(for: [expectation(for: increment, evaluatedWith: bytecode)], timeout: 5)
        XCTAssertTrue((bytecode.value as? String)?.contains("SEND +") == true)

        let filter = browser.textFields["classFilter"]
        filter.click()
        filter.typeText("Integer")
        let integer = browser.staticTexts["Integer"].firstMatch
        XCTAssertTrue(integer.waitForExistence(timeout: 5))
        integer.click()
        XCTAssertFalse(toggle.isEnabled)
        let addition = browser.staticTexts["+"].firstMatch
        XCTAssertTrue(addition.waitForExistence(timeout: 5))
        addition.click()
        toggle.click()
        let primitive = NSPredicate(format: "value == %@", "This VM primitive has no bytecode.")
        wait(for: [expectation(for: primitive, evaluatedWith: bytecode)], timeout: 5)
    }

    func testBrowserShowsClassCreatedInWorkspace() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let workspaceEditor = workspace.textViews["workspaceEditor"]
        replaceText(in: workspaceEditor, with: "Object subclass: #ClassContextExample instanceVariableNames: 'count'")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["ClassContextExample"].waitForExistence(timeout: 5))
        workspaceEditor.typeKey("2", modifierFlags: .command)

        let browser = app.windows["toolWindow-2"]
        let filter = browser.textFields["classFilter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.click()
        filter.typeText("ClassContextExample")
        let classRow = browser.staticTexts["ClassContextExample"].firstMatch
        XCTAssertTrue(classRow.waitForExistence(timeout: 5))
        classRow.click()

        let definition = NSPredicate(format: "value == %@",
                                     "Object subclass: #ClassContextExample\n    instanceVariableNames: 'count'")
        wait(for: [expectation(for: definition, evaluatedWith: browser.textViews["methodEditor"])], timeout: 5)
        let createClass = NSPredicate(format: "label BEGINSWITH %@", "Create Class")
        XCTAssertFalse(browser.buttons.matching(createClass).firstMatch.exists)
        XCTAssertFalse(browser.staticTexts["Create a Class"].exists)
        classRow.rightClick()
        XCTAssertFalse(app.menuItems.matching(createClass).firstMatch.exists)
    }

    func testBrowserOrganizationMenusCreateCategoriesAndProtocols() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.typeKey("2", modifierFlags: .command)
        let browser = app.windows["toolWindow-2"]
        XCTAssertTrue(browser.waitForExistence(timeout: 5))

        func add(_ menu: String, item: String, named name: String) {
            let actions = browser.descendants(matching: .any).matching(identifier: menu).firstMatch
            XCTAssertTrue(actions.waitForExistence(timeout: 5))
            actions.click()
            let command = app.menuItems[item].firstMatch
            XCTAssertTrue(command.waitForExistence(timeout: 5))
            command.click()
            let field = browser.textFields["organizationName"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.click()
            field.typeText(name)
            browser.buttons["applyOrganizationEdit"].click()
            XCTAssertTrue(browser.staticTexts[name].firstMatch.waitForExistence(timeout: 5))
        }

        add("categoryActions", item: "New Category …", named: "Domain Models")
        browser.staticTexts["Examples"].firstMatch.click()
        browser.staticTexts["Counter"].firstMatch.click()
        add("protocolActions", item: "New Protocol …", named: "Reading")
    }

    func testWorkspaceAndLiveMethodEditing() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 10))
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["5"].waitForExistence(timeout: 5))
        let transcript = app.windows["toolWindow-3"]
        XCTAssertTrue(transcript.staticTexts.containing(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "The counter is at 5", "The counter is at 5")).firstMatch.exists)

        workspace.textViews["workspaceEditor"].typeKey("2", modifierFlags: .command)
        let browser = app.windows["toolWindow-2"]
        XCTAssertTrue(browser.waitForExistence(timeout: 5))
        let panes = ["Class Categories", "Classes", "Protocols", "Methods"].map { browser.staticTexts[$0] }
        for pane in panes { XCTAssertTrue(pane.waitForExistence(timeout: 5)) }
        for (left, right) in zip(panes, panes.dropFirst()) {
            XCTAssertLessThan(left.frame.minX, right.frame.minX)
        }
        browser.staticTexts["Examples"].firstMatch.click()
        browser.staticTexts["Counter"].firstMatch.click()
        browser.staticTexts["Accessing"].firstMatch.click()
        browser.staticTexts["value"].firstMatch.click()
        let method = browser.textViews["methodEditor"]
        XCTAssertTrue(method.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(method.frame.minY, panes[0].frame.maxY)
        replaceText(in: method, with: "value\n    ^ count + 10")
        method.typeKey("s", modifierFlags: .command)
        let editor = workspace.textViews["workspaceEditor"]
        editor.typeKey("1", modifierFlags: .command)
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["15"].waitForExistence(timeout: 5))
    }

    func testDoItEvaluatesOnlySelection() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        replaceText(in: editor, with: "1 / 0.\n6 * 7")
        editor.typeKey(.leftArrow, modifierFlags: [.command, .shift])
        editor.typeKey("d", modifierFlags: .command)
        XCTAssertTrue(workspace.staticTexts["42"].waitForExistence(timeout: 5))
        XCTAssertFalse(workspace.staticTexts["ERROR"].exists)
    }

    func testWorkspaceToolbarGroupsActionsAndFoldsResult() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let browser = app.windows["toolWindow-2"]
        let transcript = app.windows["toolWindow-3"]
        let editor = workspace.textViews["workspaceEditor"]
        let run = workspace.buttons["executeButton"]
        let resultToggle = workspace.buttons["toolResultToggle"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(browser.waitForExistence(timeout: 5))
        XCTAssertEqual(run.label, "Do it")
        XCTAssertFalse(workspace.buttons["saveImageButton"].exists)
        XCTAssertFalse(browser.buttons["saveImageButton"].exists)
        XCTAssertFalse(resultToggle.exists)

        replaceText(in: editor, with: "1 / 0.\n6 * 7")
        editor.typeKey(.leftArrow, modifierFlags: [.command, .shift])
        run.click()
        let result = workspace.staticTexts["42"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(resultToggle.exists)
        resultToggle.click()
        XCTAssertGreaterThan(result.frame.minY, resultToggle.frame.maxY)
        resultToggle.click()
        XCTAssertLessThan(result.frame.minY, resultToggle.frame.maxY)

        let actions = workspace.descendants(matching: .any).matching(identifier: "workspaceActions").firstMatch
        XCTAssertTrue(actions.exists)
        actions.click()
        func menuItem(_ identifier: String, title: String) -> XCUIElement {
            app.menuItems.matching(NSPredicate(format: "identifier == %@ OR label == %@",
                                              "workspaceAction-\(identifier)", title)).firstMatch
        }
        let printIt = menuItem("printIt", title: "Print it")
        XCTAssertTrue(printIt.waitForExistence(timeout: 5))
        XCTAssertEqual(printIt.title, "Print it")
        XCTAssertEqual(menuItem("inspectIt", title: "Inspect it").title, "Inspect it")
        XCTAssertEqual(menuItem("debugIt", title: "Debug it").title, "Debug it")
        XCTAssertFalse(app.menuItems["workspaceAction-doIt"].firstMatch.exists)
        printIt.click()

        let printed = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "→ 42", "→ 42")
        let output = transcript.staticTexts.matching(printed).firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        app.menuBars.menuBarItems["Smalltalk"].click()
        XCTAssertTrue(app.menuItems["Examples"].firstMatch.waitForExistence(timeout: 5))
        app.menuItems["Clear Transcript"].click()
        let cleared = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: output)
        wait(for: [cleared], timeout: 5)

        app.menuBars.menuBarItems["Smalltalk"].click()
        let examples = app.menuItems["Examples"].firstMatch
        examples.hover()
        let counter = app.menuItems["Counter"].firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        counter.click()
        let example = app.windows["toolWindow-4"].textViews["workspaceEditor"]
        let exampleSource = NSPredicate(format: "value CONTAINS %@", "counter := Counter new.")
        wait(for: [expectation(for: exampleSource, evaluatedWith: example)], timeout: 5)
    }

    func testWorkspaceContextMenuUsesTheSelectionForAllThreeActions() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        let selectedSource = "6 * 7"
        let source = "1 / 0.\n" + selectedSource
        replaceText(in: editor, with: source)
        editor.typeKey(.leftArrow, modifierFlags: [.command, .shift])

        // Open the menu away from the selection. Running the entire buffer
        // or evaluating the text under the pointer would miss the result.
        let point = editor.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45))
        func menuItem(_ id: String) -> XCUIElement {
            app.menuItems["editorContext-\(id)"].firstMatch
        }
        func choose(_ id: String, title: String) {
            let command = menuItem(id)
            XCTAssertTrue(command.waitForExistence(timeout: 5), editor.debugDescription)
            XCTAssertEqual(command.title, title)
            XCTAssertTrue(command.isEnabled)
            command.click()
        }

        withPreservedPasteboard { pasteboard in
            pasteboard.clearContents()
            point.rightClick()
            XCTAssertTrue(menuItem("copy").waitForExistence(timeout: 5))
            XCTAssertEqual(menuItem("cut").title, "Cut")
            XCTAssertEqual(menuItem("paste").title, "Paste")
            XCTAssertEqual(menuItem("selectAll").title, "Select All")
            choose("copy", title: "Copy")
            XCTAssertEqual(pasteboard.string(forType: .string), selectedSource)

            editor.typeKey(.rightArrow, modifierFlags: [])
            point.rightClick()
            choose("paste", title: "Paste")
            XCTAssertEqual(editor.value as? String, source + selectedSource)
            editor.typeKey("z", modifierFlags: .command)
            XCTAssertEqual(editor.value as? String, source)
        }

        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeKey(.leftArrow, modifierFlags: [.command, .shift])
        point.rightClick()
        choose("doIt", title: "Do it")
        XCTAssertTrue(workspace.staticTexts["42"].waitForExistence(timeout: 5))
        XCTAssertFalse(workspace.staticTexts["ERROR"].exists)

        XCUIElement.perform(withKeyModifiers: .control) { point.click() }
        choose("printIt", title: "Print it")
        let transcript = app.windows["toolWindow-3"].staticTexts["transcriptOutput"]
        let output = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "→ 42", "→ 42")
        wait(for: [expectation(for: output, evaluatedWith: transcript)], timeout: 5)

        point.rightClick()
        choose("inspectIt", title: "Inspect it")
        let inspector = app.windows["objectInspector"].firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        let summary = inspector.staticTexts["inspectorSummary"]
        let inspected = NSPredicate(format: "label == %@ OR value == %@", "42", "42")
        wait(for: [expectation(for: inspected, evaluatedWith: summary)], timeout: 5)
    }

    func testWorkspaceDebuggerStepsIntoSelectedCodeAndContinues() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        replaceText(in: editor, with: "1 / 0.\nCounter new value + 42")
        editor.typeKey(.leftArrow, modifierFlags: [.command, .shift])

        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45)).rightClick()
        let debug = app.menuItems["editorContext-debugIt"].firstMatch
        XCTAssertTrue(debug.waitForExistence(timeout: 5), editor.debugDescription)
        XCTAssertEqual(debug.title, "Debug it")
        debug.click()

        let debugger = app.windows["debugger"].firstMatch
        XCTAssertTrue(debugger.waitForExistence(timeout: 5))
        let title = debugger.staticTexts["debuggerFrameTitle"]
        let workspaceFrame = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Workspace", "Workspace")
        wait(for: [expectation(for: workspaceFrame, evaluatedWith: title)], timeout: 5)

        let stepInto = debugger.buttons["debuggerStepInto"]
        let location = debugger.staticTexts["debuggerLocation"]
        let instruction = debugger.staticTexts["debuggerInstruction"]
        let initializeFrame = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "initialize", "initialize")
        for _ in 0..<6 where !initializeFrame.evaluate(with: title) {
            let previousLocation = location.label
            let previousInstruction = instruction.label
            stepInto.click()
            let advanced = NSPredicate { _, _ in
                stepInto.isEnabled && (title.label.contains("initialize") ||
                    (title.value as? String)?.contains("initialize") == true ||
                    location.label != previousLocation || instruction.label != previousInstruction)
            }
            wait(for: [expectation(for: advanced, evaluatedWith: nil)], timeout: 5)
        }
        XCTAssertTrue(initializeFrame.evaluate(with: title), debugger.debugDescription)

        debugger.buttons["debuggerContinue"].click()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: debugger)], timeout: 5)
        XCTAssertTrue(workspace.staticTexts["42"].waitForExistence(timeout: 5))
        XCTAssertFalse(workspace.staticTexts["ERROR"].exists)
    }

    func testInspectItUsesSelectionAndNavigatesNestedArray() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        replaceText(in: editor, with: "1 / 0.\n#((1 2) 3)")
        editor.typeKey(.leftArrow, modifierFlags: [.command, .shift])
        editor.typeKey("i", modifierFlags: .command)

        let inspector = app.windows["objectInspector"].firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        let classLabel = inspector.staticTexts["inspectorClass"]
        XCTAssertTrue(classLabel.waitForExistence(timeout: 5))
        func expectClass(_ name: String) -> XCTestExpectation {
            expectation(for: NSPredicate(format: "label == %@ OR value == %@", name, name), evaluatedWith: classLabel)
        }
        wait(for: [expectClass("Array")], timeout: 5)

        let initialAttachment = XCTAttachment(screenshot: inspector.screenshot())
        initialAttachment.name = "Object Inspector at its root"
        initialAttachment.lifetime = .deleteOnSuccess
        add(initialAttachment)
        func row(_ name: String) -> XCUIElement {
            inspector.descendants(matching: .any).matching(identifier: "inspectorRow-\(name)").firstMatch
        }
        let first = row("[1]")
        XCTAssertTrue(first.waitForExistence(timeout: 5), inspector.debugDescription)
        first.click()
        let back = inspector.buttons["inspectorBack"]
        let backEnabled = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: back)
        wait(for: [backEnabled], timeout: 5)
        row("[2]").click()
        let summary = inspector.staticTexts["inspectorSummary"]
        let scalarValue = expectation(for: NSPredicate(format: "label == %@ OR value == %@", "2", "2"),
                                      evaluatedWith: summary)
        wait(for: [expectClass("SmallInteger"), scalarValue], timeout: 5)

        back.click()
        wait(for: [expectClass("Array")], timeout: 5)
        let attachment = XCTAttachment(screenshot: inspector.screenshot())
        attachment.name = "Object Inspector showing a nested array"
        attachment.lifetime = .keepAlways
        add(attachment)
        inspector.buttons[XCUIIdentifierCloseWindow].click()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: inspector)
        wait(for: [closed], timeout: 5)
    }

    func testNativeWorkspacesKeepIndependentBuffersShareObjectsAndCloseSeparately() {
        let app = launchFreshApp()
        let first = app.windows["toolWindow-1"]
        let firstEditor = first.textViews["workspaceEditor"]
        XCTAssertTrue(firstEditor.waitForExistence(timeout: 10))
        let firstSource = "shared := 40. shared"
        replaceText(in: firstEditor, with: firstSource)
        first.buttons["executeButton"].click()
        XCTAssertTrue(first.staticTexts["40"].waitForExistence(timeout: 5))
        firstEditor.typeKey("n", modifierFlags: .command)

        let second = app.windows["toolWindow-4"]
        let secondEditor = second.textViews["workspaceEditor"]
        XCTAssertTrue(secondEditor.waitForExistence(timeout: 5))
        replaceText(in: secondEditor, with: "shared + 2")
        second.buttons["executeButton"].click()
        XCTAssertTrue(second.staticTexts["42"].waitForExistence(timeout: 5))
        XCTAssertEqual(firstEditor.value as? String, firstSource)
        XCTAssertEqual(app.windows.containing(.textView, identifier: "workspaceEditor").count, 2)

        second.buttons[XCUIIdentifierCloseWindow].click()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: second)
        wait(for: [closed], timeout: 5)
        XCTAssertTrue(firstEditor.exists)
        XCTAssertEqual(firstEditor.value as? String, firstSource)
        XCTAssertTrue(app.windows["toolWindow-2"].exists)
        XCTAssertTrue(app.windows["toolWindow-3"].exists)
    }

    func testImageSaveLoadAndRelaunchPreserveLiveSystem() throws {
        continueAfterFailure = false
        let suite = "dev.moritz.Smalltalk80UITests.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("st80-image-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let app = XCUIApplication()
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        let url = directory.appendingPathComponent("Smalltalk.stimage")
        app.launchEnvironment["ST80_PREFERENCES_SUITE"] = suite
        app.launch()
        let first = app.windows["toolWindow-1"]
        let firstEditor = first.textViews["workspaceEditor"]
        XCTAssertTrue(firstEditor.waitForExistence(timeout: 10))
        let source = """
        Counter subclass: #SavedCounter instanceVariableNames: ''.
        SavedCounter compile: 'value ^ super value + 100'.
        persisted := SavedCounter new.
        persisted add: 7.
        Transcript show: 'Image survives restart'; cr.
        ToolVM collectGarbage.
        persisted value
        """
        replaceText(in: firstEditor, with: source)
        first.buttons["executeButton"].click()
        XCTAssertTrue(first.staticTexts["107"].waitForExistence(timeout: 5))
        firstEditor.typeKey("n", modifierFlags: .command)
        let second = app.windows["toolWindow-4"]
        let secondEditor = second.textViews["workspaceEditor"]
        XCTAssertTrue(secondEditor.waitForExistence(timeout: 5))
        // Smalltalk window messages must update the actual native NSWindow;
        // its resulting geometry is then preserved through the image restart.
        let oldFrame = second.frame
        replaceText(in: secondEditor, with: """
        Desktop activeWindow moveToX: 240 y: 300.
        Desktop activeWindow resizeWidth: 790 height: 530
        """)
        second.buttons["executeButton"].click()
        let savedFrame = second.frame
        XCTAssertGreaterThan(
            abs(savedFrame.minX - oldFrame.minX) + abs(savedFrame.minY - oldFrame.minY),
            10,
            "Smalltalk window messages did not move the native window: before \(oldFrame), after \(savedFrame)"
        )
        XCTAssertGreaterThan(savedFrame.width, oldFrame.width + 20)
        replaceText(in: secondEditor, with: "persisted value")

        secondEditor.typeKey("s", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["OKButton"].waitForExistence(timeout: 5))
        navigateFilePanel(in: app, to: directory.path)
        app.buttons["OKButton"].click()
        let saved = expectation(for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: url.path) }, evaluatedWith: nil)
        wait(for: [saved], timeout: 10)

        replaceText(in: firstEditor, with: "persisted add: 50. persisted value")
        first.buttons["executeButton"].click()
        XCTAssertTrue(first.staticTexts["157"].waitForExistence(timeout: 5))
        openImage(url, in: app)
        let restoredSource = expectation(for: NSPredicate(format: "value == %@", source), evaluatedWith: firstEditor)
        wait(for: [restoredSource], timeout: 5)
        XCTAssertEqual(secondEditor.value as? String, "persisted value")

        app.terminate()
        app.launch()
        openImage(url, in: app)
        let reopenedFirst = app.windows["toolWindow-1"].textViews["workspaceEditor"]
        let reopenedSecondWindow = app.windows["toolWindow-4"]
        let reopenedSecond = reopenedSecondWindow.textViews["workspaceEditor"]
        XCTAssertTrue(reopenedFirst.waitForExistence(timeout: 10))
        let reopenedSource = expectation(for: NSPredicate(format: "value == %@", source), evaluatedWith: reopenedFirst)
        wait(for: [reopenedSource], timeout: 5)
        XCTAssertTrue(reopenedSecond.waitForExistence(timeout: 5))
        XCTAssertEqual(reopenedSecond.value as? String, "persisted value")
        XCTAssertEqual(app.windows.containing(.textView, identifier: "workspaceEditor").count, 2)
        XCTAssertEqual(reopenedSecondWindow.frame.minX, savedFrame.minX, accuracy: 3)
        XCTAssertEqual(reopenedSecondWindow.frame.minY, savedFrame.minY, accuracy: 3)
        XCTAssertEqual(reopenedSecondWindow.frame.width, savedFrame.width, accuracy: 3)
        XCTAssertEqual(reopenedSecondWindow.frame.height, savedFrame.height, accuracy: 3)
        let transcript = app.windows["toolWindow-3"]
        XCTAssertTrue(transcript.staticTexts.matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "Image survives restart", "Image survives restart")).firstMatch.exists)
        reopenedSecondWindow.buttons["executeButton"].click()
        XCTAssertTrue(reopenedSecondWindow.staticTexts["107"].waitForExistence(timeout: 5))
        XCTAssertFalse(reopenedSecondWindow.staticTexts["ERROR"].exists)
    }

    func testSmalltalkFormFlushesInputsBeforeClickAndSurvivesImageRelaunch() throws {
        continueAfterFailure = false
        let suite = "dev.moritz.Smalltalk80UITests.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("st80-ui-form-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let app = XCUIApplication()
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        app.launchEnvironment["ST80_PREFERENCES_SUITE"] = suite
        app.launch()
        let editor = app.windows["toolWindow-1"].textViews["workspaceEditor"]
        replaceText(in: editor, with: """
        UIWindow subclass: #FormWindow instanceVariableNames: 'firstName surname greeting'.
        FormWindow compile: 'initialize
            | column row button |
            super initialize.
            self title: ''Smalltalk Form''.
            firstName := UITextField new.
            firstName label: ''First Name''; placeholder: ''Your first name''.
            surname := UITextField new.
            surname label: ''Last Name''; placeholder: ''Your last name''.
            greeting := UILabel new.
            greeting text: ''Ready.''.
            button := UIButton new.
            button title: ''Greet''; action: [ self greet ].
            row := UIRow new.
            row spacing: 12; add: firstName; add: surname.
            column := UIColumn new.
            column padding: 20; spacing: 12.
            column add: row; add: button; add: greeting.
            self content: column'.
        FormWindow compile: 'greet greeting text: ''Hello, '', firstName text, '' '', surname text, ''!'''.
        form := FormWindow new open
        """)
        app.windows["toolWindow-1"].buttons["executeButton"].click()
        let window = app.windows["toolWindow-4"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertEqual(window.title, "Smalltalk Form")
        let first = window.textFields["First Name"]
        let last = window.textFields["Last Name"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(last.exists)
        XCTAssertTrue(first.identifier.hasPrefix("ui-"))
        XCTAssertNotEqual(first.identifier, last.identifier)
        XCTAssertNotEqual(first.identifier, window.buttons["Greet"].identifier)
        XCTAssertLessThan(first.frame.minX, last.frame.minX)
        first.click()
        first.typeText("Moritz")
        last.click()
        last.typeText("Frisch")
        window.buttons["Greet"].click()
        XCTAssertTrue(window.staticTexts["Hello, Moritz Frisch!"].waitForExistence(timeout: 5))

        first.click()
        first.typeKey("a", modifierFlags: .command)
        first.typeText("Ada")
        last.click()
        last.typeKey("a", modifierFlags: .command)
        last.typeText("Lovelace")
        // Save directly from a field, without Return or another button click.
        last.typeKey("s", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["OKButton"].waitForExistence(timeout: 5))
        navigateFilePanel(in: app, to: directory.path)
        app.buttons["OKButton"].click()
        let image = directory.appendingPathComponent("Smalltalk.stimage")
        let saved = expectation(for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: image.path) }, evaluatedWith: nil)
        wait(for: [saved], timeout: 10)

        app.terminate()
        app.launch()
        openImage(image, in: app)
        let restored = app.windows["toolWindow-4"]
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        XCTAssertEqual(restored.textFields["First Name"].value as? String, "Ada")
        XCTAssertEqual(restored.textFields["Last Name"].value as? String, "Lovelace")
        restored.buttons["Greet"].click()
        XCTAssertTrue(restored.staticTexts["Hello, Ada Lovelace!"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: restored.screenshot())
        attachment.name = "Smalltalk form after image relaunch"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Projection errors must not prevent the workspace from flushing edits
        // and evaluating a repair of a malformed UI tree.
        let workspace = app.windows["toolWindow-1"]
        let workspaceEditor = workspace.textViews["workspaceEditor"]
        restored.textFields["First Name"].typeKey("1", modifierFlags: .command)
        replaceText(in: workspaceEditor, with: "broken := UIColumn new. form content: broken. broken add: broken")
        workspace.buttons["executeButton"].click()
        let error = workspace.staticTexts.containing(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Invalid interface", "Invalid interface")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        replaceText(in: workspaceEditor, with: "form content: UILabel new. form content text: 'Layout repaired.'")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(restored.staticTexts["Layout repaired."].waitForExistence(timeout: 5))
    }

    func testMVCModelsRefreshMultipleViewsWhileTypingFromWorkspaceAndAfterImageRelaunch() throws {
        continueAfterFailure = false
        let suite = "dev.moritz.Smalltalk80UITests.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("st80-mvc-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let app = XCUIApplication()
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        app.launchEnvironment["ST80_PREFERENCES_SUITE"] = suite
        app.launch()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Examples/GreetingWindow.st"), encoding: .utf8)
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        replaceText(in: editor, with: source + """
        . greetingView moveToX: 100 y: 1000.
        mirrorView := GreetingView new.
        mirrorView moveToX: 650 y: 1000.
        mirrorView model: greetingModel controller: greetingController; open
        """)
        workspace.buttons["executeButton"].click()
        let first = app.windows["toolWindow-4"]
        let second = app.windows["toolWindow-5"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        let field = first.textFields["Name"]
        field.click()
        field.typeText("Moritz")
        // No Return, focus change or click: the controller updates the model as
        // we type, and both dependent views must react to that model change.
        XCTAssertTrue(second.staticTexts["Hello, Moritz!"].waitForExistence(timeout: 5))
        XCTAssertEqual(second.textFields["Name"].value as? String, "Moritz")
        XCTAssertEqual(field.value as? String, "Moritz")
        field.typeKey(.leftArrow, modifierFlags: .command)
        field.typeText("Dr. ")
        XCTAssertTrue(second.staticTexts["Hello, Dr. Moritz!"].waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Dr. Moritz")

        field.typeKey("1", modifierFlags: .command)
        replaceText(in: editor, with: "greetingModel name: 'Ada'")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(first.staticTexts["Hello, Ada!"].waitForExistence(timeout: 5))
        XCTAssertTrue(second.staticTexts["Hello, Ada!"].exists)
        XCTAssertEqual(field.value as? String, "Ada")
        second.buttons["Clear"].click()
        XCTAssertTrue(first.staticTexts["No greeting yet."].waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "")

        second.textFields["Name"].typeKey("1", modifierFlags: .command)
        replaceText(in: editor, with: "GreetingController compile: 'nameChanged: aString ^ 1 / 0'")
        workspace.buttons["executeButton"].click()
        field.click()
        field.typeText("Recoverable")
        let inputError = first.staticTexts.containing(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Division by zero", "Division by zero")).firstMatch
        XCTAssertTrue(inputError.waitForExistence(timeout: 5))
        field.typeKey("1", modifierFlags: .command)
        replaceText(in: editor, with: "GreetingController compile: 'nameChanged: aString model name: aString'")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(second.staticTexts["Hello, Recoverable!"].waitForExistence(timeout: 5))

        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("Saved")
        field.typeKey("s", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["OKButton"].waitForExistence(timeout: 5))
        navigateFilePanel(in: app, to: directory.path)
        app.buttons["OKButton"].click()
        let image = directory.appendingPathComponent("Smalltalk.stimage")
        let saved = expectation(for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: image.path) }, evaluatedWith: nil)
        wait(for: [saved], timeout: 10)
        app.terminate()
        app.launch()
        openImage(image, in: app)
        let restoredFirst = app.windows["toolWindow-4"]
        let restoredSecond = app.windows["toolWindow-5"]
        XCTAssertTrue(restoredFirst.waitForExistence(timeout: 10))
        XCTAssertEqual(restoredFirst.textFields["Name"].value as? String, "Saved")
        XCTAssertTrue(restoredSecond.staticTexts["Hello, Saved!"].exists)
        restoredSecond.buttons["Use Example Name"].click()
        XCTAssertTrue(restoredFirst.staticTexts["Hello, Moritz!"].waitForExistence(timeout: 5))
        XCTAssertEqual(restoredFirst.textFields["Name"].value as? String, "Moritz")
        let attachment = XCTAttachment(screenshot: restoredFirst.screenshot())
        attachment.name = "MVC view after model change and image relaunch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSmalltalkLimitsAndCloseVetoReachNativeWindows() {
        let app = launchFreshApp()
        let first = app.windows["toolWindow-1"]
        let editor = first.textViews["workspaceEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        replaceText(in: editor, with: """
        SystemWindow compile: 'canClose ^ self title ~= ''Protected'''.
        protected := Desktop openWorkspace.
        protected title: 'Protected'; minimumWidth: 650 height: 420; resizeWidth: 20 height: 20
        """)
        first.buttons["executeButton"].click()
        let window = app.windows["toolWindow-4"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertEqual(window.frame.width, 650, accuracy: 2)
        XCTAssertEqual(window.frame.height, 420, accuracy: 2)
        window.buttons[XCUIIdentifierCloseWindow].click()
        let secondEditor = window.textViews["workspaceEditor"]
        replaceText(in: secondEditor, with: "Desktop windows size")
        window.buttons["executeButton"].click()
        XCTAssertTrue(window.staticTexts["4"].waitForExistence(timeout: 5))
        replaceText(in: secondEditor, with: "protected title: 'Closable'")
        window.buttons["executeButton"].click()
        window.buttons[XCUIIdentifierCloseWindow].click()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: window)
        wait(for: [closed], timeout: 5)
        XCTAssertTrue(first.exists)
        XCTAssertFalse(first.staticTexts["ERROR"].exists)
    }

    func testChangesAfterImageSnapshotSurviveRelaunchAndCanBeRestoredFromTheUI() throws {
        continueAfterFailure = false
        let suite = "dev.moritz.Smalltalk80UITests.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("st80-recovery-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let app = XCUIApplication()
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        app.launchEnvironment["ST80_PREFERENCES_SUITE"] = suite
        app.launch()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.typeKey("s", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["OKButton"].waitForExistence(timeout: 5))
        navigateFilePanel(in: app, to: directory.path)
        app.buttons["OKButton"].click()
        let image = directory.appendingPathComponent("Smalltalk.stimage")
        let saved = expectation(for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: image.path) }, evaluatedWith: nil)
        wait(for: [saved], timeout: 10)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Smalltalk.changes").path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).contains { $0.pathExtension == "sources" })
        replaceText(in: editor, with: "Counter compile: 'recovered ^ 73'")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["#recovered"].waitForExistence(timeout: 5))
        editor.typeKey("q", modifierFlags: .command)
        let discard = app.buttons["Don't Save"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        app.launch()
        openImage(image, in: app)
        let restored = app.windows["toolWindow-1"]
        let restoredEditor = restored.textViews["workspaceEditor"]
        XCTAssertTrue(restoredEditor.waitForExistence(timeout: 10))
        replaceText(in: restoredEditor, with: "Desktop openChanges")
        restored.buttons["executeButton"].click()
        let history = app.windows["toolWindow-4"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        let record = history.staticTexts["Counter » recovered"].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.click()
        XCTAssertTrue(history.staticTexts["After Image Checkpoint"].firstMatch.exists)
        history.buttons["restoreChangeButton"].click()
        XCTAssertTrue(history.staticTexts["Restored: Counter » recovered"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: history.screenshot())
        attachment.name = "Recovered method from the durable changes journal"
        attachment.lifetime = .keepAlways; add(attachment)
        record.typeKey("1", modifierFlags: .command)
        replaceText(in: restoredEditor, with: "Counter new recovered")
        restored.buttons["executeButton"].click()
        XCTAssertTrue(restored.staticTexts["73"].waitForExistence(timeout: 5))
        XCTAssertFalse(restored.staticTexts["ERROR"].exists)
    }

    private func launchFreshApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["ST80_PREFERENCES_SUITE"] = "dev.moritz.Smalltalk80UITests.\(UUID().uuidString)"
        app.launch()
        return app
    }

    private func replaceText(in editor: XCUIElement, with source: String) {
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeKey("a", modifierFlags: .command)
        // XCUI's key synthesis drops a dead-key caret on German keyboards.
        withPreservedPasteboard { pasteboard in
            pasteboard.clearContents()
            pasteboard.setString(source, forType: .string)
            editor.typeKey("v", modifierFlags: .command)
        }
        XCTAssertEqual(editor.value as? String, source)
    }

    private func withPreservedPasteboard(_ action: (NSPasteboard) -> Void) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        defer {
            pasteboard.clearContents()
            if let previous { pasteboard.writeObjects(previous) }
        }
        action(pasteboard)
    }

    private func openImage(_ image: URL, in app: XCUIApplication) {
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: workspace.buttons["executeButton"])
        wait(for: [ready], timeout: 5)
        editor.typeKey("o", modifierFlags: [.command, .shift])
        let open = app.buttons["OKButton"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        navigateFilePanel(in: app, to: image.path)
        open.click()
    }

    private func navigateFilePanel(in app: XCUIApplication, to path: String) {
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(path)
        app.typeKey(.return, modifierFlags: [])
    }
}
