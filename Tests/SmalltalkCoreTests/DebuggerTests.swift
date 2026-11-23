import Testing
@testable import SmalltalkCore

struct DebuggerTests {
    @Test(.timeLimit(.minutes(1)))
    func debuggerStepsThroughACompiledMethodAndPreservesItsSideEffects() async throws {
        let session = SmalltalkSession()
        let method = """
        probe: amount
            | local |
            local := amount + 1.
            self increment.
            ^ self value + local
        """
        let compiled = await session.compile(method, in: "Counter")
        try #require(compiled.executionError == nil)
        let prepared = await session.evaluate("debugCounter := Counter new")
        try #require(prepared.executionError == nil)

        let source = """
        | answer |
        answer := debugCounter probe: 40.
        answer + debugCounter value
        """
        let debugger = await session.debugSource(source)
        defer { debugger.send(.stop) }
        var events = debugger.events.makeAsyncIterator()
        var paused = try requirePause(await events.next())

        guard case .entry = paused.reason else {
            throw SmalltalkError("Expected the debugger to pause at the entry point.")
        }
        let workspace = try #require(paused.frames.first)
        #expect(paused.frames.count == 1)
        #expect(workspace.source == source)
        #expect(workspace.line == 2)
        #expect(workspace.variables.first { $0.name == "answer" }?.value == "nil")

        for _ in 0..<16 where paused.frames.count == 1 {
            debugger.send(.stepInto)
            paused = try requirePause(await events.next())
        }
        let callee = try #require(paused.frames.first)
        guard case .step = paused.reason else {
            throw SmalltalkError("Expected the debugger to pause after a step.")
        }
        #expect(paused.frames.count == 2)
        #expect(paused.frames.last?.id == workspace.id)
        #expect(callee.title.contains("Counter") && callee.title.contains("probe:"))
        #expect(callee.source == method)
        #expect(callee.line == 3)
        #expect(callee.variables.first { $0.name == "self" }?.className == "Counter")
        #expect(callee.variables.first { $0.name == "amount" }?.value == "40")
        #expect(callee.variables.first { $0.name == "local" }?.value == "nil")

        // Step over the entire line that sends increment, even if the source
        // locations before and after its send use different columns.
        for _ in 0..<16 where (paused.frames.first?.line ?? 0) < 5 {
            debugger.send(.stepOver)
            paused = try requirePause(await events.next())
            #expect(paused.frames.first?.id == callee.id)
            #expect(paused.frames.count == 2)
        }
        let returning = try #require(paused.frames.first)
        #expect(returning.line == 5)
        #expect(returning.variables.first { $0.name == "local" }?.value == "41")

        debugger.send(.stepOut)
        let caller = try requirePause(await events.next())
        #expect(caller.frames.map(\.id) == [workspace.id])

        debugger.send(.resume)
        let finished = try requireResult(await events.next())
        #expect(finished.executionError == nil)
        #expect(finished.value == "43")
        #expect(await events.next() == nil)
        #expect(await session.evaluate("debugCounter value").value == "1")
    }

    @Test(.timeLimit(.minutes(1)))
    func stoppingAndDismissingAnErrorBothReleaseTheInterpreter() async throws {
        let session = SmalltalkSession()
        let prepared = await session.evaluate("debugCounter := Counter new")
        try #require(prepared.executionError == nil)
        let cancelled = await session.debugSource("debugCounter increment")
        defer { cancelled.send(.stop) }
        var cancelledEvents = cancelled.events.makeAsyncIterator()
        _ = try requirePause(await cancelledEvents.next())

        let queued = Task { await session.evaluate("debugCounter value") }
        cancelled.send(.stop)
        let stopped = try requireResult(await cancelledEvents.next())
        #expect(stopped.value == nil)
        #expect(await queued.value.value == "0")

        let method = """
        faulty: dividend
            | divisor |
            divisor := 0.
            ^ dividend / divisor
        """
        let compiled = await session.compile(method, in: "Counter")
        try #require(compiled.executionError == nil)
        let failing = await session.debugSource("debugCounter faulty: 42")
        defer { failing.send(.stop) }
        var failingEvents = failing.events.makeAsyncIterator()
        let entry = try requirePause(await failingEvents.next())
        failing.send(.resume)
        let failure = try requirePause(await failingEvents.next())
        let frame = try #require(failure.frames.first)
        if case .error(let message) = failure.reason {
            #expect(message.contains("Division by zero"))
        } else {
            Issue.record("Expected a debugger pause at the runtime error.")
        }
        #expect(failure.frames.count == 2)
        #expect(failure.frames.last?.id == entry.frames.first?.id)
        #expect(frame.title.contains("faulty:"))
        #expect(frame.line == 4)
        #expect(frame.source == method)
        #expect(frame.variables.first { $0.name == "dividend" }?.value == "42")
        #expect(frame.variables.first { $0.name == "divisor" }?.value == "0")

        failing.send(.stop)
        let finished = try requireResult(await failingEvents.next())
        #expect(finished.executionError?.contains("Division by zero") == true)
        #expect(await session.evaluate("6 * 7").value == "42")
    }

    @Test(.timeLimit(.minutes(1)))
    func debuggerShowsTheOriginAndCapturedBindingsOfAnEscapingBlock() async throws {
        let session = SmalltalkSession()
        let source = """
        | captured |
        captured := Counter new add: 40; yourself.
        debugAction := [ :delta |
            ToolVM collectGarbage.
            captured add: delta.
            captured value ]
        """
        let prepared = await session.evaluate(source)
        try #require(prepared.executionError == nil)

        let debugger = await session.debugSource("debugAction value: 2")
        defer { debugger.send(.stop) }
        var events = debugger.events.makeAsyncIterator()
        var paused = try requirePause(await events.next())
        for _ in 0..<16 where paused.frames.count == 1 {
            debugger.send(.stepInto)
            paused = try requirePause(await events.next())
        }
        let block = try #require(paused.frames.first)
        #expect(paused.frames.count == 2)
        #expect(block.source == source)
        #expect(block.line == 4)
        #expect(block.variables.first { $0.name == "captured" }?.className == "Counter")
        #expect(block.variables.first { $0.name == "delta" }?.value == "2")

        debugger.send(.resume)
        let finished = try requireResult(await events.next())
        #expect(finished.executionError == nil)
        #expect(finished.value == "42")
    }

    private func requirePause(_ event: DebuggerEvent?) throws -> DebuggerSnapshot {
        let event = try #require(event)
        if case .paused(let snapshot) = event { return snapshot }
        throw SmalltalkError("Expected a debugger pause, but the evaluation finished.")
    }

    private func requireResult(_ event: DebuggerEvent?) throws -> EvaluationResult {
        let event = try #require(event)
        if case .finished(let result) = event { return result }
        throw SmalltalkError("Expected the debugger evaluation to finish.")
    }
}
