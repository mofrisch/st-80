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

    @Test func intervalSlicesIncludeBothBoundsAndAllowReversedIndices() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | interval |
            interval := 30 to: 10 by: -10.
            Array with: (interval copyFrom: 1 to: 3)
                with: (interval copyFrom: 1 to: 1)
                with: (interval copyFrom: 3 to: 3)
                with: (interval copyFrom: 3 to: 1)
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(#(30 20 10) #(30) #(10) #())")
        #expect(await session.evaluate("(1 to: 100000) copyFrom: 99999 to: 100000").value == "#(99999 100000)")
    }

    @Test(arguments: [
        "(1 to: 3) copyFrom: 0 to: 1",
        "(1 to: 3) copyFrom: 1 to: 0",
        "(1 to: 3) copyFrom: 4 to: 1",
        "(1 to: 3) copyFrom: 1 to: 4",
        "(1 to: 3) copyFrom: 1.0 to: 3",
        "(1 to: 3) copyFrom: 1 to: 3.0",
        "(1 to: 0) copyFrom: 1 to: 0",
    ])
    func intervalSlicesRejectInvalidEndpoints(_ source: String) async {
        let session = SmalltalkSession()
        let result = await session.evaluate("[ \(source) ] on: Error do: [ :error | #invalidIndex ]")
        #expect(result.error == nil)
        #expect(result.value == "#invalidIndex")
    }

    @Test func intervalReadStreamsStillReturnEmptySlices() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | stream before matched values |
            stream := ReadStream on: (1 to: 3).
            before := stream next: 0.
            matched := stream upTo: 1.
            values := stream next: 2.
            Array with: before with: matched with: values
                with: (Array with: (stream next: 0) with: (stream upTo: 4)
                    with: stream nextLine with: (ReadStream on: (1 to: 0)) contents)
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(#() #() #(2 3) #(#() #() '' #()))")
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

    @Test func stringMembershipUsesCharacterElements() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | mutable |
            mutable := String withAll: 'abc'.
            Array with: ('abc' includes: $b)
                with: ('abc' includes: 'b')
                with: (mutable includes: 'bc')
                with: (mutable includes: $b)
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(true false false true)")
    }

    @Test func stringAndSymbolMinMaxReturnTheOperandWhenTextCollatesEqually() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | first operand |
            first := String with: $a.
            operand := String with: $A.
            Array with: ((first min: operand) == operand)
                with: ((first max: operand) == operand)
                with: ((#a min: operand) == operand)
                with: ((#a max: operand) == operand)
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(true true true true)")
        #expect(await session.evaluate("Array with: ('a' min: 'b') with: ('b' max: 'a')").value == "#('a' 'b')")
    }

    @Test(arguments: [
        "Array with: 1 with: 2",
        "#(1 2) asOrderedCollection",
        "ByteArray with: 1 with: 2",
        "String with: $a with: $b",
    ])
    func emptyReplacementsAreNoOpsButStillCheckTheReceiverBounds(_ construction: String) async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | collection before |
            collection := \(construction).
            before := collection asArray.
            collection replaceFrom: 2 to: 1 with: (1 to: 0).
            collection replaceFrom: 2 to: 1 withObject: collection first.
            collection asArray = before
            """)
        #expect(result.error == nil)
        #expect(result.value == "true")
        let invalidStart = await session.evaluate("""
            | collection |
            collection := \(construction).
            [collection replaceFrom: 3 to: 2 with: #()]
                on: Error do: [:error | #invalidIndex]
            """)
        #expect(invalidStart.error == nil)
        #expect(invalidStart.value == "#invalidIndex")
        let invalidStop = await session.evaluate("""
            | collection |
            collection := \(construction).
            [collection replaceFrom: 1 to: 0 withObject: collection first]
                on: Error do: [:error | #invalidIndex]
            """)
        #expect(invalidStop.error == nil)
        #expect(invalidStop.value == "#invalidIndex")
    }

    @Test func transcriptNextPutAllUsesTheReceiverNextPutMethod() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            Transcript class compile: 'nextPut: character self show: (character asString , ''!'')'.
            Transcript nextPutAll: 'ab'
            """)
        #expect(result.error == nil)
        #expect(result.transcript == "a!b!")
    }

    @Test func transcriptNextPutAllUsesTheSourceDoMethod() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            String compile: 'do: operation operation value: $z. operation value: $y'.
            Transcript nextPutAll: 'ab'
            """)
        #expect(result.error == nil)
        #expect(result.transcript == "zy")
    }

    @Test func stockTranscriptNextPutAllPreservesLineBreaksAndSupportsLongStrings() async {
        let session = SmalltalkSession()
        let lines = await session.evaluate("Transcript nextPutAll: (String with: $a with: Character cr with: $b)")
        #expect(lines.error == nil)
        #expect(lines.transcript == "a\nb")
        let text = String(repeating: "abc", count: 5_000)
        let bulk = await session.evaluate("Transcript nextPutAll: '\(text)'")
        #expect(bulk.error == nil)
        #expect(bulk.transcript == text)
    }

    @Test func transcriptNextPutAllPreservesObservableWrites() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | observer |
            Object subclass: #TranscriptObserver instanceVariableNames: 'updates'.
            TranscriptObserver compile: 'initialize updates := OrderedCollection new'.
            TranscriptObserver compile: 'update: aspect updates add: TranscriptBuffer text'.
            TranscriptObserver compile: 'updates ^ updates asArray'.
            observer := TranscriptObserver new.
            TranscriptBuffer addDependent: observer.
            Transcript nextPutAll: 'ab'.
            observer updates
            """)
        #expect(result.error == nil)
        #expect(result.value == "#('a' 'ab')")
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
