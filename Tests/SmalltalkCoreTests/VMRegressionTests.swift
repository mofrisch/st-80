import Testing
@testable import SmalltalkCore

struct VMRegressionTests {
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
        runtime.debuggerCancellation = channel
        channel.send(.stop)

        // Call the comparator directly so this cannot pass solely because
        // send() checks cancellation before entering the primitive.
        #expect(throws: (any Error).self) { try runtime.equal(.integer(1), .integer(1)) }
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
}
