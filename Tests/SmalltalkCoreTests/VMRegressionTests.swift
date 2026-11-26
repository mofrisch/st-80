import Foundation
import Testing
@testable import SmalltalkCore

struct VMRegressionTests {
    @Test func exceptionHandlerResultRemainsRootedDuringUnwind() async {
        let session = SmalltalkSession()
        let result = await session.worker.submit { runtime in
            runtime.memory.stressCollection = true
            return runtime.run("""
                [ [ Error signal ] ensure: [ ToolVM collectGarbage ] ]
                    on: Error do: [ :exception | Array with: 42 ]
                """)
        }
        #expect(result.executionError == nil)
        #expect(result.value == "#(42)")
    }

    @Test func exceptionTransferCrossesNestedToolEvaluation() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            [ ToolVM evaluateSource: 'Error signal: ''nested'''. 0 ]
                on: Error do: [ :exception | exception messageText ]
            """)
        #expect(result.executionError == nil)
        #expect(result.value == "'nested'")
        let returned = await session.evaluate("""
            [ ToolVM evaluateSource: 'Error signal'. 0 ] on: Error do: [ :exception | ^ 42 ]
            """)
        #expect(returned.executionError == nil)
        #expect(returned.value == "42")
    }

    private func sharedArrayGraph(levels: Int, in runtime: SmalltalkRuntime) throws -> Value {
        var graph: Value = .integer(1)
        for _ in 0..<levels { graph = try runtime.array([graph, graph]) }
        return graph
    }

    @Test func arrayEqualityComparesSharedBranchesWithLinearWork() throws {
        let runtime = SmalltalkRuntime(bootstrap: false)
        let levels = 18
        let left = try sharedArrayGraph(levels: levels, in: runtime)
        let right = try sharedArrayGraph(levels: levels, in: runtime)

        #expect(try runtime.equal(left, right))
        // Each level has only one distinct pair of arrays. The size of the
        // unfolded binary tree must not determine execution cost.
        #expect(runtime.steps > 0 && runtime.steps <= levels * 2 + 1)
        #expect(try !runtime.equal(left, right, identity: true))
        #expect(try runtime.equal(left, left, identity: true))
    }

    @Test func arrayEqualitySupportsDeepGraphsAndChecksBothMembersOfEachPair() throws {
        let runtime = SmalltalkRuntime(bootstrap: false)
        let left = try sharedArrayGraph(levels: 128, in: runtime)
        let right = try sharedArrayGraph(levels: 128, in: runtime)
        #expect(try runtime.equal(left, right))

        let shared = try runtime.array([.integer(1)])
        let repeated = try runtime.array([shared, shared])
        let different = try runtime.array([shared, runtime.array([.integer(2)])])
        #expect(try !runtime.equal(repeated, different))
    }

    @Test func arrayEqualityHandlesCyclesAndStillFindsUnequalContents() throws {
        let runtime = SmalltalkRuntime(bootstrap: false)
        let left = try runtime.array([.nilValue, .integer(7)])
        let right = try runtime.array([.nilValue, .integer(7)])
        guard case .array(let leftArray) = left, case .array(let rightArray) = right else {
            Issue.record("Expected arrays.")
            return
        }
        leftArray.elements[0] = left
        rightArray.elements[0] = right

        #expect(try runtime.equal(left, right))
        rightArray.elements[1] = .integer(8)
        #expect(try !runtime.equal(left, right))
    }

    @Test(arguments: ["=", "~=", "includes:"])
    func arrayComparisonsRespectTheExecutionBudget(_ selector: String) throws {
        let runtime = SmalltalkRuntime(bootstrap: false)
        let left = try runtime.array([.integer(1), .integer(2), .integer(3)])
        let right = try runtime.array([.integer(1), .integer(2), .integer(3)])
        let receiver = selector == "includes:" ? try runtime.array([left]) : left
        runtime.steps = 99_996

        do {
            _ = try runtime.send(receiver, selector, [right])
            Issue.record("Array comparison bypassed the execution budget.")
        } catch let error as SmalltalkError {
            #expect(error.message.contains("100,000 steps"))
        }
    }

    @Test func arrayComparisonChecksDebuggerCancellationInsideThePrimitive() throws {
        let runtime = SmalltalkRuntime(bootstrap: false)
        let (_, continuation) = AsyncStream<DebuggerEvent>.makeStream()
        defer { continuation.finish() }
        let channel = DebuggerChannel(continuation)
        runtime.executionCancellation = channel
        channel.send(.stop)

        // Call the comparator directly so this cannot pass solely because
        // send() checks cancellation before entering the primitive.
        #expect(throws: (any Error).self) { try runtime.equal(.integer(1), .integer(1)) }
    }

    @Test func largeIntegerArithmeticChargesTheExecutionBudgetBeforeCalculating() throws {
        let runtime = SmalltalkRuntime(bootstrap: false)
        let dividend = try #require(BigInteger.parseMagnitude(String(repeating: "9", count: 800), radix: 10) { _ in })
        let divisor = try #require(BigInteger.parseMagnitude(String(repeating: "7", count: 400), radix: 10) { _ in })
        let charge = runtime.chargeNumericWork
        let multiplication = #expect(throws: SmalltalkError.self) {
            try runtime.withToolExecutionBudget(64) { _ = try dividend.multiplied(by: divisor, charge: charge) }
        }
        let division = #expect(throws: SmalltalkError.self) {
            try runtime.withToolExecutionBudget(64) { _ = try dividend.divided(by: divisor, charge: charge) }
        }
        #expect(multiplication?.message.contains("64 steps") == true)
        #expect(division?.message.contains("64 steps") == true)
    }

    @Test func largeIntegerArithmeticChecksDebuggerCancellationAtTheLibraryBoundary() throws {
        let runtime = SmalltalkRuntime(bootstrap: false)
        let (_, continuation) = AsyncStream<DebuggerEvent>.makeStream()
        defer { continuation.finish() }
        let channel = DebuggerChannel(continuation)
        runtime.executionCancellation = channel
        channel.send(.stop)

        let integer = BigInteger(Int64.max)
        #expect(throws: (any Error).self) {
            try integer.multiplied(by: integer, charge: runtime.chargeNumericWork)
        }
    }

    private func removePayload(in session: SmalltalkSession) async -> EvaluationResult {
        await session.evaluate("""
            ToolVM acceptDefinition: 'Object subclass: #MigrationOwner instanceVariableNames: '''''
                in: MigrationOwner basedOn: (ToolVM definitionOf: MigrationOwner)
            """)
    }

    @Test func classMigrationIgnoresUnreachableInstancesWithoutAnExplicitCollection() async throws {
        let session = SmalltalkSession()
        let prepared = await session.evaluate("""
            Object subclass: #MigrationOwner instanceVariableNames: 'payload'.
            MigrationOwner compile: 'fill payload := 42'.
            [ MigrationOwner new fill ] value.
            MigrationOwner compile: 'fill ^ self'.
            nil
            """)
        try #require(prepared.executionError == nil)

        let edited = await removePayload(in: session)
        #expect(edited.executionError == nil)
        #expect(edited.value?.hasPrefix("#(true ") == true)
        #expect(edited.classes.first { $0.name == "MigrationOwner" }?.fields == [])
    }

    @Test func classMigrationStillProtectsAReachableInstanceAndSucceedsAfterItIsReleased() async throws {
        let session = SmalltalkSession()
        let prepared = await session.evaluate("""
            Object subclass: #MigrationOwner instanceVariableNames: 'payload'.
            MigrationOwner compile: 'fill payload := 42'.
            live := MigrationOwner new fill.
            MigrationOwner compile: 'fill ^ self'.
            nil
            """)
        try #require(prepared.executionError == nil)

        let rejected = await removePayload(in: session)
        #expect(rejected.value?.hasPrefix("#(false ") == true)
        #expect(rejected.value?.contains("still holds a value") == true)
        #expect(rejected.classes.first { $0.name == "MigrationOwner" }?.fields == ["payload"])
        #expect(await session.evaluate("live printString").value == "'a MigrationOwner (payload: 42)'")

        try #require(await session.evaluate("live := nil").executionError == nil)
        let accepted = await removePayload(in: session)
        #expect(accepted.value?.hasPrefix("#(true ") == true)
        #expect(accepted.classes.first { $0.name == "MigrationOwner" }?.fields == [])
    }

    // MARK: - Interpreter stack budget

    /// Runs on a thread with the interpreter worker's stack, so a stack overflow
    /// crashes the test process exactly as it would crash the app.
    private func onWorkerStack<T>(_ body: @escaping @Sendable () throws -> T) throws -> T {
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<T, Error>?
        let thread = Thread {
            result = Result { try body() }
            done.signal()
        }
        thread.stackSize = InterpreterWorker.stackSize
        thread.start()
        done.wait()
        return try result!.get()
    }

    @Test func compilingTheDeepestSourceAtTheDeepestCallFitsTheWorkerStack() throws {
        let nesting = 32 // The Smalltalk compiler's source nesting limit.
        let deepest = String(repeating: "[", count: nesting) + "1" + String(repeating: "]", count: nesting)
        let tooDeep = "[" + deepest + "]"
        let results = try onWorkerStack { () -> [EvaluationResult] in
            let runtime = SmalltalkRuntime()
            let setup = runtime.run("""
                Object subclass: #StackProbe instanceVariableNames: ''.
                StackProbe compile: 'down: n source: aString
                    n = 0 ifTrue: [ ^ StackProbe compile: aString ].
                    ^ self down: n - 1 source: aString'.
                nil
                """)
            return [
                setup,
                // 124 is the deepest call at which compile: still runs; 125 hits the
                // 128-frame limit first.
                runtime.run("StackProbe new down: 124 source: 'deep ^ \(deepest)'"),
                runtime.run("StackProbe new deep value"),
                runtime.run("StackProbe new down: 125 source: 'deeper ^ 1'"),
                runtime.run("StackProbe new down: 0 source: 'tooDeep ^ \(tooDeep)'"),
            ]
        }
        #expect(results[0].executionError == nil, "\(results[0].executionError ?? "")")
        #expect(results[1].value == "#deep", "\(results[1].error ?? "")")
        #expect(results[2].executionError == nil, "\(results[2].error ?? "")")
        #expect(results[3].error?.contains("Maximum call depth") == true)
        // The nesting limit is what bounds the compiler's recursion. If it is raised,
        // revisit this test together with the worker stack size.
        #expect(results[4].error?.contains("nesting limit of 32") == true)
    }

    @Test func compilerModeRecursionStopsAtItsDepthLimitWithoutOverflowingTheWorkerStack() throws {
        // Block-heavy recursion costs more native stack per Smalltalk frame than a
        // plain send, much like the compiler's own recursive descent.
        let sources = [
            "loop ^ self loop",
            "loop ^ true ifTrue: [ true ifTrue: [ self loop ] ]",
            "loop ^ [ :x | [ :y | self loop ] value: x ] value: 1",
        ]
        for source in sources {
            let message = try onWorkerStack { () -> String in
                let method = try SmalltalkRuntime().compileMethod(source)
                let runtime = SmalltalkRuntime(bootstrap: false, compilationMode: true)
                guard let object = runtime.classes["Object"] else { return "Object is missing" }
                let probe = STClass("DepthProbe", superclass: object, fields: [])
                probe.classMethods[method.selector] = method
                runtime.classes[probe.name] = probe
                runtime.globals[probe.name] = .classObject(probe)
                do {
                    _ = try runtime.send(.classObject(probe), "loop", [])
                    return "no error"
                } catch {
                    return error.localizedDescription
                }
            }
            #expect(message.contains("Maximum call depth"), "\(source): \(message)")
        }
    }
}
