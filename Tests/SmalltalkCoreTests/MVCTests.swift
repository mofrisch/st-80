import Foundation
import Testing
@testable import SmalltalkCore

@MainActor
struct MVCTests {
    private func elements(_ root: UIElementInfo?) -> [UIElementInfo] {
        guard let root else { return [] }
        return [root] + root.children.flatMap { elements($0) }
    }

    @Test func modelObserverProtocolDeduplicatesFiltersAndRemovesDependents() async throws {
        let session = SmalltalkSession()
        let created = await session.evaluate("""
        Object subclass: #Observer instanceVariableNames: 'updates aspect'.
        Observer compile: 'initialize updates := 0'.
        Observer compile: 'update: anAspect updates := updates + 1. aspect := anAspect'.
        Observer compile: 'updates ^ updates'.
        Observer compile: 'aspect ^ aspect'.
        subject := Model new.
        observer := Observer new.
        subject addDependent: observer; addDependent: observer; changed: #name.
        observer updates
        """)
        #expect(created.error == nil)
        #expect(created.value == "1")
        let aspect = await session.evaluate("observer aspect")
        #expect(aspect.value == "#name")
        let all = await session.evaluate("subject changed. observer aspect")
        #expect(all.value == "nil")
        let removed = await session.evaluate("subject removeDependent: observer; changed. observer updates")
        #expect(removed.value == "2")
    }

    @Test func directModelChangesRefreshTwoViewsWithoutControllerCalls() async throws {
        let session = SmalltalkSession()
        let opened = await session.evaluate(SmalltalkExamples.userInterface + """
        . secondView := GreetingView new.
        secondView model: greetingModel controller: greetingController; open
        """)
        #expect(opened.error == nil)
        #expect(opened.windows.filter { $0.kind == .custom }.count == 2)
        let changed = await session.evaluate("greetingModel name: 'Ada 👋'")
        #expect(changed.error == nil)
        for window in changed.windows.filter({ $0.kind == .custom }) {
            #expect(elements(window.content).contains { $0.kind == .textField && $0.liveInput && $0.text == "Ada 👋" })
            #expect(elements(window.content).contains { $0.kind == .label && $0.text == "Hallo, Ada 👋!" })
        }
        let dependencies = await session.evaluate("greetingModel dependents size")
        #expect(dependencies.value == "4")
    }

    @Test func controllerInputsAndButtonsUpdateModelWithoutFeedbackLoops() async throws {
        let session = SmalltalkSession()
        let opened = await session.evaluate(SmalltalkExamples.userInterface + """
        . writes := 0.
        GreetingModel compile: 'name: aString writes := writes + 1. name := aString. self changed'
        """)
        #expect(opened.error == nil)
        let window = try #require(opened.windows.first { $0.kind == .custom })
        let field = try #require(elements(window.content).first { $0.kind == .textField })
        let input = await session.uiAction(.text(windowID: window.id, elementID: field.id, value: "Grace"))
        #expect(input.error == nil)
        #expect(elements(input.windows.last?.content).contains { $0.kind == .label && $0.text == "Hallo, Grace!" })
        let writes = await session.evaluate("writes")
        #expect(writes.value == "1")
        let button = try #require(elements(window.content).first { $0.kind == .button && $0.text == "Beispielname" })
        let clicked = await session.uiAction(.click(windowID: window.id, elementID: button.id))
        #expect(clicked.error == nil)
        #expect(elements(clicked.windows.last?.content).contains { $0.id == field.id && $0.text == "Moritz" })
        let modelValue = await session.evaluate("greetingModel name")
        #expect(modelValue.value == "'Moritz'")
    }

    @Test func aspectNotificationsRebindingAndWindowLifecycleKeepObserversConsistent() async throws {
        let session = SmalltalkSession()
        let opened = await session.evaluate(SmalltalkExamples.userInterface + """
        . label := greetingView content children at: 3.
        GreetingModel compile: 'silentName: aString name := aString'.
        greetingModel silentName: 'Gezielt'; changed: #name
        """)
        #expect(opened.error == nil)
        let window = try #require(opened.windows.first { $0.kind == .custom })
        #expect(elements(window.content).contains { $0.kind == .textField && $0.text == "Gezielt" })
        #expect(elements(window.content).contains { $0.kind == .label && $0.text == "Noch keine Begrüßung." })
        let greeting = await session.evaluate("greetingModel changed: #greeting")
        #expect(elements(greeting.windows.last?.content).contains { $0.kind == .label && $0.text == "Hallo, Gezielt!" })
        let rebound = await session.evaluate("label bind: #text to: greetingModel aspect: #name. greetingModel dependents size")
        #expect(rebound.error == nil)
        #expect(rebound.value == "2")
        let unbound = await session.evaluate("label unbind: #text. greetingModel name: 'Neu'. greetingModel dependents size")
        #expect(unbound.value == "1")
        #expect(elements(unbound.windows.last?.content).contains { $0.kind == .label && $0.text == "Gezielt" })
        _ = await session.windowAction(.close(window.id))
        let closed = await session.evaluate("greetingModel name: 'Geschlossen'. greetingModel dependents size")
        #expect(closed.value == "0")
        let reopened = await session.evaluate("greetingView open. greetingModel dependents size")
        #expect(reopened.error == nil)
        let reconnected = await session.evaluate("greetingModel dependents size")
        #expect(reconnected.value == "1")
        #expect(elements(reopened.windows.last?.content).contains { $0.kind == .textField && $0.text == "Geschlossen" })
        let removed = await session.evaluate("greetingView content removeAll")
        #expect(removed.error == nil)
        let disconnected = await session.evaluate("greetingModel dependents size")
        #expect(disconnected.value == "0")
    }

