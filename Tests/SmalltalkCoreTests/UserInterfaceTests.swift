import Foundation
import Testing
@testable import SmalltalkCore

@MainActor
struct UserInterfaceTests {
    private func elements(_ root: UIElementInfo?) -> [UIElementInfo] {
        guard let root else { return [] }
        return [root] + root.children.flatMap { elements($0) }
    }

    @Test func exampleProjectsNestedLayoutsAndDispatchesTextAndButtons() async throws {
        let session = SmalltalkSession()
        let opened = await session.evaluate(SmalltalkExamples.legacyUserInterface)
        #expect(opened.error == nil)
        let window = try #require(opened.windows.first { $0.kind == .custom })
        #expect(window.title == "Meine Smalltalk-Oberfläche")
        let column = try #require(window.content)
        #expect(column.kind == .column)
        #expect(column.padding == 20)
        #expect(column.spacing == 12)
        #expect(column.children.map(\.kind) == [.textField, .row, .label])
        let field = try #require(elements(column).first { $0.kind == .textField })
        #expect(field.label == "Name")
        #expect(field.placeholder == "Dein Name")
        let greet = try #require(elements(column).first { $0.kind == .button && $0.text == "Begrüßen" })
        let clear = try #require(elements(column).first { $0.kind == .button && $0.text == "Leeren" })
        let edited = await session.uiAction(.text(windowID: window.id, elementID: field.id, value: "Moritz 👋"))
        #expect(edited.error == nil)
        #expect(elements(edited.windows.last?.content).contains { $0.id == field.id && $0.text == "Moritz 👋" })
        let clicked = await session.uiAction(.click(windowID: window.id, elementID: greet.id))
        #expect(clicked.error == nil)
        #expect(elements(clicked.windows.last?.content).contains { $0.kind == .label && $0.text == "Hallo, Moritz 👋!" })
        let cleared = await session.uiAction(.click(windowID: window.id, elementID: clear.id))
        #expect(cleared.error == nil)
        #expect(elements(cleared.windows.last?.content).contains { $0.id == field.id && $0.text.isEmpty })
        #expect(elements(cleared.windows.last?.content).contains { $0.kind == .label && $0.text == "Noch keine Begrüßung." })
    }

    @Test func windowSubclassesKeepIndependentControlsAndLiveMethodsAcrossImageLoad() async throws {
        let session = SmalltalkSession()
        let opened = await session.evaluate("""
        initializations := 0.
        UIWindow subclass: #GreetingWindow instanceVariableNames: 'nameField greeting'.
        GreetingWindow compile: 'initialize
            | column button |
            super initialize.
            initializations := initializations + 1.
            nameField := UITextField new.
            greeting := UILabel new.
            button := UIButton new.
            button title: ''Begrüßen''; action: [ self greet ].
            column := UIColumn new.
            column add: nameField; add: button; add: greeting.
            self content: column'.
        GreetingWindow compile: 'greet greeting text: ''Hallo, '', nameField text'.
        first := GreetingWindow new open.
        second := GreetingWindow new open.
        first open
        """)
        #expect(opened.error == nil)
        let windows = opened.windows.filter { $0.kind == .custom }
        #expect(windows.count == 2)
        #expect(Set(windows.map(\.id)).count == 2)
        let first = try #require(windows.first { $0.id == opened.activeWindowID })
        let field = try #require(elements(first.content).first { $0.kind == .textField })
        let button = try #require(elements(first.content).first { $0.kind == .button })
        _ = await session.uiAction(.text(windowID: first.id, elementID: field.id, value: "Moritz"))
        let compilation = await session.compile("greet greeting text: 'Neu: ', nameField text", in: "GreetingWindow")
        #expect(compilation.error == nil)
        let data = try await session.imageData()
        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(data)
        #expect(loaded.evaluation.error == nil)
        let count = await restored.evaluate("initializations")
        #expect(count.value == "2")
        let restoredFirst = try #require(loaded.evaluation.windows.first { $0.id == first.id })
        let restoredButton = try #require(elements(restoredFirst.content).first { $0.kind == .button })
        #expect(restoredButton.id != button.id)
        let stale = await restored.uiAction(.click(windowID: first.id, elementID: button.id))
        #expect(stale.error == nil)
        #expect(elements(stale.windows.first { $0.id == first.id }?.content).contains { $0.kind == .label && $0.text.isEmpty })
        let clicked = await restored.uiAction(.click(windowID: first.id, elementID: restoredButton.id))
        #expect(clicked.error == nil)
        #expect(elements(clicked.windows.first { $0.id == first.id }?.content).contains { $0.kind == .label && $0.text == "Neu: Moritz" })
        #expect(elements(clicked.windows.first { $0.kind == .custom && $0.id != first.id }?.content).contains { $0.kind == .textField && $0.text.isEmpty })
    }

    @Test func localVariablesCapturedByActionsSurviveImageLoad() async throws {
        let session = SmalltalkSession()
        let opened = await session.evaluate(SmalltalkExamples.legacyUserInterface)
        let window = try #require(opened.windows.first { $0.kind == .custom })
        let field = try #require(elements(window.content).first { $0.kind == .textField })
        _ = await session.uiAction(.text(windowID: window.id, elementID: field.id, value: "Gespeichert"))
        let data = try await session.imageData()
        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(data)
        let restoredWindow = try #require(loaded.evaluation.windows.first { $0.id == window.id })
        let button = try #require(elements(restoredWindow.content).first { $0.kind == .button && $0.text == "Begrüßen" })
        let clicked = await restored.uiAction(.click(windowID: window.id, elementID: button.id))
        #expect(clicked.error == nil)
        #expect(elements(clicked.windows.first { $0.id == window.id }?.content).contains { $0.kind == .label && $0.text == "Hallo, Gespeichert!" })
    }

