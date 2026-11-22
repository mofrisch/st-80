import Testing
@testable import SmalltalkCore

@MainActor
struct SmalltalkCoreTests {
    private func value(_ source: String, in runtime: SmalltalkRuntime = SmalltalkRuntime()) -> String? {
        let result = runtime.run(source)
        #expect(result.error == nil, "\(result.error ?? "")")
        return result.value
    }

    @Test func bootstrapAndWorkspaceExample() {
        let runtime = SmalltalkRuntime()
        let result = runtime.run(SmalltalkExamples.workspace)
        #expect(result.error == nil)
        #expect(result.value == "5")
        #expect(result.transcript == "Hallo, Smalltalk!\nDer Zähler steht bei 5\n")
        #expect(result.bindings.contains { $0.name == "counter" && $0.className == "Counter" })
    }

    @Test func precedenceIsSmalltalkPrecedence() {
        #expect(value("3 + 4 * 2") == "14")
        #expect(value("3 + (4 * 2)") == "11")
        #expect(value("2 + 3 squared") == "11")
        #expect(value("3 + 4 > 6 ifTrue: [ 42 ] ifFalse: [ 0 ]") == "42")
    }

    @Test func assignmentsAndWorkspacePersistence() {
        let runtime = SmalltalkRuntime()
        #expect(value("a := b := 21", in: runtime) == "21")
        #expect(value("a + b", in: runtime) == "42")
        #expect(value("| local | local := 9. local", in: runtime) == "9")
        #expect(runtime.run("local").error?.contains("Unbekannte Variable") == true)
    }

    @Test func stringsCommentsSymbolsAndUnicode() {
        #expect(value("\"ignorieren\" 'Grüße 👋' size") == "7")
        #expect(value("'it''s ', 'alive'") == "'it''s alive'")
        #expect(value("#hello asString") == "'hello'")
        #expect(value("'Grüße' at: 3") == "'ü'")
        #expect(value("#(one #two 'three' (4 5))") == "#(#one #two 'three' #(4 5))")
    }

    @Test func cascadeUsesOneReceiverAndReturnsLastMessage() {
        let runtime = SmalltalkRuntime()
        #expect(value("Counter new increment; increment; value", in: runtime) == "2")
        #expect(value("Transcript show: 'a'; cr; show: 'b'", in: runtime) == "Transcript")
        #expect(runtime.transcript == "a\nb")
    }

    @Test func blocksCaptureMutableLexicalVariables() {
        #expect(value("| count increment | count := 0. increment := [ count := count + 1 ]. increment value. increment value. count") == "2")
        #expect(value("[ :a :b | | sum | sum := a + b. sum * 2 ] value: 3 value: 4") == "14")
    }

    @Test func escapingClosureRemainsUsable() {
        let runtime = SmalltalkRuntime()
        #expect(value("Counter compile: 'reader ^ [ count ]'. c := Counter new. read := c reader. c increment. read value", in: runtime) == "1")
        #expect(value("c increment. read value", in: runtime) == "2")
    }

