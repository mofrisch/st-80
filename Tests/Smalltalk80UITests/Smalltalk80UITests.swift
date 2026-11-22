import AppKit
import XCTest

@MainActor
final class Smalltalk80UITests: XCTestCase {
    func testWorkspaceAndLiveMethodEditing() {
        let app = XCUIApplication()
        app.launchEnvironment["ST80_PREFERENCES_SUITE"] = "dev.moritz.Smalltalk80UITests.\(UUID().uuidString)"
        app.launch()
        let execute = app.buttons["executeButton"]
        XCTAssertTrue(execute.waitForExistence(timeout: 10))
        execute.click()
        XCTAssertTrue(app.staticTexts["5"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "value CONTAINS %@", "Der Zähler steht bei 5")).firstMatch.exists)

        app.staticTexts["Counter"].firstMatch.click()
        app.staticTexts["value"].firstMatch.click()
        let method = app.textViews["methodEditor"]
        XCTAssertTrue(method.waitForExistence(timeout: 5))
        method.click()
        method.typeKey("a", modifierFlags: .command)
        method.typeText("value\n    ^ count + 10")
        method.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Counter » value"].firstMatch.waitForExistence(timeout: 5))
        app.typeKey("1", modifierFlags: .command)
        execute.click()
        XCTAssertTrue(app.staticTexts["15"].waitForExistence(timeout: 5))
    }

    func testDoItEvaluatesOnlySelection() {
        let app = XCUIApplication()
        app.launchEnvironment["ST80_PREFERENCES_SUITE"] = "dev.moritz.Smalltalk80UITests.\(UUID().uuidString)"
        app.launch()
        let editor = app.textViews["workspaceEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("1 / 0.\n6 * 7")
        editor.typeKey(.leftArrow, modifierFlags: [.command, .shift])
        editor.typeKey("d", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["42"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["FEHLER"].exists)
    }

    func testImageSaveLoadAndRelaunchPreserveLiveSystem() throws {
        continueAfterFailure = false
        let suite = "dev.moritz.Smalltalk80UITests.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("st80-image-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        let url = directory.appendingPathComponent("Smalltalk.stimage")
        let app = XCUIApplication()
        app.launchEnvironment["ST80_PREFERENCES_SUITE"] = suite
        app.launch()
        let source = """
        Counter subclass: #SavedCounter instanceVariableNames: ''.
        SavedCounter compile: 'value ^ super value + 100'.
        persisted := SavedCounter new.
        persisted add: 7.
        Transcript show: 'Image survives restart'; cr.
        persisted value
        """
        replaceWorkspace(in: app, with: source)
        app.buttons["executeButton"].click()
        XCTAssertTrue(app.staticTexts["107"].waitForExistence(timeout: 5))

        app.buttons["saveImageButton"].click()
        XCTAssertTrue(app.buttons["OKButton"].waitForExistence(timeout: 5))
        navigateFilePanel(in: app, to: directory.path)
        let save = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label IN %@", "OKButton", ["Save", "Sichern", "Speichern"])).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.click()
        let saved = expectation(for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: url.path) }, evaluatedWith: nil)
        wait(for: [saved], timeout: 10)
        XCTAssertTrue(app.staticTexts["imageName"].waitForExistence(timeout: 5))

        replaceWorkspace(in: app, with: "persisted add: 50. persisted value")
        app.buttons["executeButton"].click()
        XCTAssertTrue(app.staticTexts["157"].waitForExistence(timeout: 5))
        app.textViews["workspaceEditor"].typeKey("o", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["OKButton"].waitForExistence(timeout: 5))
        navigateFilePanel(in: app, to: url.path)
        let open = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label IN %@", "OKButton", ["Open", "Öffnen"])).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.click()
        let restoredEditor = app.textViews["workspaceEditor"]
        XCTAssertTrue(restoredEditor.waitForExistence(timeout: 5))
        let restoredSource = expectation(for: NSPredicate(format: "value == %@", source), evaluatedWith: restoredEditor)
        wait(for: [restoredSource], timeout: 5)

        app.terminate()
        app.launch()
        let editor = app.textViews["workspaceEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let reopenedSource = expectation(for: NSPredicate(format: "value == %@", source), evaluatedWith: editor)
        wait(for: [reopenedSource], timeout: 5)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "Image survives restart", "Image survives restart")).firstMatch.exists)
        replaceWorkspace(in: app, with: "persisted value")
        app.buttons["executeButton"].click()
        XCTAssertTrue(app.staticTexts["107"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["FEHLER"].exists)
    }

    private func replaceWorkspace(in app: XCUIApplication, with source: String) {
        let editor = app.textViews["workspaceEditor"]
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
