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
        Observer compileClass: 'new ^ super new initialize; yourself'.
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
            #expect(elements(window.content).contains { $0.kind == .label && $0.text == "Hello, Ada 👋!" })
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
        #expect(elements(input.windows.last?.content).contains { $0.kind == .label && $0.text == "Hello, Grace!" })
        let writes = await session.evaluate("writes")
        #expect(writes.value == "1")
        let button = try #require(elements(window.content).first { $0.kind == .button && $0.text == "Use Example Name" })
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
        greetingModel silentName: 'Targeted'; changed: #name
        """)
        #expect(opened.error == nil)
        let window = try #require(opened.windows.first { $0.kind == .custom })
        #expect(elements(window.content).contains { $0.kind == .textField && $0.text == "Targeted" })
        #expect(elements(window.content).contains { $0.kind == .label && $0.text == "No greeting yet." })
        let greeting = await session.evaluate("greetingModel changed: #greeting")
        #expect(elements(greeting.windows.last?.content).contains { $0.kind == .label && $0.text == "Hello, Targeted!" })
        let rebound = await session.evaluate("label bind: #text to: greetingModel aspect: #name. greetingModel dependents size")
        #expect(rebound.error == nil)
        #expect(rebound.value == "2")
        let unbound = await session.evaluate("label unbind: #text. greetingModel name: 'New'. greetingModel dependents size")
        #expect(unbound.value == "1")
        #expect(elements(unbound.windows.last?.content).contains { $0.kind == .label && $0.text == "Targeted" })
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
        . greetingModel name: 'Saved'.
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
        let changed = await restored.evaluate("greetingModel name: 'After Restart'")
        #expect(changed.error == nil)
        #expect(elements(changed.windows.last?.content).contains { $0.kind == .label && $0.text == "Hello, After Restart!" })
        let window = try #require(changed.windows.first { $0.kind == .custom })
        let clear = try #require(elements(window.content).first { $0.kind == .button && $0.text == "Clear" })
        let clicked = await restored.uiAction(.click(windowID: window.id, elementID: clear.id))
        #expect(clicked.error == nil)
        #expect(elements(clicked.windows.last?.content).contains { $0.kind == .textField && $0.text.isEmpty })
    }

    @Test func restoredBindingsReconcileThroughTheImageHook() async throws {
        let donor = SmalltalkSession()
        try #require(await donor.evaluate(SmalltalkExamples.userInterface).error == nil)
        try #require(await donor.evaluate("mountChanges := 0").error == nil)
        try #require(await donor.compile("""
        reconcileMount: isMounted
            mountChanges := mountChanges + 1.
            isMounted ifTrue: [ ^ self connect ].
            ^ self disconnect
        """, in: "UIBinding").error == nil)
        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(donor.imageData())
        let window = try #require(loaded.evaluation.windows.first { $0.kind == .custom })
        #expect(loaded.evaluation.bindings.first { $0.name == "mountChanges" }?.value == "0")
        #expect(await restored.snapshot().bindings.first { $0.name == "mountChanges" }?.value == "0")
        #expect(await restored.evaluate("greetingModel dependents size").value == "2")

        let closed = await restored.windowAction(.close(window.id))
        #expect(closed.error == nil)
        #expect(closed.bindings.first { $0.name == "mountChanges" }?.value == "2")
        #expect(await restored.evaluate("greetingModel dependents size").value == "0")

        let opened = await restored.evaluate("greetingView open")
        #expect(opened.error == nil)
        #expect(opened.bindings.first { $0.name == "mountChanges" }?.value == "4")
        #expect(await restored.evaluate("greetingModel dependents size").value == "2")
    }

    @Test(arguments: [false, true])
    func imagesMissingTheBindingLifecycleMethodAreRejected(fileImage: Bool) async throws {
        let donor = SmalltalkSession()
        let current = SmalltalkSession()
        try #require(await current.evaluate("kept := 73").error == nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("st80-mvc-image-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let selector = "reconcileMount:"

        do {
            if fileImage {
                let url = directory.appendingPathComponent("Old.stimage")
                try await donor.saveImage(to: url, workspace: "", transcript: "")
                let archive = try decoder.decode(ImageFileArchive.self, from: Data(contentsOf: url))
                let methods = archive.methods.filter { $0.className != "UIBinding" || $0.code.selector != selector }
                try #require(methods.count == archive.methods.count - 1)
                let older = ImageFileArchive(memory: archive.memory, methods: methods,
                                             sourcesFile: archive.sourcesFile, sourcesID: archive.sourcesID,
                                             changesFile: archive.changesFile, changesID: archive.changesID,
                                             checkpoint: archive.checkpoint)
                try encoder.encode(older).write(to: url)
                _ = try await current.loadImage(from: url)
            } else {
                var archive = try await decoder.decode(ImageArchive.self, from: donor.imageData())
                let bindingClass = try #require(archive.classes.firstIndex { $0.name == "UIBinding" })
                archive.classes[bindingClass].methods.removeValue(forKey: selector)
                archive.executableMethods?["UIBinding"]?.removeValue(forKey: selector)
                _ = try await current.loadImage(encoder.encode(archive))
            }
            Issue.record("The image without a binding lifecycle method loaded.")
        } catch let error as SmalltalkError {
            #expect(error.message.contains("The image is missing UIBinding>>reconcileMount:"))
        }
        #expect(await current.evaluate("kept").value == "73")
    }

    @Test func existingInstancesJoinTheBindingIndexAfterReparenting() async throws {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
        Object subclass: #FutureBinding instanceVariableNames: ''.
        binding := FutureBinding new.
        ToolVM acceptDefinition: 'UIBinding subclass: #FutureBinding instanceVariableNames: ''''' in: FutureBinding basedOn: (ToolVM definitionOf: FutureBinding).
        binding initialize.
        model := Model new.
        binding source: model aspect: #isNil view: UILabel new property: #enabled.
        binding connect
        """)
        try #require(result.error == nil)
        #expect(await session.evaluate("FutureBinding superclass name").value == "#UIBinding")
        #expect(await session.evaluate("binding active").value == "false")
        #expect(await session.evaluate("model dependents size").value == "0")
    }

    @Test func theBindingIndexDoesNotKeepACollectedBindingAlive() async throws {
        let session = SmalltalkSession()
        try #require(await session.evaluate("temporaryBinding := UIBinding new").error == nil)
        let reclaimed = await session.worker.submit { runtime in
            weak var binding: STObject?
            if case .object(let object)? = runtime.globals.removeValue(forKey: "temporaryBinding") {
                binding = object
            }
            guard binding != nil else { return false }
            runtime.collectGarbage()
            return binding == nil
        }
        #expect(reclaimed)
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
        #expect(cycle.error?.contains("call depth") == true)
        let repaired = await session.evaluate("subject removeDependent: observer; changed")
        #expect(repaired.error == nil)
        let opened = await session.evaluate(SmalltalkExamples.userInterface)
        #expect(opened.error == nil)
        let invalid = await session.evaluate("GreetingModel compile: 'greeting ^ 42'. greetingModel changed")
        #expect(invalid.error != nil)
        let recovered = await session.evaluate("GreetingModel compile: 'greeting ^ ''Repaired'''. greetingModel changed")
        #expect(recovered.error == nil)
        #expect(elements(recovered.windows.last?.content).contains { $0.kind == .label && $0.text == "Repaired" })
    }
}
