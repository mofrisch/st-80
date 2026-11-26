import AppKit
import XCTest

@MainActor
final class Smalltalk80UITests: XCTestCase {
    func testSettingsMenuAndShortcutOpenOneSmalltalkWindow() throws {
        let app = launchFreshApp(opening: [])
        let menus = app.menuBars.menuBarItems
        XCTAssertTrue(menus["File"].waitForExistence(timeout: 10))
        let topLevelMenus = menus.allElementsBoundByIndex
        let titles = topLevelMenus.map(\.title)
        let fileIndex = try XCTUnwrap(titles.firstIndex(of: "File"), "Menu titles: \(titles)")
        XCTAssertGreaterThan(fileIndex, 0, "Menu titles: \(titles)")
        let appMenu = topLevelMenus[fileIndex - 1]
        appMenu.click()
        let settingsItem = appMenu.menuItems["Settings…"]
        XCTAssertTrue(settingsItem.waitForExistence(timeout: 5))
        settingsItem.click()
        let settings = app.windows.matching(identifier: "settingsWindow")
        let window = settings.firstMatch
        let note = window.staticTexts["settingsImageNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertEqual(note.value as? String ?? note.label, "Windows and session state are stored in the Smalltalk image.")

        app.typeKey(",", modifierFlags: .command)
        XCTAssertEqual(settings.count, 1)
        XCTAssertEqual(app.windows.count, 1)
        window.buttons[XCUIIdentifierCloseWindow].click()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: window)
        wait(for: [closed], timeout: 5)

        openTool("Workspace", in: app)
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        replaceText(in: editor, with: """
        SettingsWindow compile: 'buildContent
            ^ UILabel new identifier: ''customSettingsNote''; text: ''Settings from the live image''; yourself'
        """)
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["#buildContent"].waitForExistence(timeout: 5))
        editor.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(window.staticTexts["customSettingsNote"].waitForExistence(timeout: 5))
        XCTAssertEqual(settings.count, 1)
    }

    func testToolAndCloseKeyboardShortcuts() throws {
        let app = launchFreshApp()
        let originalWorkspace = app.windows["toolWindow-1"]
        let editor = originalWorkspace.textViews["workspaceEditor"]
        editor.click()

        editor.typeKey("w", modifierFlags: .command)
        let newWorkspace = app.windows["toolWindow-2"]
        XCTAssertTrue(newWorkspace.textViews["workspaceEditor"].waitForExistence(timeout: 5))
        XCTAssertTrue(originalWorkspace.exists)

        newWorkspace.textViews["workspaceEditor"].typeKey("b", modifierFlags: .command)
        let browser = app.windows["toolWindow-3"]
        XCTAssertTrue(browser.waitForExistence(timeout: 5))
        XCTAssertEqual(browser.title, "System Browser")

        app.typeKey("t", modifierFlags: .command)
        let transcript = app.windows["toolWindow-4"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 5))
        XCTAssertEqual(transcript.title, "Transcript")
        let frame = transcript.frame
        let primaryScreen = try XCTUnwrap(NSScreen.screens.first)
        XCTAssertEqual(frame.height, 260, accuracy: 2)
        XCTAssertTrue(NSScreen.screens.contains { screen in
            abs(screen.visibleFrame.maxX - frame.maxX - 24) <= 2
                && abs(primaryScreen.frame.maxY - screen.visibleFrame.minY - frame.maxY - 24) <= 2
        }, "Transcript frame: \(frame)")

        app.typeKey("w", modifierFlags: [.command, .shift])
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: transcript)
        wait(for: [closed], timeout: 5)
        XCTAssertTrue(browser.exists && newWorkspace.exists && originalWorkspace.exists)
    }

    func testToolMenuUsesTheTitleAndShortcutEditedInSmalltalk() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        replaceText(in: editor, with: """
        ApplicationMenu compileClass: 'toolsMenu
            ^ UIMenu new title: ''Utilities'';
                add: (self command: #transcript title: ''Show Log'' shortcut: ''⌥⌘L''); yourself'.
        #menuUpdated
        """)
        workspace.buttons["executeButton"].click()
        let utilities = app.menuBars.menuBarItems["Utilities"]
        XCTAssertTrue(utilities.waitForExistence(timeout: 5))
        utilities.click()
        XCTAssertTrue(utilities.menuItems["Show Log"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        editor.typeKey("l", modifierFlags: [.command, .option])
        let transcript = app.windows["toolWindow-2"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 5))
        XCTAssertEqual(transcript.title, "Transcript")
    }

    func testOpeningWorkspaceAtTheWindowLimitReportsFailureAndPreservesTheDraft() {
        let app = launchFreshApp()
        defer { app.terminate() }
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        // Fill the actual desktop limit with lightweight, minimized windows.
        // Their models need no editor trees or extra visible native content.
        replaceText(in: editor, with: """
        capacityWindows := Array new: 128.
        capacityWindows at: 1 put: (Desktop windowAt: 1).
        2 to: 128 do: [ :index |
            capacityWindows at: index put: (SystemWindow new id: index; minimized: true; yourself) ].
        Desktop model windows: capacityWindows.
        Desktop model nextID: 129.
        Desktop windows size
        """)
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["128"].waitForExistence(timeout: 10))
        let draft = "'Keep this existing workspace draft'"
        replaceText(in: editor, with: draft)
        openTool("Workspace", in: app)

        let message = "The desktop is limited to 128 windows."
        let failure = workspace.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", message, message)).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 5), workspace.debugDescription)
        XCTAssertEqual(editor.value as? String, draft)
        XCTAssertTrue(editor.isHittable)
        XCTAssertFalse(app.windows["toolWindow-129"].exists)
    }

    func testWindowToolbarResizesForChangedLabelsAndControls() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        let execute = workspace.buttons["executeButton"]
        XCTAssertTrue(execute.waitForExistence(timeout: 10))
        let initialWidth = execute.frame.width
        let longTitle = "Evaluate the selected Smalltalk source"
        // AppKit's accessibility button bounds can include a border just beyond
        // the hosting view's correctly fitted frame, including pixel rounding.
        let titlebarFrameTolerance: CGFloat = 2
        replaceText(in: editor, with: """
        toolbarProbe := ((Desktop windowAt: 1) content children at: 1).
        executeProbe := toolbarProbe children at: 1.
        executeProbe title: '\(longTitle)'
        """)
        editor.typeKey("d", modifierFlags: .command)
        let actions = workspace.descendants(matching: .any).matching(identifier: "workspaceActions").firstMatch

        func checkToolbar(_ predicate: NSPredicate, object: Any? = nil, phase: String) -> Bool {
            let expected = XCTNSPredicateExpectation(predicate: predicate, object: object)
            let completed = XCTWaiter.wait(for: [expected], timeout: 5) == .completed
            XCTAssertTrue(completed, """
                Toolbar \(phase): label=\(execute.label), frame=\(execute.frame), initialWidth=\(initialWidth), hittable=\(execute.isHittable).
                Actions exists=\(actions.exists), frame=\(actions.exists ? actions.frame : .zero). Workspace frame=\(workspace.frame).
                Editor=\(editor.value as? String ?? "<missing>")
                \(workspace.debugDescription)
                """)
            return completed
        }
        guard checkToolbar(NSPredicate(format: "label == %@", longTitle), object: execute, phase: "label update") else { return }
        guard checkToolbar(NSPredicate { _, _ in
            execute.frame.width > initialWidth + 80
                && execute.isHittable && actions.isHittable
                && actions.frame.maxX <= workspace.frame.maxX + titlebarFrameTolerance
        }, phase: "expansion") else { return }

        replaceText(in: editor, with: """
        executeProbe title: 'Run'.
        toolbarProbe removeAll; add: executeProbe;
            add: (UIButton new identifier: 'extraToolbarAction'; title: 'Additional toolbar action';
                action: [ executeProbe title: 'Toolbar action fired' ]; yourself)
        """)
        editor.typeKey("d", modifierFlags: .command)
        let extra = workspace.buttons["extraToolbarAction"]
        guard checkToolbar(NSPredicate { _, _ in
            extra.exists && extra.isHittable && extra.frame.maxX <= workspace.frame.maxX + titlebarFrameTolerance
        }, phase: "added control") else { return }
        XCTAssertFalse(actions.exists)
        extra.click()
        let clicked = expectation(for: NSPredicate(format: "label == %@", "Toolbar action fired"), evaluatedWith: execute)
        wait(for: [clicked], timeout: 5)

        replaceText(in: editor, with: "toolbarProbe removeAll; add: executeProbe. executeProbe title: 'Run'")
        editor.typeKey("d", modifierFlags: .command)
        guard checkToolbar(NSPredicate { _, _ in
            execute.label == "Run" && !extra.exists && execute.isHittable
                && execute.frame.width < initialWidth + 20
                && workspace.frame.maxX - execute.frame.maxX < 60
        }, phase: "contraction") else { return }
    }

    func testOpeningWorkspaceCreatesARepairEditorWhenAllWorkspacesWereClosed() {
        let app = launchFreshApp(opening: ["Workspace", "Browser"])
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        replaceText(in: editor, with: """
        heldBrowserContent := (Desktop windowAt: 2) content.
        UIWindow new content: (UIButton new identifier: 'breakBrowser'; title: 'Break Browser';
            action: [ (Desktop windowAt: 2) content: 7 ]; yourself); open
        """)
        workspace.buttons["executeButton"].click()
        let custom = app.windows["toolWindow-3"]
        XCTAssertTrue(custom.buttons["breakBrowser"].waitForExistence(timeout: 5))
        focusWindow("Workspace", in: app)
        workspace.buttons[XCUIIdentifierCloseWindow].click()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: workspace)
        wait(for: [closed], timeout: 5)
        custom.buttons["breakBrowser"].click()
        let failure = custom.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Invalid interface.", "Invalid interface.")).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        openTool("Workspace", in: app)
        let repair = app.windows["toolWindow-4"]
        let repairEditor = repair.textViews["workspaceEditor"]
        XCTAssertTrue(repairEditor.waitForExistence(timeout: 5))
        XCTAssertTrue(repairEditor.isHittable)
        replaceText(in: repairEditor, with: "(Desktop windowAt: 2) content: heldBrowserContent. 42")
        repair.buttons["executeButton"].click()
        XCTAssertTrue(repair.staticTexts["42"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.windows["toolWindow-2"].textViews["methodEditor"].exists)
    }

    func testWorkspaceRepairsAnInvalidDesktopWithoutLosingItsEditorOrDraft() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        let damage = "heldWindows := Desktop windows. Desktop model windows: nil"
        replaceText(in: editor, with: damage)
        workspace.buttons["executeButton"].click()
        let message = "Desktop has no valid window list."
        let failure = workspace.staticTexts["toolWindowError"]
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        XCTAssertTrue((failure.value as? String ?? failure.label).contains(message))
        XCTAssertTrue(editor.isHittable)
        XCTAssertEqual(editor.value as? String, damage)
        XCTAssertTrue(workspace.buttons["executeButton"].isEnabled)

        // Evaluate while the model remains broken, then repair it using the
        // same retained editor and its native command shortcut.
        replaceText(in: editor, with: "1 + 2")
        editor.typeKey("d", modifierFlags: .command)
        let preview = workspace.staticTexts["workspaceRecoveryResult"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertEqual(preview.value as? String ?? preview.label, "3")
        XCTAssertTrue(failure.exists)
        openTool("Workspace", in: app)
        XCTAssertTrue(editor.isHittable)
        XCTAssertEqual(editor.value as? String, "1 + 2")
        XCTAssertEqual(app.windows.containing(.textView, identifier: "workspaceEditor").count, 1)

        let repair = "Desktop model windows: heldWindows. 6 * 7"
        replaceText(in: editor, with: repair)
        editor.typeKey("d", modifierFlags: .command)
        XCTAssertTrue(workspace.staticTexts["42"].waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, repair)
        XCTAssertFalse(failure.exists)
        XCTAssertFalse(preview.exists)

        replaceText(in: editor, with: "20 + 22")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["42"].waitForExistence(timeout: 5))
    }

    func testWorkspaceRepairsItsInvalidContentAndResumesNormalCommands() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        let damage = "heldContent := (Desktop windowAt: 1) content. (Desktop windowAt: 1) content: 7"
        replaceText(in: editor, with: damage)
        workspace.buttons["executeButton"].click()
        let message = "Invalid interface."
        let failure = workspace.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", message, message)).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        XCTAssertTrue(editor.isHittable)
        XCTAssertEqual(editor.value as? String, damage)
        let repair = "(Desktop windowAt: 1) content: heldContent. 40 + 2"
        replaceText(in: editor, with: repair)
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["42"].waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, repair)
        XCTAssertFalse(failure.exists)
        openTool("Workspace", in: app)
        XCTAssertTrue(app.windows["toolWindow-2"].textViews["workspaceEditor"].waitForExistence(timeout: 5))
    }

    func testFreshDesktopRestoresIndependentWorkspacesAndBrowsersAndOneTranscript() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = launchFreshApp(opening: [])
        defer { app.terminate() }
        assertDesktopEmpty(in: app)

        openTool("Workspace", in: app)
        let firstWorkspace = app.windows["toolWindow-1"]
        let firstEditor = firstWorkspace.textViews["workspaceEditor"]
        XCTAssertTrue(firstEditor.waitForExistence(timeout: 5))
        let starterSource = "Transcript show: 'Hello'; cr."
        XCTAssertEqual(firstEditor.value as? String, starterSource)

        let fileMenu = app.menuBars.menuBarItems["File"]
        fileMenu.click()
        XCTAssertFalse(fileMenu.menuItems.allElementsBoundByIndex.contains { $0.title.contains("Workspace") })
        app.typeKey(.escape, modifierFlags: [])

        openTool("Transcript", in: app)
        let transcript = app.windows["toolWindow-2"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 5))
        let output = transcript.staticTexts["transcriptOutput"]
        if output.exists {
            XCTAssertEqual(output.value as? String ?? output.label, "")
        }
        focusWindow("Workspace", in: app)
        firstWorkspace.buttons["executeButton"].click()
        let hello = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Hello", "Hello")
        wait(for: [expectation(for: hello, evaluatedWith: output)], timeout: 5)
        let firstSource = "shared := 40"
        replaceText(in: firstEditor, with: firstSource)
        firstWorkspace.buttons["executeButton"].click()
        XCTAssertTrue(firstWorkspace.staticTexts["40"].waitForExistence(timeout: 5))

        openTool("Workspace", in: app)
        let secondWorkspace = app.windows["toolWindow-3"]
        let secondEditor = secondWorkspace.textViews["workspaceEditor"]
        XCTAssertTrue(secondEditor.waitForExistence(timeout: 5))
        XCTAssertEqual(secondEditor.value as? String, starterSource)
        XCTAssertNotEqual(firstWorkspace.frame, secondWorkspace.frame)
        replaceText(in: secondEditor, with: "shared + 2")
        secondWorkspace.buttons["executeButton"].click()
        XCTAssertTrue(secondWorkspace.staticTexts["42"].waitForExistence(timeout: 5))
        let secondSource = "'Ein unabhängiger Entwurf 👋'"
        replaceText(in: secondEditor, with: secondSource)

        openTool("Browser", in: app)
        let firstBrowser = app.windows["toolWindow-4"]
        let valueMethod = firstBrowser.staticTexts["value"].firstMatch
        XCTAssertTrue(valueMethod.waitForExistence(timeout: 5))
        valueMethod.click()
        let firstBrowserEditor = firstBrowser.textViews["methodEditor"]
        let valueSource = "value\n    ^ count"
        let selectedValue = expectation(for: NSPredicate(format: "value == %@", valueSource), evaluatedWith: firstBrowserEditor)
        wait(for: [selectedValue], timeout: 5)

        openTool("Browser", in: app)
        let secondBrowser = app.windows["toolWindow-5"]
        let increment = secondBrowser.staticTexts["increment"].firstMatch
        XCTAssertTrue(increment.waitForExistence(timeout: 5))
        XCTAssertNotEqual(firstBrowser.frame, secondBrowser.frame)
        increment.click()
        let secondBrowserEditor = secondBrowser.textViews["methodEditor"]
        let selectedIncrement = expectation(for: NSPredicate(format: "value BEGINSWITH %@", "increment\n"), evaluatedWith: secondBrowserEditor)
        wait(for: [selectedIncrement], timeout: 5)
        let incrementSource = try XCTUnwrap(secondBrowserEditor.value as? String)

        fileMenu.click()
        XCTAssertTrue(fileMenu.menuItems["Accept"].exists)
        app.typeKey(.escape, modifierFlags: [])
        openTool("Transcript", in: app)
        fileMenu.click()
        XCTAssertFalse(fileMenu.menuItems["Accept"].exists)
        app.typeKey(.escape, modifierFlags: [])
        func assertToolState() {
            XCTAssertEqual(app.windows.count, 5)
            XCTAssertEqual(firstEditor.value as? String, firstSource)
            XCTAssertEqual(secondEditor.value as? String, secondSource)
            XCTAssertEqual(firstBrowserEditor.value as? String, valueSource)
            XCTAssertEqual(secondBrowserEditor.value as? String, incrementSource)
            XCTAssertTrue((output.value as? String ?? output.label).contains("Hello"))
        }
        assertToolState()

        openTool("Workspace", in: app)
        let temporaryWorkspace = app.windows["toolWindow-6"]
        XCTAssertTrue(temporaryWorkspace.textViews["workspaceEditor"].waitForExistence(timeout: 5))
        temporaryWorkspace.buttons[XCUIIdentifierCloseWindow].click()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: temporaryWorkspace)
        wait(for: [closed], timeout: 5)
        assertToolState()
        saveImage(in: app, editor: app, directory: directory)

        app.terminate()
        app.launch()
        assertDesktopEmpty(in: app)
        openImage(directory.appendingPathComponent("Smalltalk.stimage"), in: app)
        XCTAssertTrue(output.waitForExistence(timeout: 10))
        assertToolState()
        XCTAssertFalse(temporaryWorkspace.exists)

        requestReset(in: app)
        assertDesktopEmpty(in: app)
    }

    func testArrangeToolsPlacesBrowserLeftAndStacksWorkspaceAndTranscriptRight() {
        let app = launchFreshApp(opening: [])
        openAndArrangeStandardTools(in: app)
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

    func testResetProtectsPendingDraftThroughCancelSaveFailureAndSuccessfulSave() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        replaceText(in: editor, with: "kept := 42. kept")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["42"].waitForExistence(timeout: 5))
        let draft = "kept + 1"
        replaceText(in: editor, with: draft)

        requestReset(in: app)
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].click()
        XCTAssertTrue(editor.isHittable)
        XCTAssertEqual(editor.value as? String, draft)

        requestReset(in: app)
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        app.buttons["Save"].click()
        XCTAssertTrue(app.buttons["OKButton"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].click()
        XCTAssertTrue(editor.isHittable)
        XCTAssertEqual(editor.value as? String, draft)

        let image = directory.appendingPathComponent("Smalltalk.stimage")
        let conflictingLog = directory.appendingPathComponent("Smalltalk.changes")
        try Data("another session's journal".utf8).write(to: conflictingLog)
        requestReset(in: app)
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        app.buttons["Save"].click()
        XCTAssertTrue(app.buttons["OKButton"].waitForExistence(timeout: 5))
        navigateFilePanel(in: app, to: directory.path)
        app.buttons["OKButton"].click()
        XCTAssertTrue(app.staticTexts["Could not save the image"].waitForExistence(timeout: 5))
        app.buttons["OK"].click()
        XCTAssertEqual(editor.value as? String, draft)
        XCTAssertFalse(FileManager.default.fileExists(atPath: image.path))
        try FileManager.default.removeItem(at: conflictingLog)

        requestReset(in: app)
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        app.buttons["Save"].click()
        XCTAssertTrue(app.buttons["OKButton"].waitForExistence(timeout: 5))
        navigateFilePanel(in: app, to: directory.path)
        app.buttons["OKButton"].click()
        assertDesktopEmpty(in: app)
        XCTAssertTrue(FileManager.default.fileExists(atPath: image.path))

        openImage(image, in: app)
        let restored = expectation(for: NSPredicate(format: "value == %@", draft), evaluatedWith: editor)
        wait(for: [restored], timeout: 10)
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["43"].waitForExistence(timeout: 5))
    }

    func testImageSwitchCanCancelSaveAndDiscardTheCurrentSession() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceDirectory = directory.appendingPathComponent("Source")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("Smalltalk.stimage")
        let source = sourceDirectory.appendingPathComponent("Smalltalk.stimage")
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        replaceText(in: editor, with: "switchValue := 7. switchValue")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["7"].waitForExistence(timeout: 5))
        saveImage(in: app, editor: editor, directory: directory)
        editor.typeKey("s", modifierFlags: [.command, .option, .shift])
        XCTAssertTrue(app.buttons["OKButton"].waitForExistence(timeout: 5))
        navigateFilePanel(in: app, to: sourceDirectory.path)
        app.buttons["OKButton"].click()
        let saved = expectation(for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: source.path) }, evaluatedWith: nil)
        wait(for: [saved], timeout: 10)
        replaceText(in: editor, with: "switchValue := 42. switchValue")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["42"].waitForExistence(timeout: 5))
        let draft = "switchValue + 1"
        replaceText(in: editor, with: draft)

        openImage(target, in: app, decision: nil)
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].click()
        XCTAssertEqual(editor.value as? String, draft)
        XCTAssertTrue(editor.isHittable)

        openImage(target, in: app, decision: "Save")
        let targetSource = expectation(for: NSPredicate(format: "value == %@", "switchValue := 7. switchValue"), evaluatedWith: editor)
        wait(for: [targetSource], timeout: 10)
        replaceText(in: editor, with: "switchValue")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["7"].waitForExistence(timeout: 5))

        openImage(source, in: app)
        let savedDraft = expectation(for: NSPredicate(format: "value == %@", draft), evaluatedWith: editor)
        wait(for: [savedDraft], timeout: 10)
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["43"].waitForExistence(timeout: 5))
        replaceText(in: editor, with: "switchValue := 99. switchValue")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["99"].waitForExistence(timeout: 5))
        openImage(target, in: app)
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "switchValue := 7. switchValue"), evaluatedWith: editor)], timeout: 10)
        openImage(source, in: app)
        wait(for: [expectation(for: NSPredicate(format: "value == %@", draft), evaluatedWith: editor)], timeout: 10)
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["43"].waitForExistence(timeout: 5))
    }

    func testResetJournalFailureKeepsTheLiveWorldAndReportsTheFailure() throws {
        continueAfterFailure = false
        let suite = "dev.moritz.Smalltalk80UITests.\(UUID().uuidString)"
        let logs = FileManager.default.temporaryDirectory.appendingPathComponent("st80-changes-" + suite)
        let app = XCUIApplication()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: logs.path)
            app.terminate()
            try? FileManager.default.removeItem(at: logs)
        }
        app.launchEnvironment["ST80_PREFERENCES_SUITE"] = suite
        app.launchEnvironment["ST80_CHANGES_DIRECTORY"] = logs.path
        app.launch()
        openTool("Workspace", in: app)
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        replaceText(in: editor, with: "kept := 42. kept")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["42"].waitForExistence(timeout: 5))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: logs.path)

        requestReset(in: app)
        XCTAssertTrue(app.buttons["Don't Save"].waitForExistence(timeout: 5))
        app.buttons["Don't Save"].click()
        let failure = workspace.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Could not reset the session", "Could not reset the session")).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 5), workspace.debugDescription)
        XCTAssertEqual(editor.value as? String, "kept := 42. kept")
        replaceText(in: editor, with: "kept + 1")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["43"].waitForExistence(timeout: 5))
        XCTAssertTrue(failure.exists)
    }

    func testJournalFailureStaysVisibleAcrossEvaluationAndResetCanRecover() throws {
        continueAfterFailure = false
        let suite = "dev.moritz.Smalltalk80UITests.\(UUID().uuidString)"
        let logs = FileManager.default.temporaryDirectory.appendingPathComponent("st80-changes-" + suite)
        try Data("blocked journal directory".utf8).write(to: logs)
        let app = XCUIApplication()
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: logs)
        }
        app.launchEnvironment["ST80_PREFERENCES_SUITE"] = suite
        app.launchEnvironment["ST80_CHANGES_DIRECTORY"] = logs.path
        app.launch()
        openTool("Workspace", in: app)
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        let message = "Changes cannot be recorded on disk"
        let failure = workspace.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", message, message)).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 10))
        replaceText(in: editor, with: "Counter compile: 'answer ^ 42'. Counter new answer")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["42"].waitForExistence(timeout: 5))
        XCTAssertTrue(failure.exists)

        try FileManager.default.removeItem(at: logs)
        requestReset(in: app)
        XCTAssertTrue(app.buttons["Don't Save"].waitForExistence(timeout: 5))
        app.buttons["Don't Save"].click()
        assertDesktopEmpty(in: app)
        openTool("Workspace", in: app)
        replaceText(in: editor, with: "Counter compile: 'answer ^ 43'. Counter new answer")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["43"].waitForExistence(timeout: 5))
        let files = try FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.filter { $0.pathExtension == "changes" }.count, 1)
        XCTAssertFalse(failure.exists)
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
        assertDesktopEmpty(in: app)
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))

        app.launch()
        openTool("Workspace", in: app)
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
        assertDesktopEmpty(in: app)
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
        let app = launchFreshApp(opening: ["Workspace", "Browser"])
        let workspace = app.windows["toolWindow-1"]
        let workspaceEditor = workspace.textViews["workspaceEditor"]
        XCTAssertTrue(workspaceEditor.waitForExistence(timeout: 10))
        replaceText(in: workspaceEditor, with: "live := Counter new add: 9; yourself. live value")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["9"].waitForExistence(timeout: 5))
        focusWindow("System Browser", in: app)

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
        XCTAssertEqual(editor.value as? String, "value\n    ^ count")
        browser.buttons["classDefinition"].click()
        let definition = "Object subclass: #Counter\n    instanceVariableNames: 'count label'"
        replaceText(in: editor, with: definition)
        editor.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(browser.staticTexts["Counter definition accepted."].waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, definition)
        focusWindow("Workspace", in: app)
        replaceText(in: workspaceEditor, with: "live value + Counter new value")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["9"].waitForExistence(timeout: 5))
    }

    func testBrowserCreatesAndEditsClassMethodsIndependently() {
        let app = launchFreshApp(opening: ["Workspace", "Browser"])
        let workspace = app.windows["toolWindow-1"]
        let workspaceEditor = workspace.textViews["workspaceEditor"]
        XCTAssertTrue(workspaceEditor.waitForExistence(timeout: 10))
        focusWindow("System Browser", in: app)

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
        XCTAssertEqual(source.value as? String, "value\n    ^ count")
        browser.buttons["classMethodSide"].click()
        XCTAssertEqual(source.value as? String, "value\n    ^ 70")
        replaceText(in: source, with: "value\n    ^ 73")
        source.typeKey("s", modifierFlags: .command)
        focusWindow("Workspace", in: app)
        replaceText(in: workspaceEditor, with: "Counter value + Counter new value")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["73"].waitForExistence(timeout: 5))
    }

    func testBrowserShowsReadOnlyBytecodeAndPreservesSourceDraft() throws {
        let app = launchFreshApp(opening: ["Browser"])
        let browser = app.windows["toolWindow-1"]
        let source = browser.textViews["methodEditor"]
        let bytecode = browser.textViews["bytecodeEditor"]
        let toggle = browser.buttons["methodBytecodeToggle"]
        let value = browser.staticTexts["value"].firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertFalse(toggle.isEnabled)
        XCTAssertFalse(bytecode.exists)
        value.click()

        let acceptedSource = "value\n    ^ count"
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
        pasteText("x", into: bytecode)
        XCTAssertEqual(bytecode.value as? String, listing)

        XCTAssertEqual(toggle.label, "Bytecode")
        toggle.click()
        XCTAssertFalse(bytecode.exists)
        XCTAssertEqual(source.value as? String, draft)
        toggle.click()
        source.click()
        source.typeKey("z", modifierFlags: .command)
        wait(for: [expectation(for: originalValue, evaluatedWith: source)], timeout: 5)

        let rejected = "value\n    ^ ("
        replaceText(in: source, with: rejected)
        source.typeKey("s", modifierFlags: .command)
        let rejectedResult = expectation(for: NSPredicate(format: "label == %@", "Error"),
                                         evaluatedWith: browser.buttons["toolResultToggle"])
        wait(for: [rejectedResult], timeout: 5)
        XCTAssertTrue(accept.isEnabled)
        XCTAssertEqual(source.value as? String, rejected)
        XCTAssertEqual(bytecode.value as? String, listing)

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
        pasteText("Integer", into: filter)
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
        let app = launchFreshApp(opening: ["Workspace", "Browser"])
        let workspace = app.windows["toolWindow-1"]
        let workspaceEditor = workspace.textViews["workspaceEditor"]
        replaceText(in: workspaceEditor, with: "Object subclass: #ClassContextExample instanceVariableNames: 'count'")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["ClassContextExample"].waitForExistence(timeout: 5))
        focusWindow("System Browser", in: app)

        let browser = app.windows["toolWindow-2"]
        let filter = browser.textFields["classFilter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.click()
        pasteText("ClassContextExample", into: filter)
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

    func testBrowserVerticalSplitResizesNavigationAndSource() {
        let app = launchFreshApp(opening: ["Browser"])
        let browser = app.windows["toolWindow-1"]
        browser.staticTexts["Compiler"].firstMatch.click()
        XCTAssertTrue(browser.staticTexts["STCompiler"].firstMatch.waitForExistence(timeout: 5))
        let editor = browser.textViews["methodEditor"]
        let dividers = browser.splitters.allElementsBoundByIndex.filter { $0.frame.width > $0.frame.height }
        guard dividers.count == 1, let divider = dividers.first else {
            return XCTFail("Expected one splitter between the Browser navigation and source panes.")
        }

        let initialPosition = divider.frame.midY
        let initialEditorHeight = editor.frame.height
        let center = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.click(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: 0, dy: -60)))
        let raisedPosition = divider.frame.midY
        XCTAssertGreaterThan(initialPosition - raisedPosition, 45)
        XCTAssertGreaterThan(editor.frame.height - initialEditorHeight, 45)

        browser.staticTexts["Collections & Text"].firstMatch.click()
        XCTAssertTrue(browser.staticTexts["Array"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(divider.frame.midY, raisedPosition, accuracy: 1)

        let start = center.withOffset(CGVector(dx: 0, dy: 6))
        let end = center.withOffset(CGVector(dx: 0, dy: 116))
        start.click(forDuration: 0.1, thenDragTo: end)
        XCTAssertGreaterThan(divider.frame.midY - initialPosition, 30)
        XCTAssertGreaterThan(initialEditorHeight - editor.frame.height, 30)
        XCTAssertTrue(editor.isHittable)
    }

    func testBrowserOrganizationMenusCreateCategoriesAndProtocols() {
        let app = launchFreshApp(opening: ["Browser"])
        let browser = app.windows["toolWindow-1"]
        XCTAssertTrue(browser.waitForExistence(timeout: 5))

        browser.staticTexts["Compiler"].firstMatch.click()
        XCTAssertTrue(browser.staticTexts["STCompiler"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(browser.staticTexts["STSourceScanner"].exists)
        browser.staticTexts["MVC"].firstMatch.click()
        XCTAssertTrue(browser.staticTexts["UIBinding"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(browser.staticTexts["STCompiler"].exists)

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
            pasteText(name, into: field)
            browser.buttons["applyOrganizationEdit"].click()
            XCTAssertTrue(browser.staticTexts[name].firstMatch.waitForExistence(timeout: 5))
        }

        add("categoryActions", item: "New Category …", named: "Domain Models")
        browser.staticTexts["Examples"].firstMatch.click()
        browser.staticTexts["Counter"].firstMatch.click()
        add("protocolActions", item: "New Protocol …", named: "Reading")
    }

    func testWorkspaceAndLiveMethodEditing() {
        let app = launchFreshApp(opening: ["Workspace", "Browser"])
        let workspace = app.windows["toolWindow-1"]
        let workspaceEditor = workspace.textViews["workspaceEditor"]
        replaceText(in: workspaceEditor, with: "counter := Counter new add: 5; yourself. counter value")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["5"].waitForExistence(timeout: 5))

        focusWindow("System Browser", in: app)
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
        focusWindow("Workspace", in: app)
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

    func testWorkspaceBudgetAndStopApplyToOneDoIt() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        let run = workspace.buttons["executeButton"]
        let stop = workspace.buttons["workspaceStop"]
        let budget = workspace.descendants(matching: .any).matching(identifier: "workspaceBudgets").firstMatch
        func runWithBudget(_ title: String) {
            XCTAssertTrue(budget.waitForExistence(timeout: 5))
            budget.click()
            app.menuItems[title].firstMatch.click()
        }

        replaceText(in: editor, with: "| sum | sum := 0. 1 to: 20000 do: [ :i | sum := sum + i ]. sum")
        runWithBudget("1,000,000 steps")
        XCTAssertTrue(workspace.staticTexts["200010000"].waitForExistence(timeout: 8))
        run.click()
        let error = workspace.staticTexts["toolWindowError"]
        func waitForError(containing text: String) {
            let content = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
            let visible = expectation(for: content, evaluatedWith: error)
            wait(for: [visible], timeout: 5)
        }
        waitForError(containing: "100,000 steps")

        replaceText(in: editor, with: "[ true ] whileTrue: [ 1 + 2 ]")
        runWithBudget("10,000,000 steps")
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.click()
        waitForError(containing: "Execution stopped.")
        XCTAssertFalse(stop.exists)
        replaceText(in: editor, with: "6 * 7")
        run.click()
        XCTAssertTrue(workspace.staticTexts["42"].waitForExistence(timeout: 5))
    }

    func testWorkspaceToolbarGroupsActionsAndFoldsResult() {
        let app = launchFreshApp(opening: ["Workspace", "Transcript"])
        let workspace = app.windows["toolWindow-1"]
        let transcript = app.windows["toolWindow-2"]
        let editor = workspace.textViews["workspaceEditor"]
        let run = workspace.buttons["executeButton"]
        let resultToggle = workspace.buttons["toolResultToggle"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(run.label, "Do it")
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
        choose("Clear Transcript", from: "Smalltalk", in: app)
        let cleared = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: output)
        wait(for: [cleared], timeout: 5)
    }

    func testWorkspaceExamplesMenuOpensTheEditedCatalogSource() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        replaceText(in: editor, with: """
        WorkspaceExamples compileClass: 'workspace ^ ''6 * 7'''.
        WorkspaceExamples compileClass: 'menuEntries ^ #((#workspace ''Edited Counter''))'.
        Desktop openWorkspace
        """)
        workspace.buttons["executeButton"].click()
        let editedWorkspace = app.windows["toolWindow-2"]
        XCTAssertTrue(editedWorkspace.textViews["workspaceEditor"].waitForExistence(timeout: 5))

        app.menuBars.menuBarItems["Smalltalk"].click()
        let examples = app.menuItems["Examples"].firstMatch
        XCTAssertTrue(examples.waitForExistence(timeout: 5))
        examples.hover()
        let entry = app.menuItems["Edited Counter"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.click()

        let opened = app.windows["toolWindow-3"]
        let source = opened.textViews["workspaceEditor"]
        let hasSource = NSPredicate(format: "value == %@", "6 * 7")
        wait(for: [expectation(for: hasSource, evaluatedWith: source)], timeout: 5)
        XCTAssertFalse(opened.staticTexts["42"].exists)
    }

    func testWorkspaceContextMenuUsesTheSelectionForAllThreeActions() {
        let app = launchFreshApp(opening: ["Workspace", "Transcript"])
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
        let transcript = app.windows["toolWindow-2"].staticTexts["transcriptOutput"]
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

    func testNativeEditorUsesTheEditingMenuFromSmalltalk() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        replaceText(in: workspace.textViews["workspaceEditor"], with: """
        menuEditor := UICodeEditor new identifier: 'menuEditor'; text: 'Copy this';
            editingMenu: #((#copy 'Copy Source') (#selectAll 'Select Everything')); yourself.
        UIWindow new title: 'Editor Menu'; content: menuEditor; open
        """)
        workspace.buttons["executeButton"].click()
        let editor = app.windows["toolWindow-2"].textViews["menuEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeKey("a", modifierFlags: .command)
        let point = editor.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45))
        withPreservedPasteboard { pasteboard in
            pasteboard.clearContents()
            point.rightClick()
            let copy = app.menuItems["editorContext-copy"].firstMatch
            XCTAssertTrue(copy.waitForExistence(timeout: 5))
            XCTAssertEqual(copy.title, "Copy Source")
            XCTAssertEqual(app.menuItems["editorContext-selectAll"].firstMatch.title, "Select Everything")
            XCTAssertFalse(app.menuItems["editorContext-cut"].exists)
            XCTAssertFalse(app.menuItems["editorContext-paste"].exists)
            copy.click()
            XCTAssertEqual(pasteboard.string(forType: .string), "Copy this")
        }
    }

    func testWorkspaceContextMenuOnlyShowsCommandsDefinedInSmalltalk() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        let execute = workspace.buttons["executeButton"]
        replaceText(in: editor, with: """
        menuProbe := 0.
        menuEditor := (Desktop windowAt: 1) content children at: 3.
        menuEditor contextMenu: (UIMenu new add: (UIButton new title: 'Run Probe';
            command: #runProbe; action: [ menuProbe := 42 ]; yourself); yourself).
        #menuChanged
        """)
        execute.click()
        XCTAssertTrue(workspace.staticTexts["#menuChanged"].waitForExistence(timeout: 5))

        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45)).rightClick()
        let custom = app.menuItems["editorContext-runProbe"].firstMatch
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        XCTAssertEqual(custom.title, "Run Probe")
        XCTAssertFalse(app.menuItems["editorContext-debugIt"].exists)
        custom.click()

        replaceText(in: editor, with: "menuProbe")
        execute.click()
        XCTAssertTrue(workspace.staticTexts["42"].waitForExistence(timeout: 5))
    }

    func testApplicationMenuAndShortcutsFollowTheFocusedWorkspacesCommands() {
        let app = launchFreshApp(opening: ["Workspace", "Transcript"])
        let workspace = app.windows["toolWindow-1"]
        let originalEditor = workspace.textViews["workspaceEditor"]
        replaceText(in: originalEditor, with: """
        WorkspaceWindow compile: 'applicationCommands
            | menu |
            menu := UIMenu new role: #applicationCommands; yourself.
            menu add: (self selectionButton: ''Print Selection'' command: #doIt action: #printIt:).
            menu add: ((self selectionButton: ''Inspect Selection'' command: #inspectIt action: #inspect:) enabled: false; yourself).
            ^ menu'.
        (Desktop windowAt: 1) title: 'Original Workspace'.
        Desktop openWorkspace
        """)
        workspace.buttons["executeButton"].click()
        let editor = app.windows["toolWindow-3"].textViews["workspaceEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()

        let menu = app.menuBars.menuBarItems["Smalltalk"]
        menu.click()
        XCTAssertTrue(app.menuItems["Print Selection"].firstMatch.waitForExistence(timeout: 5))
        let inspect = app.menuItems["Inspect Selection"].firstMatch
        XCTAssertTrue(inspect.exists)
        XCTAssertFalse(inspect.isEnabled)
        XCTAssertFalse(app.menuItems["Debug it"].exists)
        app.typeKey(.escape, modifierFlags: [])

        replaceText(in: editor, with: "1 / 0.\n6 * 7")
        editor.typeKey(.leftArrow, modifierFlags: [.command, .shift])
        editor.typeKey("d", modifierFlags: [.command, .shift])
        XCTAssertFalse(app.windows["debugger"].firstMatch.waitForExistence(timeout: 2))
        editor.typeKey("d", modifierFlags: .command)
        let transcript = app.windows["toolWindow-2"].staticTexts["transcriptOutput"]
        let printed = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "→ 42", "→ 42")
        wait(for: [expectation(for: printed, evaluatedWith: transcript)], timeout: 5)

        focusWindow("Original Workspace", in: app)
        menu.click()
        XCTAssertTrue(app.menuItems["Do it"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.menuItems["Print Selection"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    func testWorkspaceRecoveryMenuWorksWithoutProjectedCommands() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        let execute = workspace.buttons["executeButton"]
        replaceText(in: editor, with: """
        menuRoot := (Desktop windowAt: 1) content.
        (menuRoot children at: 3) contextMenu: nil.
        ((menuRoot children at: 1) children at: 2) visible: false.
        (menuRoot children at: 5) visible: false.
        #commandsHidden
        """)
        execute.click()
        XCTAssertTrue(workspace.staticTexts["#commandsHidden"].waitForExistence(timeout: 5))
        replaceText(in: editor, with: "heldWindows := Desktop windows. Desktop model windows: nil")
        execute.click()
        let message = "Desktop has no valid window list."
        let failure = workspace.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", message, message)).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 5))

        replaceText(in: editor, with: "1 / 0.\n6 * 7")
        editor.typeKey(.leftArrow, modifierFlags: [.command, .shift])
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45)).rightClick()
        let evaluate = app.menuItems["editorContext-doIt"].firstMatch
        XCTAssertTrue(evaluate.waitForExistence(timeout: 5))
        let print = app.menuItems["editorContext-printIt"].firstMatch
        let inspect = app.menuItems["editorContext-inspectIt"].firstMatch
        XCTAssertTrue(print.exists && print.isEnabled)
        XCTAssertTrue(inspect.exists && inspect.isEnabled)
        XCTAssertFalse(app.menuItems["editorContext-debugIt"].exists)
        evaluate.click()

        let result = workspace.staticTexts["workspaceRecoveryResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.value as? String ?? result.label, "42")
        XCTAssertTrue(failure.exists)

        replaceText(in: editor, with: "7 * 8")
        editor.typeKey("d", modifierFlags: .command)
        let shortcutResult = NSPredicate(format: "label == %@ OR value == %@", "56", "56")
        wait(for: [expectation(for: shortcutResult, evaluatedWith: result)], timeout: 5)
    }

    func testWorkspaceDebuggerStepsIntoSelectedCodeAndContinues() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        replaceText(in: editor, with: "1 / 0.\nCounter new value + 42")
        editor.typeKey(.leftArrow, modifierFlags: [.command, .shift])

        editor.typeKey("d", modifierFlags: [.command, .shift])
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

        let workspaceRow = debugger.staticTexts["Workspace"].firstMatch
        XCTAssertTrue(workspaceRow.waitForExistence(timeout: 5))
        workspaceRow.click()
        wait(for: [expectation(for: workspaceFrame, evaluatedWith: title)], timeout: 5)

        debugger.buttons["debuggerContinue"].click()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: debugger)], timeout: 5)
        XCTAssertTrue(workspace.staticTexts["42"].waitForExistence(timeout: 5))
        XCTAssertFalse(workspace.staticTexts["ERROR"].exists)
    }

    func testWorkspaceDebuggerCanStopWhenItsSmalltalkPresentationFails() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        let execute = workspace.buttons["executeButton"]
        replaceText(in: editor, with: """
        stopProbe := 0.
        DebuggerPresentation compileClass: 'contentFor: stack frame: frame error: error phase: phase ^ nil'.
        #debuggerPresentationChanged
        """)
        execute.click()
        XCTAssertTrue(workspace.staticTexts["#debuggerPresentationChanged"].waitForExistence(timeout: 5))

        replaceText(in: editor, with: "stopProbe := stopProbe + 1")
        let debugger = openWorkspaceDebugger(in: app, editor: editor)
        let message = "The debugger presentation must provide a control tree."
        let error = debugger.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", message, message)).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 8), debugger.debugDescription)
        XCTAssertFalse(debugger.buttons["debuggerContinue"].exists)

        let stop = debugger.buttons["debuggerStop"]
        XCTAssertTrue(stop.isEnabled)
        stop.click()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: debugger)
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: execute)
        wait(for: [closed, ready], timeout: 5)
        replaceText(in: editor, with: "stopProbe + 42")
        execute.click()
        XCTAssertTrue(workspace.staticTexts["42"].waitForExistence(timeout: 5))
        XCTAssertFalse(workspace.staticTexts["ERROR"].exists)
    }

    func testWorkspaceDebuggerUsesTheImageWindowAndStopsWhenClosed() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        let execute = workspace.buttons["executeButton"]
        replaceText(in: editor, with: """
        closeProbe := 0.
        DebuggerWindow compile: 'initialize
            super initialize.
            identifier := ''debugger''.
            self title: ''Smalltalk Debugger''; minimumWidth: 620 height: 360; resizeWidth: 700 height: 450'.
        #debuggerWindowChanged
        """)
        execute.click()
        XCTAssertTrue(workspace.staticTexts["#debuggerWindowChanged"].waitForExistence(timeout: 5))

        replaceText(in: editor, with: "closeProbe := closeProbe + 1")
        let debugger = openWorkspaceDebugger(in: app, editor: editor)
        XCTAssertEqual(debugger.title, "Smalltalk Debugger")
        XCTAssertEqual(debugger.frame.width, 700, accuracy: 2)
        XCTAssertTrue(debugger.buttons["debuggerContinue"].waitForExistence(timeout: 5))
        debugger.buttons[XCUIIdentifierCloseWindow].click()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: debugger)
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: execute)
        wait(for: [closed, ready], timeout: 5)
        replaceText(in: editor, with: "closeProbe + 42")
        execute.click()
        XCTAssertTrue(workspace.staticTexts["42"].waitForExistence(timeout: 5))
    }

    func testWorkspaceDebuggerShowsTheFailureAndClosesWithoutResuming() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        let execute = workspace.buttons["executeButton"]
        replaceText(in: editor, with: "failureProbe := 41.\n1 / 0.\nfailureProbe := 0")

        let debugger = openWorkspaceDebugger(in: app, editor: editor)
        let resume = debugger.buttons["debuggerContinue"]
        XCTAssertTrue(resume.waitForExistence(timeout: 8))
        resume.click()

        let fault = debugger.staticTexts["debuggerError"]
        let divisionError = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Division by zero", "Division by zero")
        wait(for: [expectation(for: divisionError, evaluatedWith: fault)], timeout: 5)
        XCTAssertFalse(resume.isEnabled)
        XCTAssertFalse(debugger.buttons["debuggerStepInto"].isEnabled)
        XCTAssertFalse(debugger.buttons["debuggerStepOver"].isEnabled)
        XCTAssertFalse(debugger.buttons["debuggerStepOut"].isEnabled)
        let close = debugger.buttons["debuggerStop"]
        XCTAssertEqual(close.label, "Close")
        XCTAssertTrue(close.isEnabled)
        close.click()

        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: debugger)
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: execute)
        wait(for: [closed, ready], timeout: 5)
        replaceText(in: editor, with: "failureProbe + 1")
        execute.click()
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

    func testObjectInspectorsUseTheImageWindowAndCloseIndependently() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        replaceText(in: editor, with: """
        ObjectInspectorWindow compile: 'initialize
            super initialize.
            identifier := ''objectInspector''.
            self title: ''Smalltalk Inspector''; minimumWidth: 380 height: 250; resizeWidth: 640 height: 440'.
        #inspectorWindowChanged
        """)
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["#inspectorWindowChanged"].waitForExistence(timeout: 5))

        let inspectors = app.windows.matching(identifier: "objectInspector")
        func inspector(for className: String) -> XCUIElement {
            inspectors.containing(NSPredicate(format: "identifier == %@ AND (label == %@ OR value == %@)",
                                             "inspectorClass", className, className)).firstMatch
        }

        replaceText(in: editor, with: "Counter new add: 41")
        editor.typeKey("i", modifierFlags: .command)
        let counter = inspector(for: "Counter")
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        XCTAssertEqual(counter.title, "Smalltalk Inspector")
        XCTAssertEqual(counter.frame.width, 640, accuracy: 2)

        focusWindow("Workspace", in: app)
        replaceText(in: editor, with: "#(1 2)")
        editor.typeKey("i", modifierFlags: .command)
        let array = inspector(for: "Array")
        XCTAssertTrue(array.waitForExistence(timeout: 5))
        XCTAssertEqual(inspectors.count, 2)
        array.buttons[XCUIIdentifierCloseWindow].click()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: array)
        wait(for: [closed], timeout: 5)
        XCTAssertTrue(counter.exists)
        XCTAssertEqual(inspectors.count, 1)
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
        openAndArrangeStandardTools(in: app)
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
        openTool("Workspace", in: app)
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

    func testRejectedImagePreservesTheLiveSessionAndResetStartsFresh() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let badImage = directory.appendingPathComponent("Rejected.stimage")
        try Data(#"{"format":"st80-image","version":0}"#.utf8).write(to: badImage)
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        replaceText(in: editor, with: "resetProbe := Counter new add: 41; yourself. resetProbe value")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["41"].waitForExistence(timeout: 5))

        let draft = "resetProbe value + 1"
        replaceText(in: editor, with: draft)
        openImage(badImage, in: app)
        XCTAssertTrue(app.staticTexts["Could not load the image"].waitForExistence(timeout: 5))
        let reason = "Image version 0 is unsupported."
        let detail = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", reason, reason)).firstMatch
        XCTAssertTrue(detail.exists)
        app.buttons["OK"].click()
        XCTAssertEqual(editor.value as? String, draft)
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["42"].waitForExistence(timeout: 5))

        editor.typeKey("i", modifierFlags: .command)
        let inspector = app.windows["objectInspector"].firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        app.menuBars.menuBarItems["Smalltalk"].click()
        app.menuItems["Reset Session"].click()
        XCTAssertTrue(app.buttons["Don't Save"].waitForExistence(timeout: 5))
        app.buttons["Don't Save"].click()
        assertDesktopEmpty(in: app)
        XCTAssertFalse(inspector.exists)
        openTool("Workspace", in: app)
        replaceText(in: editor, with: "resetProbe")
        workspace.buttons["executeButton"].click()
        let unknownBinding = expectation(for: NSPredicate(format: "label == %@", "Error"),
                                         evaluatedWith: workspace.buttons["toolResultToggle"])
        let message = "Unknown variable: resetProbe"
        let missingProbe = workspace.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", message, message)).firstMatch
        wait(for: [unknownBinding], timeout: 5)
        XCTAssertTrue(missingProbe.waitForExistence(timeout: 5))
    }

    func testIgnoredFormEditKeepsItsDraftUntilTheControlAcceptsIt() {
        let app = launchFreshApp()
        defer { app.terminate() }
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        replaceText(in: editor, with: """
        UITextField subclass: #GateField instanceVariableNames: ''.
        GateField compile: 'editText: aString
            heldField enabled: false.
            ^ super editText: aString'.
        gate := GateField new identifier: 'gate'; label: 'Gate'; yourself.
        heldField := UITextField new identifier: 'heldField'; label: 'Draft'; yourself.
        resultLabel := UILabel new text: 'Ready'; yourself.
        submit := UIButton new identifier: 'submit'; title: 'Submit';
            action: [ resultLabel text: heldField text ]; yourself.
        form := UIWindow new title: 'Draft Form';
            content: (UIColumn new add: gate; add: heldField; add: submit; add: resultLabel; yourself); open
        """)
        workspace.buttons["executeButton"].click()
        let form = app.windows["toolWindow-2"]
        let gate = form.textFields["gate"]
        let field = form.textFields["heldField"]
        let submit = form.buttons["submit"]
        XCTAssertTrue(gate.waitForExistence(timeout: 10))

        // Neither field has live input. The first edit disables the second
        // while the app is flushing both pending edits for Submit.
        gate.click()
        pasteText("Close the gate", into: gate)
        field.click()
        pasteText("Retained draft", into: field)
        submit.click()
        XCTAssertTrue(form.staticTexts["The control could not accept its pending edit. The draft is still available."].waitForExistence(timeout: 5))
        XCTAssertFalse(field.isEnabled)
        XCTAssertEqual(field.value as? String, "Retained draft")
        XCTAssertTrue(form.staticTexts["Ready"].exists)

        focusWindow("Workspace", in: app)
        replaceText(in: editor, with: "heldField enabled: true")
        workspace.buttons["executeButton"].click()
        let enabled = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: field)
        wait(for: [enabled], timeout: 5)
        focusWindow("Draft Form", in: app)
        submit.click()
        XCTAssertTrue(form.staticTexts["Retained draft"].waitForExistence(timeout: 5))
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
        openTool("Workspace", in: app)
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
        let window = app.windows["toolWindow-2"]
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
        pasteText("Moritz", into: first)
        last.click()
        pasteText("Frisch", into: last)
        window.buttons["Greet"].click()
        XCTAssertTrue(window.staticTexts["Hello, Moritz Frisch!"].waitForExistence(timeout: 5))

        first.click()
        first.typeKey("a", modifierFlags: .command)
        pasteText("Ada", into: first)
        last.click()
        last.typeKey("a", modifierFlags: .command)
        pasteText("Lovelace", into: last)
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
        let restored = app.windows["toolWindow-2"]
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
        focusWindow("Workspace", in: app)
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
        openAndArrangeStandardTools(in: app)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Examples/GreetingWindow.st"), encoding: .utf8)
        let workspace = app.windows["toolWindow-1"]
        let editor = workspace.textViews["workspaceEditor"]
        replaceText(in: editor, with: source + """
        . nameEdits := 0.
        GreetingController compile: 'nameChanged: aString
            nameEdits := nameEdits + 1.
            model name: aString'.
        greetingView moveToX: 100 y: 1000.
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
        pasteText("Moritz", into: field)
        // No Return, focus change or click: the controller updates the model
        // when the input changes, and both dependent views must react.
        XCTAssertTrue(second.staticTexts["Hello, Moritz!"].waitForExistence(timeout: 5))
        XCTAssertEqual(second.textFields["Name"].value as? String, "Moritz")
        XCTAssertEqual(field.value as? String, "Moritz")
        field.typeKey(.leftArrow, modifierFlags: .command)
        pasteText("Dr. ", into: field)
        XCTAssertTrue(second.staticTexts["Hello, Dr. Moritz!"].waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Dr. Moritz")

        focusWindow("Workspace", in: app)
        replaceText(in: editor, with: "editsBeforeAda := nameEdits. greetingModel name: 'Ada'")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(first.staticTexts["Hello, Ada!"].waitForExistence(timeout: 5))
        XCTAssertTrue(second.staticTexts["Hello, Ada!"].exists)
        XCTAssertEqual(field.value as? String, "Ada")
        // A second command flushes queued edits. Showing Ada must not have run
        // the input controller again, even if it writes back the same name.
        replaceText(in: editor, with: "greetingModel name , ' / ' , (nameEdits - editsBeforeAda) printString")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["'Ada / 0'"].waitForExistence(timeout: 5))
        second.buttons["Clear"].click()
        XCTAssertTrue(first.staticTexts["No greeting yet."].waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "")

        focusWindow("Workspace", in: app)
        replaceText(in: editor, with: "GreetingController compile: 'nameChanged: aString ^ 1 / 0'")
        workspace.buttons["executeButton"].click()
        field.click()
        pasteText("Recoverable", into: field)
        let inputError = first.staticTexts.containing(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Division by zero", "Division by zero")).firstMatch
        XCTAssertTrue(inputError.waitForExistence(timeout: 5))

        let image = directory.appendingPathComponent("Smalltalk.stimage")
        field.typeKey("q", modifierFlags: .command)
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.click()
        let panelSave = app.buttons["OKButton"]
        XCTAssertTrue(panelSave.waitForExistence(timeout: 5))
        navigateFilePanel(in: app, to: directory.path)
        panelSave.click()
        XCTAssertTrue(app.staticTexts["Could not save the image"].waitForExistence(timeout: 5))
        XCTAssertFalse(FileManager.default.fileExists(atPath: image.path))
        app.buttons["OK"].click()
        XCTAssertEqual(field.value as? String, "Recoverable")

        focusWindow("Workspace", in: app)
        replaceText(in: editor, with: "GreetingController compile: 'nameChanged: aString model name: aString'")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(second.staticTexts["Hello, Recoverable!"].waitForExistence(timeout: 5))

        field.click()
        field.typeKey("a", modifierFlags: .command)
        pasteText("Saved", into: field)
        field.typeKey("s", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["OKButton"].waitForExistence(timeout: 5))
        navigateFilePanel(in: app, to: directory.path)
        app.buttons["OKButton"].click()
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
        let window = app.windows["toolWindow-2"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertEqual(window.frame.width, 650, accuracy: 2)
        XCTAssertEqual(window.frame.height, 420, accuracy: 2)
        window.buttons[XCUIIdentifierCloseWindow].click()
        let secondEditor = window.textViews["workspaceEditor"]
        replaceText(in: secondEditor, with: "Desktop windows size")
        window.buttons["executeButton"].click()
        XCTAssertTrue(window.staticTexts["2"].waitForExistence(timeout: 5))
        replaceText(in: secondEditor, with: "protected title: 'Closable'")
        window.buttons["executeButton"].click()
        window.buttons[XCUIIdentifierCloseWindow].click()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: window)
        wait(for: [closed], timeout: 5)
        XCTAssertTrue(first.exists)
        XCTAssertFalse(first.staticTexts["ERROR"].exists)
    }

    func testBrowserVersionsOpensTheSelectedMethodsHistory() {
        let app = launchFreshApp(opening: ["Browser"])
        let browser = app.windows["toolWindow-1"]
        let method = browser.staticTexts["value"].firstMatch
        XCTAssertTrue(method.waitForExistence(timeout: 5))
        method.click()
        let actions = browser.descendants(matching: .any).matching(identifier: "methodActions").firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.click()
        let versions = app.menuItems["Versions …"].firstMatch
        XCTAssertTrue(versions.waitForExistence(timeout: 5))
        versions.click()

        let history = app.windows["toolWindow-2"]
        XCTAssertTrue(history.staticTexts["Versions: Counter » value"].waitForExistence(timeout: 5))
        XCTAssertTrue(history.staticTexts["Shipped Baseline"].firstMatch.exists)
        history.staticTexts["Counter » value"].firstMatch.click()
        let restore = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: history.buttons["restoreChangeButton"])
        wait(for: [restore], timeout: 5)
    }

    func testOpeningChangesReportsInvalidJournalAndAllowsRetry() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let invalid = directory.appendingPathComponent("Invalid.changes")
        try Data("Incomplete header".utf8).write(to: invalid)
        let valid = directory.appendingPathComponent("Valid.changes")
        let journal = """
        {"format":"st80-changes","version":1,"id":"\(UUID())"}
        {"id":"\(UUID())","sequence":1,"timestamp":0,"kind":"method","className":"Counter","selector":"recoveredImport","source":"recoveredImport ^ 73"}

        """
        try Data(journal.utf8).write(to: valid)

        let app = launchFreshApp(opening: [])
        defer { app.terminate() }
        assertDesktopEmpty(in: app)

        func openChanges(_ file: URL) {
            choose("Open Changes File …", from: "Smalltalk", in: app)
            let open = app.buttons["OKButton"]
            XCTAssertTrue(open.waitForExistence(timeout: 5))
            navigateFilePanel(in: app, to: file.path)
            open.click()
        }

        openChanges(invalid)
        let history = app.windows["toolWindow-1"]
        XCTAssertTrue(app.staticTexts["Could not import the changes log"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The changes log header is missing or incomplete."].exists)
        app.buttons["OK"].click()
        XCTAssertFalse(history.exists)

        openChanges(valid)
        XCTAssertTrue(history.staticTexts["Counter » recoveredImport"].firstMatch.waitForExistence(timeout: 5))
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
        openTool("Workspace", in: app)
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
        let history = app.windows["toolWindow-2"]
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
        focusWindow("Workspace", in: app)
        replaceText(in: restoredEditor, with: "Counter new recovered")
        restored.buttons["executeButton"].click()
        XCTAssertTrue(restored.staticTexts["73"].waitForExistence(timeout: 5))
        XCTAssertFalse(restored.staticTexts["ERROR"].exists)
    }

    private func launchFreshApp(opening tools: [String] = ["Workspace"]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["ST80_PREFERENCES_SUITE"] = "dev.moritz.Smalltalk80UITests.\(UUID().uuidString)"
        app.launch()
        openTools(tools, in: app)
        return app
    }

    private func openTools(_ tools: [String], in app: XCUIApplication) {
        for (index, title) in tools.enumerated() {
            openTool(title, in: app)
            XCTAssertTrue(app.windows["toolWindow-\(index + 1)"].waitForExistence(timeout: 10))
        }
        if tools.first == "Workspace", tools.count > 1 {
            focusWindow("Workspace", in: app)
        }
    }

    private func openAndArrangeStandardTools(in app: XCUIApplication) {
        openTools(["Workspace", "Browser", "Transcript"], in: app)
        choose("Arrange Tools", from: "Smalltalk", in: app)
    }

    private func openTool(_ name: String, in app: XCUIApplication) {
        choose(name, from: "Tools", in: app)
    }

    private func focusWindow(_ title: String, in app: XCUIApplication) {
        choose(title, from: "Window", in: app)
    }

    private func choose(_ title: String, from menu: String, in app: XCUIApplication) {
        enabledMenuItem(title, from: menu, in: app).click()
    }

    private func enabledMenuItem(_ title: String, from menu: String, in app: XCUIApplication) -> XCUIElement {
        let menuBarItem = app.menuBars.menuBarItems[menu]
        XCTAssertTrue(menuBarItem.waitForExistence(timeout: 10))
        menuBarItem.click()
        let item = menuBarItem.menuItems[title].firstMatch
        let enabled = expectation(for: NSPredicate(format: "exists == true AND enabled == true"), evaluatedWith: item)
        wait(for: [enabled], timeout: 10)
        return item
    }

    private func assertDesktopEmpty(in app: XCUIApplication) {
        _ = enabledMenuItem("Workspace", from: "Tools", in: app)
        app.typeKey(.escape, modifierFlags: [])
        let empty = expectation(for: NSPredicate { _, _ in app.windows.count == 0 }, evaluatedWith: nil)
        wait(for: [empty], timeout: 10)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("st80-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func openWorkspaceDebugger(in app: XCUIApplication, editor: XCUIElement) -> XCUIElement {
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45)).rightClick()
        let debug = app.menuItems["editorContext-debugIt"].firstMatch
        XCTAssertTrue(debug.waitForExistence(timeout: 5), editor.debugDescription)
        XCTAssertEqual(debug.title, "Debug it")
        debug.click()
        let debugger = app.windows["debugger"].firstMatch
        XCTAssertTrue(debugger.waitForExistence(timeout: 5))
        return debugger
    }

    private func replaceText(in editor: XCUIElement, with source: String) {
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeKey("a", modifierFlags: .command)
        pasteText(source, into: editor)
        XCTAssertEqual(editor.value as? String, source)
    }

    /// Paste at the current selection; callers set focus and select text as needed.
    private func pasteText(_ text: String, into target: XCUIElement) {
        // Avoid dead-key layout differences and long per-key synthesis in XCUI.
        withPreservedPasteboard { pasteboard in
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            target.typeKey("v", modifierFlags: .command)
        }
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

    private func requestReset(in app: XCUIApplication) {
        app.menuBars.menuBarItems["Smalltalk"].click()
        app.menuItems["Reset Session"].click()
    }

    private func saveImage(in app: XCUIApplication, editor: XCUIElement, directory: URL) {
        editor.typeKey("s", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["OKButton"].waitForExistence(timeout: 5))
        navigateFilePanel(in: app, to: directory.path)
        app.buttons["OKButton"].click()
        let image = directory.appendingPathComponent("Smalltalk.stimage")
        let saved = expectation(for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: image.path) }, evaluatedWith: nil)
        wait(for: [saved], timeout: 10)
    }

    private func openImage(_ image: URL, in app: XCUIApplication, decision: String? = "Don't Save") {
        choose("Open Image …", from: "File", in: app)
        let open = app.buttons["OKButton"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        navigateFilePanel(in: app, to: image.path)
        open.click()
        if let decision, app.buttons[decision].waitForExistence(timeout: 2) {
            app.buttons[decision].click()
        }
    }

    private func navigateFilePanel(in app: XCUIApplication, to path: String) {
        app.typeKey("g", modifierFlags: [.command, .shift])
        pasteText(path, into: app)
        app.typeKey(.return, modifierFlags: [])
    }
}