    @Test func restoredBindingsAndControllersWorkWithoutRunningGettersDuringLoad() async throws {
        let original = SmalltalkSession()
        let opened = await original.evaluate(SmalltalkExamples.userInterface + """
        . greetingModel name: 'Gespeichert'.
        loadEffects := 0.
        GreetingModel compile: 'initialize loadEffects := loadEffects + 1. super initialize. name := '''''.
        GreetingModel compile: 'name loadEffects := loadEffects + 1. ^ name'
        """)
        #expect(opened.error == nil)
        let data = try await original.imageData()
        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(data)
        #expect(loaded.evaluation.error == nil)
        let effects = await restored.evaluate("loadEffects")
        #expect(effects.value == "0")
        let snapshot = await restored.snapshot()
        #expect(snapshot.error == nil)
        let stillNoEffects = await restored.evaluate("loadEffects")
        #expect(stillNoEffects.value == "0")
        let changed = await restored.evaluate("greetingModel name: 'Nach Neustart'")
        #expect(changed.error == nil)
        #expect(elements(changed.windows.last?.content).contains { $0.kind == .label && $0.text == "Hallo, Nach Neustart!" })
        let window = try #require(changed.windows.first { $0.kind == .custom })
        let clear = try #require(elements(window.content).first { $0.kind == .button && $0.text == "Leeren" })
        let clicked = await restored.uiAction(.click(windowID: window.id, elementID: clear.id))
        #expect(clicked.error == nil)
        #expect(elements(clicked.windows.last?.content).contains { $0.kind == .textField && $0.text.isEmpty })
    }

    @Test func corruptDependencyGraphsAreRejectedTransactionally() async throws {
        let donor = SmalltalkSession()
        _ = await donor.evaluate(SmalltalkExamples.userInterface)
        var archive = try await JSONDecoder().decode(ImageArchive.self, from: donor.imageData())
        let index = try #require(archive.nodes.firstIndex { node in
            if case .object(let object) = node { return object.className == "UIBinding" }
            return false
        })
        guard case .object(var binding) = archive.nodes[index] else { return }
        binding.fields["source"] = .integer(42)
        archive.nodes[index] = .object(binding)
        let current = SmalltalkSession()
        _ = await current.evaluate("kept := 73")
        await #expect(throws: SmalltalkError.self) { try await current.loadImage(JSONEncoder().encode(archive)) }
        let kept = await current.evaluate("kept")
        #expect(kept.value == "73")
    }

    @Test func observerCyclesAreBoundedAndInvalidBoundValuesCanRecover() async throws {
        let session = SmalltalkSession()
        let cycle = await session.evaluate("""
        Object subclass: #LoopObserver instanceVariableNames: 'subject'.
        LoopObserver compile: 'subject: aModel subject := aModel'.
        LoopObserver compile: 'update: anAspect subject changed'.
        subject := Model new.
        observer := LoopObserver new.
        observer subject: subject.
        subject addDependent: observer; changed
        """)
        #expect(cycle.error?.contains("Aufruftiefe") == true)
        let repaired = await session.evaluate("subject removeDependent: observer; changed")
        #expect(repaired.error == nil)
        let opened = await session.evaluate(SmalltalkExamples.userInterface)
        #expect(opened.error == nil)
        let invalid = await session.evaluate("GreetingModel compile: 'greeting ^ 42'. greetingModel changed")
        #expect(invalid.error != nil)
        let recovered = await session.evaluate("GreetingModel compile: 'greeting ^ ''Repariert'''. greetingModel changed")
        #expect(recovered.error == nil)
        #expect(elements(recovered.windows.last?.content).contains { $0.kind == .label && $0.text == "Repariert" })
    }
}