    @Test func removedDisabledAndClosedControlsCannotDispatchStaleActions() async throws {
        let session = SmalltalkSession()
        let opened = await session.evaluate("""
        clicks := 0.
        field := UITextField new.
        button := UIButton new.
        button action: [ clicks := clicks + 1 ].
        column := UIColumn new.
        column add: field; add: button.
        window := UIWindow new.
        window content: column; open
        """)
        let window = try #require(opened.windows.first { $0.kind == .custom })
        let field = try #require(elements(window.content).first { $0.kind == .textField })
        let button = try #require(elements(window.content).first { $0.kind == .button })
        _ = await session.evaluate("column enabled: false")
        let ignoredText = await session.uiAction(.text(windowID: window.id, elementID: field.id, value: "ignored"))
        #expect(ignoredText.error == nil)
        let ignoredClick = await session.uiAction(.click(windowID: window.id, elementID: button.id))
        #expect(ignoredClick.error == nil)
        #expect(elements(ignoredClick.windows.last?.content).allSatisfy { !$0.enabled })
        _ = await session.evaluate("column enabled: true. column remove: button. replacement := UIButton new. replacement action: [ clicks := clicks + 10 ]. column add: replacement")
        let stale = await session.uiAction(.click(windowID: window.id, elementID: button.id))
        #expect(stale.error == nil)
        let newButton = try #require(elements(stale.windows.last?.content).first { $0.kind == .button })
        _ = await session.uiAction(.click(windowID: window.id, elementID: newButton.id))
        let count = await session.evaluate("clicks")
        #expect(count.value == "10")
        let text = await session.evaluate("field text")
        #expect(text.value == "''")
        _ = await session.windowAction(.close(window.id))
        _ = await session.uiAction(.click(windowID: window.id, elementID: newButton.id))
        let afterClose = await session.evaluate("clicks")
        #expect(afterClose.value == "10")
    }

    @Test func projectionDoesNotExecuteGettersAndNativeInputUsesLiveSetter() async throws {
        let session = SmalltalkSession()
        let opened = await session.evaluate("""
        reads := 0.
        UITextField subclass: #MarkedField instanceVariableNames: ''.
        MarkedField compile: 'text: aString super text: aString, ''!'''.
        UILabel compile: 'text reads := reads + 1. ^ ''wrong'''.
        label := UILabel new.
        label text: 'Original'.
        field := MarkedField new.
        column := UIColumn new.
        column add: label; add: field.
        window := UIWindow new.
        window content: column; open
        """)
        #expect(opened.error == nil)
        let window = try #require(opened.windows.first { $0.kind == .custom })
        #expect(elements(window.content).contains { $0.kind == .label && $0.text == "Original" })
        let field = try #require(elements(window.content).first { $0.kind == .textField })
        let edited = await session.uiAction(.text(windowID: window.id, elementID: field.id, value: "Neu"))
        #expect(edited.error == nil)
        #expect(elements(edited.windows.last?.content).contains { $0.id == field.id && $0.text == "Neu!" })
        let reads = await session.evaluate("reads")
        #expect(reads.value == "0")
    }

    @Test func invalidTreesAndActionFailuresAreReportedWithoutHanging() async throws {
        let session = SmalltalkSession()
        let opened = await session.evaluate("""
        column := UIColumn new.
        window := UIWindow new.
        window content: column; open
        """)
        #expect(opened.error == nil)
        let valid = try await session.imageData()
        let invalid = await session.evaluate("column add: column")
        #expect(invalid.error?.contains("Oberfläche") == true)
        #expect(invalid.executionError == nil)
        let flushed = await session.windowAction(.text(1, "column removeAll"))
        #expect(flushed.executionError == nil)
        await #expect(throws: SmalltalkError.self) { try await session.imageData() }
        var archive = try JSONDecoder().decode(ImageArchive.self, from: valid)
        let columnID = try #require(archive.nodes.firstIndex { node in
            if case .object(let object) = node { return object.className == "UIColumn" }
            return false
        })
        guard case .object(let column) = archive.nodes[columnID], case .reference(let childrenID)? = column.fields["children"] else {
            Issue.record("Column has no children array.")
            return
        }
        archive.nodes[childrenID] = .array([.reference(columnID)])
        let corrupt = try JSONEncoder().encode(archive)
        let current = SmalltalkSession()
        _ = await current.evaluate("kept := 42")
        await #expect(throws: SmalltalkError.self) { try await current.loadImage(corrupt) }
        let kept = await current.evaluate("kept")
        #expect(kept.value == "42")
        let repaired = await session.evaluate("column removeAll. button := UIButton new. button action: [ 1 / 0 ]. column add: button")
        #expect(repaired.error == nil)
        let window = try #require(repaired.windows.first { $0.kind == .custom })
        let button = try #require(elements(window.content).first { $0.kind == .button })
        let failed = await session.uiAction(.click(windowID: window.id, elementID: button.id))
        #expect(failed.error?.contains("Division durch null") == true)
        let recovered = await session.evaluate("button action: [ 6 * 7 ]")
        #expect(recovered.error == nil)
        let clicked = await session.uiAction(.click(windowID: window.id, elementID: button.id))
        #expect(clicked.error == nil)
        #expect(clicked.value == "42")
    }
}
