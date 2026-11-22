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
        browser.staticTexts["Counter"].firstMatch.click()
        browser.staticTexts["value"].firstMatch.click()
        let method = browser.textViews["methodEditor"]
        XCTAssertTrue(method.waitForExistence(timeout: 5))
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
