import Foundation
import Testing
@testable import SmalltalkCore

// Keep recursive interpreter calls on the main thread's larger stack while
// preserving Swift Testing's task-local assertion context.
@MainActor
struct GarbageCollectionTests {
    private let emptyBlock = BytecodeBody.lower(Body(temporaries: [], expressions: []))

    private func value(_ source: String, in runtime: SmalltalkRuntime) -> String? {
        let result = runtime.run(source)
        #expect(result.error == nil, "\(result.error ?? "")")
        return result.value
    }

    private func nodeClass(in runtime: SmalltalkRuntime) throws -> STClass {
        let parent = try #require(runtime.classes["Object"])
        let node = STClass("GCNode", superclass: parent, fields: ["next", "payload"])
        runtime.classes[node.name] = node
        runtime.globals[node.name] = .classObject(node)
        return node
    }

    @Test func unreachableMixedCyclesReleaseEveryManagedKind() throws {
        let runtime = SmalltalkRuntime(bootstrap: false)
        let node = try nodeClass(in: runtime)
        weak var deadObject: STObject?
        weak var deadArray: STArray?
        weak var deadBlock: STBlock?
        weak var deadEnvironment: Environment?
        do {
            let object = try runtime.object(node)
            guard case .array(let array) = try runtime.array([]) else {
                Issue.record("Expected an array.")
                return
            }
            let environment = try runtime.environment()
            let context = Context(environment: environment, receiver: .object(object), homeClass: node, homeID: 0, isWorkspace: false)
            let block = try runtime.block(parameters: [], body: emptyBlock, context: context)
            object.fields["payload"] = .array(array)
            array.elements = [.block(block), .array(array)]
            environment.values["cycle"] = .block(block)
            deadObject = object; deadArray = array; deadBlock = block; deadEnvironment = environment
        }
        let statistics = runtime.collectGarbage()
        #expect(statistics.liveNodes == 0)
        #expect(statistics.totalReclaimed == 4)
        #expect(deadObject == nil)
        #expect(deadArray == nil)
        #expect(deadBlock == nil)
        #expect(deadEnvironment == nil)
    }

    @Test func reachableCyclesKeepTheirContentsIdentityAndNativeHandles() throws {
        let runtime = SmalltalkRuntime(bootstrap: false)
        let node = try nodeClass(in: runtime)
        let object = try runtime.object(node)
        guard case .array(let array) = try runtime.array([.object(object)]) else {
            Issue.record("Expected an array.")
            return
        }
        object.fields["next"] = .object(object)
        object.fields["payload"] = .array(array)
        array.elements.append(.array(array))
        runtime.globals["kept"] = .object(object)
        let identity = ObjectIdentifier(object)
        let nativeID = object.nativeID
        let statistics = runtime.collectGarbage()
        #expect(statistics.liveObjects == 1)
        #expect(statistics.liveArrays == 1)
        guard case .object(let restored)? = runtime.globals["kept"],
              case .object(let next)? = restored.fields["next"],
              case .array(let payload)? = restored.fields["payload"],
              case .array(let alias) = payload.elements[1] else {
            Issue.record("The collector changed a reachable graph.")
            return
        }
        #expect(ObjectIdentifier(restored) == identity)
        #expect(restored.nativeID == nativeID)
        #expect(next === restored)
        #expect(payload === array && alias === array)
    }

    @Test func blockReceiverCyclesAreBrokenWithoutRelyingOnEnvironmentValues() throws {
        let runtime = SmalltalkRuntime(bootstrap: false)
        weak var deadBlock: STBlock?
        weak var deadEnvironment: Environment?
        do {
            let environment = try runtime.environment()
            let block = try runtime.block(parameters: [], body: emptyBlock, context: Context(environment: environment, receiver: .nilValue, homeClass: nil, homeID: 0, isWorkspace: true))
            block.context = Context(environment: environment, receiver: .block(block), homeClass: nil, homeID: 0, isWorkspace: true)
            deadBlock = block; deadEnvironment = environment
        }
        let statistics = runtime.collectGarbage()
        #expect(statistics.liveBlocks == 0 && statistics.liveEnvironments == 0)
        #expect(deadBlock == nil)
        #expect(deadEnvironment == nil)
    }

