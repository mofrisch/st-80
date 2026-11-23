import AppKit
import XCTest

@MainActor
final class Smalltalk80UITests: XCTestCase {
    func testWorkspaceAndLiveMethodEditing() {
        let app = launchFreshApp()
        let workspace = app.windows["toolWindow-1"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 10))
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(workspace.staticTexts["5"].waitForExistence(timeout: 5))
        let transcript = app.windows["toolWindow-3"]
        XCTAssertTrue(transcript.staticTexts.containing(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "Der Zähler steht bei 5", "Der Zähler steht bei 5")).firstMatch.exists)

        workspace.textViews["workspaceEditor"].typeKey("2", modifierFlags: .command)
        let browser = app.windows["toolWindow-2"]
        XCTAssertTrue(browser.waitForExistence(timeout: 5))
        let panes = ["Klassenkategorien", "Klassen", "Protokolle", "Methoden"].map { browser.staticTexts[$0] }
        for pane in panes { XCTAssertTrue(pane.waitForExistence(timeout: 5)) }
        for (left, right) in zip(panes, panes.dropFirst()) {
            XCTAssertLessThan(left.frame.minX, right.frame.minX)
        }
        browser.staticTexts["Beispiele"].firstMatch.click()
        browser.staticTexts["Counter"].firstMatch.click()
        browser.staticTexts["Unär"].firstMatch.click()
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
        XCTAssertFalse(workspace.staticTexts["FEHLER"].exists)
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
        firstEditor.typeKey("o", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["OKButton"].waitForExistence(timeout: 5))
        navigateFilePanel(in: app, to: url.path)
        app.buttons["OKButton"].click()
        let restoredSource = expectation(for: NSPredicate(format: "value == %@", source), evaluatedWith: firstEditor)
        wait(for: [restoredSource], timeout: 5)
        XCTAssertEqual(secondEditor.value as? String, "persisted value")

        app.terminate()
        app.launch()
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
        XCTAssertFalse(reopenedSecondWindow.staticTexts["FEHLER"].exists)
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
            self title: ''Smalltalk-Formular''.
            firstName := UITextField new.
            firstName label: ''Vorname''; placeholder: ''Dein Vorname''.
            surname := UITextField new.
            surname label: ''Nachname''; placeholder: ''Dein Nachname''.
            greeting := UILabel new.
            greeting text: ''Bereit.''.
            button := UIButton new.
            button title: ''Begrüßen''; action: [ self greet ].
            row := UIRow new.
            row spacing: 12; add: firstName; add: surname.
            column := UIColumn new.
            column padding: 20; spacing: 12.
            column add: row; add: button; add: greeting.
            self content: column'.
        FormWindow compile: 'greet greeting text: ''Hallo, '', firstName text, '' '', surname text, ''!'''.
        form := FormWindow new open
        """)
        app.windows["toolWindow-1"].buttons["executeButton"].click()
        let window = app.windows["toolWindow-4"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertEqual(window.title, "Smalltalk-Formular")
        let first = window.textFields["Vorname"]
        let last = window.textFields["Nachname"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(last.exists)
        XCTAssertTrue(first.identifier.hasPrefix("ui-"))
        XCTAssertNotEqual(first.identifier, last.identifier)
        XCTAssertNotEqual(first.identifier, window.buttons["Begrüßen"].identifier)
        XCTAssertLessThan(first.frame.minX, last.frame.minX)
        first.click()
        first.typeText("Moritz")
        last.click()
        last.typeText("Frisch")
        window.buttons["Begrüßen"].click()
        XCTAssertTrue(window.staticTexts["Hallo, Moritz Frisch!"].waitForExistence(timeout: 5))

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
        let restored = app.windows["toolWindow-4"]
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        XCTAssertEqual(restored.textFields["Vorname"].value as? String, "Ada")
        XCTAssertEqual(restored.textFields["Nachname"].value as? String, "Lovelace")
        restored.buttons["Begrüßen"].click()
        XCTAssertTrue(restored.staticTexts["Hallo, Ada Lovelace!"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: restored.screenshot())
        attachment.name = "Smalltalk form after image relaunch"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Projection errors must not prevent the workspace from flushing edits
        // and evaluating a repair of a malformed UI tree.
        let workspace = app.windows["toolWindow-1"]
        let workspaceEditor = workspace.textViews["workspaceEditor"]
        restored.textFields["Vorname"].typeKey("1", modifierFlags: .command)
        replaceText(in: workspaceEditor, with: "broken := UIColumn new. form content: broken. broken add: broken")
        workspace.buttons["executeButton"].click()
        let error = workspace.staticTexts.containing(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Ungültige Oberfläche", "Ungültige Oberfläche")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        replaceText(in: workspaceEditor, with: "form content: UILabel new. form content text: 'Layout repariert.'")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(restored.staticTexts["Layout repariert."].waitForExistence(timeout: 5))
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
        XCTAssertTrue(second.staticTexts["Hallo, Moritz!"].waitForExistence(timeout: 5))
        XCTAssertEqual(second.textFields["Name"].value as? String, "Moritz")
        XCTAssertEqual(field.value as? String, "Moritz")
        field.typeKey(.leftArrow, modifierFlags: .command)
        field.typeText("Dr. ")
        XCTAssertTrue(second.staticTexts["Hallo, Dr. Moritz!"].waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Dr. Moritz")

        field.typeKey("1", modifierFlags: .command)
        replaceText(in: editor, with: "greetingModel name: 'Ada'")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(first.staticTexts["Hallo, Ada!"].waitForExistence(timeout: 5))
        XCTAssertTrue(second.staticTexts["Hallo, Ada!"].exists)
        XCTAssertEqual(field.value as? String, "Ada")
        second.buttons["Leeren"].click()
        XCTAssertTrue(first.staticTexts["Noch keine Begrüßung."].waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "")

        second.textFields["Name"].typeKey("1", modifierFlags: .command)
        replaceText(in: editor, with: "GreetingController compile: 'nameChanged: aString ^ 1 / 0'")
        workspace.buttons["executeButton"].click()
        field.click()
        field.typeText("Reparierbar")
        let inputError = first.staticTexts.containing(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Division durch null", "Division durch null")).firstMatch
        XCTAssertTrue(inputError.waitForExistence(timeout: 5))
        field.typeKey("1", modifierFlags: .command)
        replaceText(in: editor, with: "GreetingController compile: 'nameChanged: aString model name: aString'")
        workspace.buttons["executeButton"].click()
        XCTAssertTrue(second.staticTexts["Hallo, Reparierbar!"].waitForExistence(timeout: 5))

        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("Gespeichert")
        field.typeKey("s", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["OKButton"].waitForExistence(timeout: 5))
        navigateFilePanel(in: app, to: directory.path)
        app.buttons["OKButton"].click()
        let image = directory.appendingPathComponent("Smalltalk.stimage")
        let saved = expectation(for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: image.path) }, evaluatedWith: nil)
        wait(for: [saved], timeout: 10)
        app.terminate()
        app.launch()
        let restoredFirst = app.windows["toolWindow-4"]
        let restoredSecond = app.windows["toolWindow-5"]
        XCTAssertTrue(restoredFirst.waitForExistence(timeout: 10))
        XCTAssertEqual(restoredFirst.textFields["Name"].value as? String, "Gespeichert")
        XCTAssertTrue(restoredSecond.staticTexts["Hallo, Gespeichert!"].exists)
        restoredSecond.buttons["Beispielname"].click()
        XCTAssertTrue(restoredFirst.staticTexts["Hallo, Moritz!"].waitForExistence(timeout: 5))
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
        XCTAssertFalse(first.staticTexts["FEHLER"].exists)
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
        app.terminate()
        app.launch()
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
        XCTAssertTrue(history.staticTexts["Nach Image-Stand"].firstMatch.exists)
        history.buttons["restoreChangeButton"].click()
        XCTAssertTrue(history.staticTexts["Wiederhergestellt: Counter » recovered"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: history.screenshot())
        attachment.name = "Recovered method from the durable changes journal"
        attachment.lifetime = .keepAlways; add(attachment)
        record.typeKey("1", modifierFlags: .command)
        replaceText(in: restoredEditor, with: "Counter new recovered")
        restored.buttons["executeButton"].click()
        XCTAssertTrue(restored.staticTexts["73"].waitForExistence(timeout: 5))
        XCTAssertFalse(restored.staticTexts["FEHLER"].exists)
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
        // Paste source verbatim and restore the user's pasteboard afterward.
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        pasteboard.clearContents()
        pasteboard.setString(source, forType: .string)
        editor.typeKey("v", modifierFlags: .command)
        pasteboard.clearContents()
        if let previous { pasteboard.writeObjects(previous) }
        XCTAssertEqual(editor.value as? String, source)
    }

    private func navigateFilePanel(in app: XCUIApplication, to path: String) {
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(path)
        app.typeKey(.return, modifierFlags: [])
    }
}
