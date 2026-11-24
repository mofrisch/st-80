import Testing
@testable import SmalltalkCore

@MainActor
struct BytecodeTests {
    private func interpreters() -> (bytecode: SmalltalkRuntime, reference: SmalltalkRuntime) {
        let reference = SmalltalkRuntime()
        reference.useASTInterpreterForTesting = true
        return (SmalltalkRuntime(), reference)
    }

    private func compare(
        _ source: String, expected: String,
        using interpreters: (bytecode: SmalltalkRuntime, reference: SmalltalkRuntime)
    ) {
        let reference = interpreters.reference.run(source)
        let bytecode = interpreters.bytecode.run(source)
        #expect(reference.error == nil, "\(reference.error ?? "")")
        #expect(bytecode.error == nil, "\(bytecode.error ?? "")")
        #expect(bytecode.value == expected)
        #expect(bytecode.value == reference.value)
        #expect(bytecode.transcript == reference.transcript)
    }

    @Test func bytecodeMatchesTheASTForCascadesAndLexicalSuperDispatch() {
        compare("""
        Counter subclass: #BytecodeParent instanceVariableNames: ''.
        BytecodeParent subclass: #BytecodeChild instanceVariableNames: ''.
        BytecodeChild subclass: #BytecodeGrandchild instanceVariableNames: ''.
        BytecodeParent compile: 'value ^ super value + 10'.
        BytecodeChild compile: 'value ^ super value * 2'.
        BytecodeParent compileClass: 'answer ^ 30'.
        BytecodeChild compileClass: 'answer ^ super answer + 12'.
        BytecodeChild compileClass: 'reader ^ [ super answer ]'.
        calls := 0.
        make := [ calls := calls + 1. BytecodeGrandchild new ].
        number := (make value) increment; increment; value.
        results := Array new: 4.
        results at: 1 put: number; at: 2 put: calls;
            at: 3 put: BytecodeGrandchild answer;
            at: 4 put: BytecodeGrandchild reader value.
        results
        """, expected: "#(24 1 42 30)", using: interpreters())
    }

    @Test func bytecodeMatchesTheASTForEscapingClosuresAndNonlocalReturns() {
        let modes = interpreters()
        compare("""
        | total |
        total := 40.
        increment := [ total := total + 1 ].
        reader := [ total ].
        changed := 0.
        escaped := [ ^ (changed := 99) ].
        Object subclass: #BytecodeReturnProbe instanceVariableNames: ''.
        BytecodeReturnProbe compile: 'find
            #(1 2 3) do: [ :each | each = 2 ifTrue: [ ^ each + 40 ] ].
            ^ 0'.
        BytecodeReturnProbe new find
        """, expected: "42", using: modes)
        compare("increment value. increment value. reader value", expected: "42", using: modes)
        compare("1 + ([ 2 + (^ 42) ] value). 0", expected: "42", using: modes)

        let referenceError = modes.reference.run("escaped value").error
        let bytecodeError = modes.bytecode.run("escaped value").error
        #expect(bytecodeError?.contains("home context") == true)
        #expect(bytecodeError == referenceError)
        compare("changed", expected: "0", using: modes)
    }

    @Test func bytecodeReportsTheSameSourcePositionForRuntimeErrors() {
        let modes = interpreters()
        let source = "1.\n  missingBinding"
        let referenceError = modes.reference.run(source).error
        let bytecodeError = modes.bytecode.run(source).error
        #expect(bytecodeError?.hasPrefix("Line 2, column 3:") == true)
        #expect(bytecodeError == referenceError)
        compare("6 * 7", expected: "42", using: modes)
    }

    @Test func bytecodePreservesArgumentOrderAndSkipsLaterArgumentsOnError() {
        let modes = interpreters()
        compare("""
        Counter compile: 'sum: left with: right ^ left + right'.
        order := 0.
        receiver := [ order := order * 10 + 1. Counter new ].
        first := [ order := order * 10 + 2. 40 ].
        second := [ order := order * 10 + 3. 2 ].
        answer := receiver value sum: first value with: second value.
        (Array new: 2) at: 1 put: answer; at: 2 put: order; yourself
        """, expected: "#(42 123)", using: modes)

        let failing = "order := 0. receiver value sum: (first value / 0) with: second value"
        let expected = modes.reference.run(failing)
        let actual = modes.bytecode.run(failing)
        #expect(actual.executionError?.contains("Division by zero") == true)
        #expect(actual.executionError == expected.executionError)
        compare("order", expected: "12", using: modes)
    }

    @Test func collectionKeepsPendingBytecodeReceiversAndArgumentsAlive() {
        let runtime = SmalltalkRuntime()
        let result = runtime.run("""
        Object subclass: #BytecodeRootProbe instanceVariableNames: 'total'.
        BytecodeRootProbe compile: 'initialize total := 0'.
        BytecodeRootProbe compile: 'add: counter after: ignored total := total + counter value'.
        BytecodeRootProbe compile: 'value ^ total'.
        BytecodeRootProbe new
            add: (Counter new add: 40) after: (ToolVM collectGarbage);
            add: (Counter new add: 2) after: (ToolVM collectGarbage);
            value
        """)
        #expect(result.error == nil, "\(result.error ?? "")")
        #expect(result.value == "42")
    }

    @Test func bytecodeValidationRejectsMalformedPrograms() throws {
        let position = SourcePosition(line: 1, column: 1)
        func tape(_ operations: [BytecodeOperation], temporaries: [String] = []) -> BytecodeBody {
            BytecodeBody(temporaries: temporaries, instructions: operations.map {
                BytecodeInstruction(operation: $0, position: position)
            })
        }

        let valid = tape([.load("self"), .prepareSend(isSuper: false), .send("yourself"), .finish])
        try valid.validate(parameters: [])
        let invalid: [(String, BytecodeBody)] = [
            ("stack underflow", tape([.pop, .finish])),
            ("missing prepared receiver", tape([.load("self"), .send("yourself"), .finish])),
            ("missing message argument", tape([.load("self"), .prepareSend(isSuper: false), .send("at:"), .finish])),
            ("prepared receiver escapes as a value", tape([.load("self"), .prepareSend(isSuper: false), .finish])),
            ("duplicate block parameter", tape([.makeBlock(["arg", "arg"], valid), .finish])),
            ("parameter redeclared as a temporary", tape([.makeBlock(["arg"], tape([.load("nil"), .finish], temporaries: ["arg"])), .finish])),
            ("invalid source position", BytecodeBody(temporaries: [], instructions: [
                BytecodeInstruction(operation: .load("nil"), position: SourcePosition(line: 0, column: 1)),
                BytecodeInstruction(operation: .finish, position: position),
            ])),
        ]
        for (reason, body) in invalid {
            #expect(throws: SmalltalkError.self, "\(reason)") {
                try body.validate(parameters: [])
            }
        }
    }
}
