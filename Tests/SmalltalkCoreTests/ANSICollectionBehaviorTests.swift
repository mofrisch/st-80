import Testing
import SmalltalkCore

struct ANSICollectionBehaviorTests {
    @Test func collectionCallbacksAcceptValuableObjects() async throws {
        let session = try await sessionWithCallback()
        let result = await session.evaluate("""
            | values transformer predicate recorder visited |
            values := #(1 2 3).
            transformer := ANSICallback new action: [ :each | each + 10 ].
            predicate := ANSICallback new action: [ :each | each odd ].
            visited := OrderedCollection new.
            recorder := ANSICallback new action: [ :each | visited add: each ].
            values do: recorder.
            'éa' do: recorder.
            #cat do: recorder.
            Array with: (values collect: transformer)
                with: (values select: predicate)
                with: visited asArray
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(#(11 12 13) #(1 3) #(1 2 3 $é $a $c $a $t))")
    }

    @Test func booleanAndLoopOperationsAcceptNiladicValuableObjects() async throws {
        let session = try await sessionWithCallback()
        let result = await session.evaluate("""
            | times callback first shortCircuited second |
            times := 0.
            callback := ANSICallback new action: [ times := times + 1. true ].
            first := true or: callback.
            shortCircuited := times = 0.
            second := false or: callback.
            [ times < 3 ] whileTrue: callback.
            [ times = 5 ] whileFalse: callback.
            Array with: first with: shortCircuited with: second with: times
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(true true true 5)")
    }

    @Test func subsequenceSearchHandlesEmptyTargetsAndOnlyAcceptsValidStartIndices() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | values missing outOfRange |
            values := #(1 2 3).
            missing := values indexOfSubCollection: #() startingAt: 1 ifAbsent: [ #missing ].
            outOfRange := [ values indexOfSubCollection: #(3) startingAt: 4
                ifAbsent: [ #unexpected ] ] on: Error do: [ :error | #invalidIndex ].
            Array with: (values indexOfSubCollection: #() startingAt: 2)
                with: missing with: outOfRange
                with: (values indexOfSubCollection: #(3) startingAt: 3)
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(0 #missing #invalidIndex 3)")
        #expect(await session.evaluate("#(1) indexOfSubCollection: #(1) startingAt: 0").error != nil)
        #expect(await session.evaluate("#() indexOfSubCollection: #() startingAt: 1").error != nil)
        #expect(await session.evaluate("#(1 1) copyReplaceAll: #(1) with: #(2 3)").value == "#(2 3 2 3)")
        #expect(await session.evaluate("#() copyReplaceAll: #(1) with: #(2)").value == "#()")
    }

    @Test func characterAsStringReturnsAnIndependentWritableStringAndDigitsAreDecimalLiterals() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | first second separate digitFlags |
            first := $é asString.
            second := $é asString.
            separate := first ~~ second.
            first at: 1 put: $x.
            digitFlags := Array with: ($0 isDigit and: [ $9 isDigit ])
                with: $٣ isDigit with: $٣ isAlphaNumeric with: $é isAlphaNumeric.
            Array with: first with: second with: separate with: digitFlags
            """)
        #expect(result.error == nil)
        #expect(result.value == "#('x' 'é' true #(true false false true))")
    }

    private func sessionWithCallback() async throws -> SmalltalkSession {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            Object subclass: #ANSICallback instanceVariableNames: 'action'.
            ANSICallback compile: 'action: aBlock action := aBlock'.
            ANSICallback compile: 'argumentCount ^ action argumentCount'.
            ANSICallback compile: 'value ^ action value'.
            ANSICallback compile: 'value: argument ^ action value: argument'.
            ANSICallback compile: 'valueWithArguments: arguments ^ action valueWithArguments: arguments'
            """)
        try #require(result.error == nil, "\(result.error ?? "")")
        return session
    }
}