    @Test func temporaryRootsAndFactoryInputsSurviveCollectionBeforeEveryAllocation() throws {
        let runtime = SmalltalkRuntime(bootstrap: false)
        let node = try nodeClass(in: runtime)
        runtime.memory.stressCollection = true
        try runtime.withRoots { scope in
            let object = try runtime.object(node)
            object.fields["payload"] = .integer(42)
            // The only incoming reference is the factory's Swift argument here.
            let owner = try runtime.array([.object(object)])
            scope.add(owner)
            let parent = try runtime.environment()
            parent.values["owner"] = owner
            let child = try runtime.environment(parent: parent)
            // The block factory must protect both the new context and receiver.
            let block = try runtime.block(parameters: [], body: emptyBlock, context: Context(environment: child, receiver: .object(object), homeClass: node, homeID: 0, isWorkspace: true))
            scope.add(.block(block))
            let statistics = runtime.collectGarbage()
            #expect(statistics.liveNodes == 5)
            #expect(block.context.environment.parent === parent)
            guard case .integer(let payload)? = object.fields["payload"] else {
                Issue.record("A live factory input was cleared.")
                return
            }
            #expect(payload == 42)
        }
        #expect(runtime.collectGarbage().liveNodes == 0)
    }

    @Test func wideHeapRetainsEightyThousandObjectsAndRecoversAtTheHardLimit() throws {
        let runtime = SmalltalkRuntime(bootstrap: false)
        let leafClass = try nodeClass(in: runtime)
        let groupCount = 20
        let leavesPerGroup = 4_000
        let leafCount = groupCount * leavesPerGroup
        let arrayCount = groupCount + 1
        let retainedCount = leafCount + arrayCount
        let disposableCount = runtime.memory.hardLimit - retainedCount
        try #require(disposableCount > 0)

        guard case .array(let root) = try runtime.array([]) else {
            Issue.record("Expected a root array.")
            return
        }
        runtime.globals["forest"] = .array(root)
        for groupIndex in 0..<groupCount {
            guard case .array(let group) = try runtime.array([]) else {
                Issue.record("Expected a group array.")
                return
            }
            root.elements.append(.array(group))
            for leafIndex in 0..<leavesPerGroup {
                let leaf = try runtime.object(leafClass)
                leaf.fields["payload"] = .integer(Int64(groupIndex * leavesPerGroup + leafIndex))
                group.elements.append(.object(leaf))
            }
        }

        weak var disposableProbe: STObject?
        for index in 0..<disposableCount {
            let disposable = try runtime.object(leafClass)
            if index == 0 { disposableProbe = disposable }
        }
        let full = runtime.memory.statistics
        #expect(full.liveNodes == runtime.memory.hardLimit)
        #expect(disposableProbe != nil)

        _ = try runtime.object(leafClass)
        let recovered = runtime.memory.statistics
        #expect(recovered.totalCollections == full.totalCollections + 1)
        #expect(recovered.lastReclaimed == disposableCount)
        #expect(recovered.liveObjects == leafCount + 1)
        #expect(recovered.liveArrays == arrayCount)
        #expect(disposableProbe == nil)
        #expect(root.elements.count == groupCount)
        #expect(root.elements.enumerated().allSatisfy { groupIndex, value in
            guard case .array(let group) = value, group.elements.count == leavesPerGroup else { return false }
            return group.elements.enumerated().allSatisfy { leafIndex, value in
                guard case .object(let leaf) = value,
                      case .integer(let payload)? = leaf.fields["payload"] else { return false }
                return payload == Int64(groupIndex * leavesPerGroup + leafIndex)
            }
        })

        runtime.globals["forest"] = nil
        let released = runtime.collectGarbage()
        #expect(released.liveNodes == 0)
        #expect(released.lastReclaimed == retainedCount + 1)
    }

    @Test func deepChainSurvivesMarkingAndIsReleasedAfterRemovingItsRoot() throws {
        let runtime = SmalltalkRuntime(bootstrap: false)
        let nodeClass = try nodeClass(in: runtime)
        let chainLength = 50_000
        weak var tail: STObject?
        for index in 0..<chainLength {
            let node = try runtime.object(nodeClass)
            node.fields["next"] = runtime.globals["chain"] ?? .nilValue
            if index == 0 {
                node.fields["payload"] = .integer(42)
                tail = node
            }
            runtime.globals["chain"] = .object(node)
        }

        #expect(runtime.memory.statistics.totalCollections > 0)
        let retained = runtime.collectGarbage()
        #expect(retained.liveObjects == chainLength)
        #expect(retained.totalReclaimed == 0)
        do {
            var link = runtime.globals["chain"]
            var length = 0
            while length < chainLength, case .object(let node)? = link {
                length += 1
                link = node.fields["next"]
                if length == chainLength {
                    #expect(node === tail)
                    guard case .integer(42)? = node.fields["payload"] else {
                        Issue.record("The deepest node lost its payload.")
                        return
                    }
                }
            }
            #expect(length == chainLength)
            guard case .nilValue? = link else {
                Issue.record("The chain did not terminate with nil.")
                return
            }
        }

        runtime.globals["chain"] = nil
        let released = runtime.collectGarbage()
        #expect(released.liveNodes == 0)
        #expect(released.lastReclaimed == chainLength)
        #expect(tail == nil)
    }

    @Test func runtimeTeardownAlsoReleasesCyclesWithoutAnExplicitCollection() throws {
        weak var deadBlock: STBlock?
        weak var deadEnvironment: Environment?
        do {
            let runtime = SmalltalkRuntime(bootstrap: false)
            let environment = try runtime.environment()
            let block = try runtime.block(parameters: [], body: emptyBlock, context: Context(environment: environment, receiver: .nilValue, homeClass: nil, homeID: 0, isWorkspace: true))
            environment.values["cycle"] = .block(block)
            deadBlock = block; deadEnvironment = environment
            withExtendedLifetime(runtime) {}
        }
        #expect(deadBlock == nil)
        #expect(deadEnvironment == nil)
    }

    @Test func interpreterTemporariesAndClosuresSurviveStressCollection() {
        let runtime = SmalltalkRuntime()
        #expect(value("""
        Object subclass: #GCPair instanceVariableNames: 'payload'.
        GCPair compile: 'initialize payload := #(10 (20 30))'.
        GCPair compileClass: 'new ^ super new initialize; yourself'.
        GCPair compile: 'payload ^ payload'.
        GCPair compile: 'first: a with: b ^ a'.
        Counter compile: 'reader ^ [ count ]'.
        Object subclass: #GCFinder instanceVariableNames: ''.
        GCFinder compile: 'find #(1 2 3) do: [ :each | each = 2 ifTrue: [ ^ Counter new add: each; value ] ]. ^ 0'.
        42
        """, in: runtime) == "42")
        runtime.memory.stressCollection = true
        #expect(value("(GCPair new payload at: 2) at: 2", in: runtime) == "30")
        #expect(value("(GCPair new first: (Counter new add: 7) with: (Counter new add: 99)) value", in: runtime) == "7")
        #expect(value("Counter new increment; increment; value", in: runtime) == "2")
        #expect(value("#((1 (2 3)) ((4 5) 6))", in: runtime) == "#(#(1 #(2 3)) #(#(4 5) 6))")
        #expect(value("((#(1 2 3) collect: [ :n | Counter new add: n ]) at: 3) value", in: runtime) == "3")
        #expect(value("""
        | state |
        state := 0.
        increment := [ state := state + 1 ].
        read := [ state ].
        counter := Counter new add: 8.
        reader := counter reader.
        increment value.
        counter increment.
        read value + reader value
        """, in: runtime) == "10")
        _ = runtime.collectGarbage()
        #expect(value("increment value. read value + reader value", in: runtime) == "11")
        #expect(value("GCFinder new find", in: runtime) == "2")
        #expect(value("escaped := [ ^ 77 ]. 1", in: runtime) == "1")
        #expect(runtime.run("escaped value").error?.contains("home context") == true)
        #expect(value("6 * 7", in: runtime) == "42")
        #expect(runtime.memory.statistics.totalCollections > 0)
    }

    @Test func arrayCallbacksCanRemoveOriginalReferencesWithoutLosingCopiedElements() {
        let runtime = SmalltalkRuntime()
        runtime.memory.stressCollection = true
        #expect(value("""
        source := Array new: 3.
        source at: 1 put: (Counter new add: 7).
        source at: 2 put: (Counter new add: 11).
        source at: 3 put: (Counter new add: 13).
        chosen := source select: [ :each |
            source at: 1 put: nil; at: 2 put: nil; at: 3 put: nil.
            Counter new.
            true ].
        (chosen at: 1) value + (chosen at: 3) value
        """, in: runtime) == "20")
    }

    @Test func collectionRecoversSpaceInsideOneAllocationHeavyEvaluation() {
        let memory = ObjectMemory(hardLimit: 8_192, initialThreshold: 2_048)
        let runtime = SmalltalkRuntime(memory: memory)
        #expect(value("5000 timesRepeat: [ Counter new ]. 42", in: runtime) == "42")
        let statistics = runtime.collectGarbage()
        #expect(statistics.totalAllocated > 8_192)
        #expect(statistics.totalCollections > 0)
        #expect(statistics.liveNodes < 8_192)
    }

    @Test func errorUnwindingReleasesTemporaryRootsAndLeavesTheSessionUsable() {
        let runtime = SmalltalkRuntime()
        runtime.memory.stressCollection = true
        #expect(value("6 * 7", in: runtime) == "42")
        let before = runtime.collectGarbage().liveNodes
        for _ in 0..<5 {
            #expect(runtime.run("Counter new missingMessage: (Array new: 2)").error != nil)
            #expect(runtime.run("[ Counter new. 1 / 0 ] value").error?.contains("Division by zero") == true)
        }
        #expect(value("6 * 7", in: runtime) == "42")
        #expect(runtime.collectGarbage().liveNodes == before)
    }

    @Test func hardLimitRejectsOnlyAStillLiveHeapAfterCollection() throws {
        let runtime = SmalltalkRuntime(bootstrap: false, memory: ObjectMemory(hardLimit: 4, initialThreshold: 2))
        let node = try nodeClass(in: runtime)
        try runtime.withRoots { scope in
            for _ in 0..<4 {
                scope.add(.object(try runtime.object(node)))
            }
            #expect(throws: SmalltalkError.self) {
                _ = try runtime.object(node)
            }
            #expect(runtime.memory.statistics.liveObjects == 4)
            #expect(runtime.memory.statistics.totalCollections > 0)
        }
        #expect(runtime.collectGarbage().liveNodes == 0)
        _ = try runtime.object(node)
    }

    @Test func temporaryRootClosuresPreventUnsafeClassLayoutChanges() throws {
        let runtime = SmalltalkRuntime()
        #expect(value("""
        Object subclass: #GCRootedCapture instanceVariableNames: 'payload'.
        GCRootedCapture compile: 'capture ^ [ payload ]'
        """, in: runtime) == "#capture")
        let target = try #require(runtime.classes["GCRootedCapture"])
        let instance = try runtime.send(.classObject(target), "new", [])
        let captured = try runtime.send(instance, "capture", [])
        let revisedDefinition = "Object subclass: #GCRootedCapture instanceVariableNames: ''"
        try runtime.withRoots([captured]) { _ in
            // Only the retained block still uses the field after replacement.
            _ = try runtime.compile("capture ^ nil", in: target)
            do {
                try runtime.acceptDefinition(revisedDefinition, for: target)
                Issue.record("A closure held only by a temporary root lost its captured field.")
            } catch {
                #expect(error.localizedDescription.contains("live method or block"))
                #expect(error.localizedDescription.contains("payload"))
            }
            #expect(target.ownFields == ["payload"])
        }
        _ = runtime.collectGarbage()
        try runtime.acceptDefinition(revisedDefinition, for: target)
        #expect(target.ownFields.isEmpty)
    }

    @Test func nativeDisplayBatchesKeepPartiallyConstructedObjectsAliveUnderStress() throws {
        let runtime = SmalltalkRuntime()
        let initial = runtime.performWindowAction(.open(.workspace))
        let workspace = try #require(initial.windows.first { $0.kind == .workspace })
        let displays = [
            ScreenInfo(id: "left", frame: WindowRect(x: -1600, y: 0, width: 1600, height: 1000)),
            ScreenInfo(id: "main", frame: WindowRect(x: 0, y: 0, width: 1440, height: 900)),
            ScreenInfo(id: "upper", frame: WindowRect(x: 0, y: 1000, width: 1440, height: 900)),
        ]
        runtime.memory.stressCollection = true
        let before = runtime.memory.statistics.totalCollections
        let event = NativeWindowEvent(epoch: initial.windowCommands.epoch, sequence: 1, kind: .screens(displays))
        let result = runtime.performWindowEvents([event])
        #expect(result.error == nil, "\(result.error ?? "")")
        #expect(result.windows.map(\.id) == [workspace.id])
        #expect(result.activeWindowID == workspace.id)
        #expect(runtime.memory.statistics.totalCollections > before)
        _ = runtime.collectGarbage()
        let desktop = try #require(runtime.globals["Desktop"])
        guard case .array(let stored) = try runtime.send(desktop, "screens", []) else {
            Issue.record("The desktop lost its screen list.")
            return
        }
        #expect(stored.elements.count == displays.count)
        for (element, expected) in zip(stored.elements, displays) {
            guard case .object(let display) = element,
                  case .string(let id)? = display.fields["id"],
                  case .integer(let x)? = display.fields["x"],
                  case .integer(let y)? = display.fields["y"],
                  case .integer(let width)? = display.fields["width"],
                  case .integer(let height)? = display.fields["height"] else {
                Issue.record("A display collected before the batch was linked has empty fields.")
                return
            }
            #expect(id == expected.id)
            #expect(WindowRect(x: x, y: y, width: width, height: height) == expected.frame)
        }
        let collected = runtime.run("ToolVM collectGarbage")
        #expect(collected.error == nil, "\(collected.error ?? "")")
        #expect((Int(collected.value ?? "") ?? -1) >= 0)
        let statistics = runtime.run("ToolVM gcStatistics")
        #expect(statistics.error == nil, "\(statistics.error ?? "")")
        #expect(statistics.value?.contains("#nodes") == true)
        #expect(statistics.value?.contains("#collections") == true)
    }

    @Test func imageConstructionKeepsUnconnectedShellsAliveAndRestoredClosuresUsable() throws {
        let original = SmalltalkRuntime()
        #expect(value("""
        | state |
        saved := Array new: 4096.
        1 to: 4096 do: [ :index | saved at: index put: Counter new ].
        (saved at: 1) add: 7.
        (saved at: 4096) add: 11.
        saved at: 2 put: saved.
        state := 40.
        increment := [ state := state + 1 ].
        read := [ state ].
        42
        """, in: original) == "42")
        let data = try ImageCodec.encode(original, workspace: "draft", transcript: "history")
        let archive = try JSONDecoder().decode(ImageArchive.self, from: data)
        #expect(archive.nodes.count > 4_096)
        let (restored, contents) = try ImageCodec.decode(data)
        #expect(contents.workspace == "draft" && contents.transcript == "history")
        restored.memory.stressCollection = true
        _ = restored.collectGarbage()
        #expect(value("(saved at: 1) value + (saved at: 4096) value", in: restored) == "18")
        #expect(value("(saved at: 2) == saved", in: restored) == "true")
        #expect(value("increment value. increment value. read value", in: restored) == "42")
        let before = restored.collectGarbage().liveNodes
        restored.globals.removeValue(forKey: "saved")
        let after = restored.collectGarbage().liveNodes
        #expect(before - after >= 4_096)
    }
}
