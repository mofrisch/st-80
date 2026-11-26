import Testing
@testable import SmalltalkCore

struct DebuggerTests {
    @Test(.timeLimit(.minutes(1)))
    func onlyAnUnhandledExceptionPausesTheDebuggerAsAnError() async throws {
        let session = SmalltalkSession()
        let handled = await session.debugSource("[ Error signal: 'handled' ] on: Error do: [ :exception | 42 ]")
        defer { handled.send(.stop) }
        var handledEvents = handled.events.makeAsyncIterator()
        #expect(try requirePause(await handledEvents.next()).reason == .entry)
        handled.send(.resume)
        let result = try requireResult(await handledEvents.next())
        #expect(result.value == "42")
        #expect(result.executionError == nil)

        let unhandled = await session.debugSource("Error signal: 'unhandled'")
        defer { unhandled.send(.stop) }
        var unhandledEvents = unhandled.events.makeAsyncIterator()
        #expect(try requirePause(await unhandledEvents.next()).reason == .entry)
        unhandled.send(.resume)
        let failure = try requirePause(await unhandledEvents.next())
        if case .error(let message) = failure.reason {
            #expect(message.contains("unhandled"))
        } else {
            Issue.record("Expected the debugger to pause on the unhandled exception.")
        }
        unhandled.send(.stop)
        #expect(try requireResult(await unhandledEvents.next()).executionError?.contains("unhandled") == true)
    }

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
        let custom = await session.compile("""
        command: title id: identifier send: command enabled: available
            | buttonTitle |
            buttonTitle := command = #resume ifTrue: [ 'Continue from the image' ] ifFalse: [ title ].
            ^ UIButton new title: buttonTitle; identifier: identifier; command: command; enabled: available; yourself
        """, in: "DebuggerPresentation", side: .classSide)
        try #require(custom.executionError == nil)
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
        #expect(try await paused.commandPhase(after: .stepInto, from: .paused) == .running)
        #expect(try await paused.commandPhase(after: .stepOut, from: .paused) == nil)

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

        let controls = try await paused.controlTree()
        #expect(control("debuggerContinue", in: controls)?.text == "Continue from the image")
        #expect(control("debuggerStepOut", in: controls)?.enabled == true)
        #expect(control("debuggerSource", in: controls)?.sourcePosition?.line == callee.line)
        #expect(control("debuggerVariables", in: controls)?.readOnly == true)
        let callerControls = try await paused.controlTree(selectedFrameID: workspace.id)
        #expect(control("debuggerFrameTitle", in: callerControls)?.text == "Workspace")
        let running = try await paused.controlTree(phase: .running)
        #expect(control("debuggerContinue", in: running)?.enabled == false)
        #expect(control("debuggerStop", in: running)?.enabled == true)
        #expect(try await paused.commandPhase(after: .stepOut, from: .paused) == .running)
        #expect(try await paused.commandPhase(after: .resume, from: .running) == nil)

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

        let controls = try await failure.controlTree()
        #expect(control("debuggerError", in: controls)?.text.contains("Division by zero") == true)
        #expect(control("debuggerStepInto", in: controls)?.enabled == false)
        #expect(control("debuggerStop", in: controls)?.text == "Close")
        #expect(try await failure.commandPhase(after: .resume, from: .paused) == nil)

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

    @Test(.timeLimit(.minutes(1)))
    func anInvalidDebuggerPresentationLeavesThePausedWorldIntact() async throws {
        let session = SmalltalkSession()
        let compiled = await session.compile("""
        contentFor: stack frame: frame error: error phase: phase
            debugPresentationProbe := 99.
            ^ nil
        """, in: "DebuggerPresentation", side: .classSide)
        try #require(compiled.executionError == nil)
        let setup = await session.evaluate("debugPresentationProbe := 42")
        try #require(setup.executionError == nil)

        let debugger = await session.debugSource("debugPresentationProbe := 0")
        defer { debugger.send(.stop) }
        var events = debugger.events.makeAsyncIterator()
        let paused = try requirePause(await events.next())
        do {
            _ = try await paused.controlTree()
            Issue.record("Expected the presentation to reject a write to a global in the paused world.")
        } catch let error as SmalltalkError {
            #expect(error.message == "Variable debugPresentationProbe is undeclared.")
        }

        debugger.send(.stop)
        let stopped = try requireResult(await events.next())
        #expect(stopped.executionError == "Debugging stopped.")
        #expect(stopped.value == nil)
        #expect(await session.evaluate("debugPresentationProbe").value == "42")

        let fresh = SmalltalkSession()
        let next = await fresh.debugSource("6 * 7")
        defer { next.send(.stop) }
        var nextEvents = next.events.makeAsyncIterator()
        let nextPause = try requirePause(await nextEvents.next())
        #expect(control("debuggerContinue", in: try await nextPause.controlTree())?.enabled == true)
        next.send(.resume)
        #expect(try requireResult(await nextEvents.next()).value == "42")
    }

    @Test(.timeLimit(.minutes(1)), arguments: [4_096, 4_097])
    func debuggerRendersAtTheVariableTableLimit(variableCount: Int) async throws {
        let longName = String(repeating: "🔧", count: 1_025)
        let variables = (0..<variableCount).map { index in
            DebuggerVariable(name: index == 0 ? longName : "local\(index)", value: String(index), className: "SmallInteger")
        }
        let frame = DebuggerFrame(id: 7, title: longName, source: "| temp |\n    temp := 42", line: 2, column: 5,
                                  instruction: "pushLiteral 42", variables: variables)
        let snapshot = DebuggerSnapshot(reason: .step, frames: [frame], presentation: nil)

        let root = try await snapshot.controlTree(selectedFrameID: -1, phase: .stopping)
        let stack = try #require(control("debuggerStack", in: root))
        #expect(stack.selection == "7")
        #expect(stack.enabled == false)
        let title = try #require(stack.historyEntries.first?.title)
        #expect(title.utf8.count <= 4_096)
        #expect(title.hasSuffix("…"))
        #expect(control("debuggerSource", in: root)?.sourcePosition?.column == 5)
        #expect(control("debuggerStop", in: root)?.enabled == false)

        let table = try #require(control("debuggerVariables", in: root))
        let rows = try #require(table.table?.rows)
        #expect(table.readOnly)
        #expect(rows.count == 4_096)
        #expect(rows.first?.name == title)
        #expect(rows.dropLast().last?.name == "local4094")
        if variableCount == 4_096 {
            #expect(rows.last?.name == "local4095")
            #expect(rows.last?.value == "4095")
        } else {
            #expect(rows.last?.name == "…")
            #expect(rows.last?.value == "2 more variables")
        }
    }

    private func control(_ id: String, in root: UIElementInfo) -> UIElementInfo? {
        if root.accessibilityID == id { return root }
        return root.children.lazy.compactMap { control(id, in: $0) }.first
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