    @Test func nonLocalReturnUnwindsNestedBlocks() {
        #expect(value("""
        Object subclass: #Finder instanceVariableNames: ''.
        Finder compile: 'find
            #(1 2 3) do: [ :each | each = 2 ifTrue: [ ^ each ] ].
            ^ 0'.
        Finder new find
        """) == "2")
        #expect(value("[ ^ 42 ] value. 0") == "42")
    }

    @Test func escapedNonLocalReturnReportsAnError() {
        let runtime = SmalltalkRuntime()
        _ = value("escaped := [ ^ 7 ]. 1", in: runtime)
        #expect(runtime.run("escaped value").error?.contains("Heimkontext") == true)
    }

    @Test func methodsDefaultToReceiverAndCanBeReplacedLive() {
        let runtime = SmalltalkRuntime()
        #expect(value("c := Counter new. c increment == c", in: runtime) == "true")
        #expect(value("Counter compile: 'value ^ count + 10'. c value", in: runtime) == "11")
        #expect(runtime.run("Counter compile: 'value ^ ('").error != nil)
        #expect(value("c value", in: runtime) == "11")
    }

    @Test func inheritanceFieldsAndSuperDispatch() {
        #expect(value("""
        Counter subclass: #DoubleCounter instanceVariableNames: 'extra'.
        DoubleCounter compile: 'initialize
            super initialize.
            extra := 10'.
        DoubleCounter compile: 'value ^ super value + extra'.
        c := DoubleCounter new.
        c increment.
        c value
        """) == "11")
    }

    @Test func booleanBranchesAreLazyAndLoopsUseBlocks() {
        #expect(value("false ifTrue: [ 1 / 0 ] ifFalse: [ 42 ]") == "42")
        #expect(value("false and: [ 1 / 0 ]") == "false")
        #expect(value("true or: [ 1 / 0 ]") == "true")
        #expect(value("| n | n := 0. [ n < 5 ] whileTrue: [ n := n + 1 ]. n") == "5")
        #expect(value("| sum | sum := 0. 5 to: 1 by: -2 do: [ :n | sum := sum + n ]. sum") == "9")
    }

    @Test func arraysAreMutableAndOneBased() {
        #expect(value("a := Array new: 2. a at: 1 put: 42. a at: 1") == "42")
        #expect(value("#(1 2 3) collect: [ :n | n squared ]") == "#(1 4 9)")
        #expect(value("#(1 2 3 4) select: [ :n | n > 2 ]") == "#(3 4)")
        #expect(SmalltalkRuntime().run("#(1) at: 0").error?.contains("Index 0") == true)
    }

    @Test func examplesExecute() {
        #expect(value(SmalltalkExamples.collections) == "55")
        #expect(value(SmalltalkExamples.classes) == "'Hallo, Moritz'")
        #expect(value(SmalltalkExamples.precedence) == "'Smalltalk läuft.'")
    }

    @Test func introspectionAndDynamicSend() {
        #expect(value("Counter superclass name") == "#Object")
        #expect(value("Counter new class name") == "#Counter")
        #expect(value("Counter new respondsTo: #increment") == "true")
        #expect(value("3 respondsTo: #+") == "true")
        #expect(value("3 perform: #+ with: 4") == "7")
        #expect(SmalltalkRuntime().run("3 perform: #+").error?.contains("Argumentzahl") == true)
    }

    @Test func arithmeticErrorsDoNotCrashTheSession() {
        let runtime = SmalltalkRuntime()
        #expect(runtime.run("1 / 0").error?.contains("Division durch null") == true)
        #expect(runtime.run("9223372036854775807 + 1").error?.contains("überlauf") == true)
        #expect(runtime.run("2 / 3").error?.contains("Brüche") == true)
        #expect(value("-7 // 3", in: runtime) == "-3")
        #expect(value("-7 \\\\ 3", in: runtime) == "2")
        #expect(value("6 * 7", in: runtime) == "42")
        #expect(value("-9223372036854775808", in: runtime) == "-9223372036854775808")
        #expect(runtime.run("-9223372036854775808 / -1").error?.contains("überlauf") == true)
    }

    @Test func badSyntaxIncludesSourcePosition() {
        let runtime = SmalltalkRuntime()
        #expect(runtime.run("1.\n(").error?.contains("Zeile 2") == true)
        #expect(runtime.run("'unterminated").error?.contains("String ist nicht geschlossen") == true)
        #expect(runtime.run("[ 1").error != nil)
        #expect(runtime.run("| a a | a").error != nil)
        #expect(runtime.run("| self | self").error != nil)
        #expect(runtime.run("Object := 3").error?.contains("überschrieben") == true)
    }

    @Test func executionAndNestingLimitsLeaveSessionUsable() {
        let runtime = SmalltalkRuntime()
        #expect(runtime.run("[ true ] whileTrue: [ ]").error != nil)
        #expect(runtime.run("Counter compile: 'loop ^ self loop'. Counter new loop").error?.contains("Aufruftiefe") == true)
        #expect(runtime.run(String(repeating: "(", count: 200) + "1" + String(repeating: ")", count: 200)).error?.contains("verschachtelt") == true)
        #expect(runtime.run("1" + String(repeating: " squared", count: 500)).error != nil)
        #expect(value("6 * 7", in: runtime) == "42")
    }

    @Test func cyclicArraysCanBeInspected() {
        let runtime = SmalltalkRuntime()
        let result = runtime.run("a := Array new: 1. a at: 1 put: a. a")
        #expect(result.error == nil)
        #expect(result.value?.contains("…") == true)
    }

    @Test func invalidClassDefinitionsAreRejected() {
        let runtime = SmalltalkRuntime()
        #expect(runtime.run("Object subclass: #Counter instanceVariableNames: ''").error != nil)
        #expect(runtime.run("Counter subclass: #Bad instanceVariableNames: 'count'").error != nil)
        #expect(runtime.run("Object subclass: #Bad instanceVariableNames: 'a. b'").error != nil)
        #expect(runtime.run("Integer subclass: #Bad instanceVariableNames: ''").error != nil)
    }

    @Test func actorAPICompilesAndResets() async {
        let session = SmalltalkSession()
        let first = await session.evaluate("c := Counter new. c increment. c value")
        #expect(first.value == "1")
        let compiled = await session.compile("value ^ count + 100", in: "Counter")
        #expect(compiled.error == nil)
        let second = await session.evaluate("c value")
        #expect(second.value == "101")
        _ = await session.reset()
        let missing = await session.evaluate("c")
        #expect(missing.error != nil)
        let fresh = await session.evaluate("Counter new value")
        #expect(fresh.value == "0")
        let nested = await session.evaluate(String(repeating: "(", count: 32) + "42" + String(repeating: ")", count: 32))
        #expect(nested.value == "42")
        let stopped = await session.evaluate("[ true ] whileTrue: [ ]")
        #expect(stopped.error?.contains("100.000") == true)
        let recovered = await session.evaluate("6 * 7")
        #expect(recovered.value == "42")
    }
}
