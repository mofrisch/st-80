import Testing
import SmalltalkCore

struct ANSICollectionBehaviorTests {
    @Test func intervalElementsKeepTheCommonNumericProtocolDuringAccessAndEnumeration() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | interval integralStart indexed enumerated values |
            interval := 0 to: 1 by: (1 / 2).
            integralStart := (Fraction numerator: 4 denominator: 2) to: 4.
            indexed := Array with: (interval at: 1) class with: (interval at: 3) class.
            enumerated := OrderedCollection new.
            0 to: 1 by: (1 / 2) do: [ :each | enumerated add: each class ].
            values := interval asArray.
            Array with: indexed with: enumerated asArray
                with: (integralStart collect: [ :each | each class ])
                with: (values = (Array with: 0 with: (1 / 2) with: 1))
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(#(Fraction Fraction) #(Fraction Fraction Fraction) #(Fraction Fraction Fraction) true)")
    }

    @Test func bulkIndexedWritesSendAtPutToTheReceiver() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | list bytes text |
            OrderedCollection subclass: #ANSIBulkWriteList instanceVariableNames: 'writes'.
            ANSIBulkWriteList compile: 'initialize super initialize. writes := OrderedCollection new'.
            ANSIBulkWriteList compile: 'at: index put: element
                writes add: index. ^ super at: index put: element'.
            ANSIBulkWriteList compile: 'writes ^ writes asArray'.
            ByteArray subclass: #ANSIBulkWriteBytes instanceVariableNames: 'writes'.
            ANSIBulkWriteBytes compile: 'initialize super initialize. writes := OrderedCollection new'.
            ANSIBulkWriteBytes compile: 'at: index put: element
                writes add: index. ^ super at: index put: element'.
            ANSIBulkWriteBytes compile: 'writes ^ writes asArray'.
            ansiStringWrites := OrderedCollection new.
            String compile: 'at: index put: element
                | characters |
                ansiStringWrites add: index.
                characters := self asArray.
                characters at: index put: element.
                self _replaceCharacters: characters.
                ^ element'.
            list := ANSIBulkWriteList withAll: #(1 2 3).
            bytes := ANSIBulkWriteBytes withAll: #(1 2 3).
            text := String withAll: 'abc'.
            list atAll: #(2 3 2) put: 7; atAllPut: 5.
            bytes atAll: #(2 3 2) put: 7; atAllPut: 5.
            text atAll: #(2 3 2) put: $x; atAllPut: $z.
            Array with: list writes with: bytes writes with: ansiStringWrites asArray
                with: (Array with: list asArray with: bytes asArray with: text)
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(#(2 3 2 1 2 3) #(2 3 2 1 2 3) #(2 3 2 1 2 3) #(#(5 5 5) #(5 5 5) 'zzz'))")
    }

    @Test func extensibleCollectionBulkOperationsUseSourceIterationAndIndividualMessages() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | source set sorted |
            OrderedCollection subclass: #ANSIBulkSource instanceVariableNames: 'destination visits'.
            ANSIBulkSource compile: 'observe: anObject destination := anObject. visits := OrderedCollection new'.
            ANSIBulkSource compile: 'do: action
                super do: [ :each | action value: each. visits add: destination size ]'.
            ANSIBulkSource compile: 'visits ^ visits asArray'.
            Set subclass: #ANSIBulkSet instanceVariableNames: 'removed'.
            ANSIBulkSet compile: 'initialize super initialize. removed := OrderedCollection new'.
            ANSIBulkSet compile: 'remove: each removed add: each. ^ super remove: each'.
            ANSIBulkSet compile: 'removed ^ removed asArray'.
            SortedCollection subclass: #ANSIBulkSorted instanceVariableNames: 'added removed'.
            ANSIBulkSorted compile: 'initialize
                super initialize. added := OrderedCollection new. removed := OrderedCollection new'.
            ANSIBulkSorted compile: 'add: each added add: each. ^ super add: each'.
            ANSIBulkSorted compile: 'remove: each removed add: each. ^ super remove: each'.
            ANSIBulkSorted compile: 'operations ^ Array with: added asArray with: removed asArray'.
            set := ANSIBulkSet new.
            source := ANSIBulkSource withAll: #(1 2).
            source observe: set.
            set addAll: source; removeAll: #(2 1).
            sorted := ANSIBulkSorted new.
            sorted addAll: #(3 1 2); removeAll: #(2 3).
            Array with: source visits with: set removed with: sorted operations with: sorted asArray
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(#(1 2) #(2 1) #(#(3 1 2) #(2 3)) #(1))")
    }

    @Test func sortedReplacementValidatesAnUnusedElementWithTheSortBlock() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | sorted rejected allowed allReplaced |
            sorted := SortedCollection with: 1 with: 2.
            rejected := [ sorted copyReplacing: 99 withObject: #bad. false ]
                on: Error do: [ :error | true ].
            allowed := sorted copyReplacing: 99 withObject: 3.
            allReplaced := (SortedCollection with: 1 with: 1) copyReplacing: 1 withObject: #valid.
            Array with: rejected with: allowed asArray with: allReplaced asArray with: sorted asArray
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(true #(1 2) #(#valid #valid) #(1 2))")
    }

    @Test func streamsAndStringComparisonsAcceptForwardedCollectionProtocols() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | sequence text stream writer |
            Object subclass: #ANSIForwardingCollection instanceVariableNames: 'subject'.
            ANSIForwardingCollection compile: 'subject: anObject subject := anObject'.
            ANSIForwardingCollection compile: 'doesNotUnderstand: failure
                ^ subject perform: failure selector withArguments: failure arguments'.
            sequence := ANSIForwardingCollection new subject: #(7 8 9); yourself.
            text := ANSIForwardingCollection new subject: 'ABC'; yourself.
            stream := ReadStream on: sequence.
            writer := ReadWriteStream on: sequence.
            writer nextPut: 11; reset.
            Array with: (stream next: 2) with: writer next
                with: ('abc' sameAs: text) with: ('x' , text)
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(#(7 8) 11 true 'xABC')")
    }

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

    @Test func collectionStreamsHonorAnOverriddenSelectionMethodOnArray() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | stream prefix |
            Array compile: 'select: predicate
                | selected |
                selected := OrderedCollection new.
                self do: [ :each | (predicate value: each) ifTrue: [ selected add: each ] ].
                ^ selected'.
            stream := ReadStream on: #(8 9 10).
            stream skip: 1.
            prefix := stream next: 1.
            Array with: stream contents class with: prefix class with: prefix asArray
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(OrderedCollection OrderedCollection #(9))")
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
            TranscriptObserver compileClass: 'new ^ super new initialize; yourself'.
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

    @Test func stringWithAllAcceptsCollectionsThatDoNotHaveIntegerIndices() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | dictionary |
            dictionary := Dictionary new.
            dictionary at: #letter put: $é.
            Array with: (String withAll: (Bag with: $x with: $x))
                with: (String withAll: dictionary)
                with: (String withAll: (Set with: $z))
                with: (String withAll: Bag new)
            """)
        #expect(result.error == nil)
        #expect(result.value == "#('xx' 'é' 'z' '')")
    }

    @Test func stringWithAllUsesSourceDo() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            Array compile: 'do: operation operation value: $z. operation value: $y'.
            String withAll: #($a $b)
            """)
        #expect(result.error == nil)
        #expect(result.value == "'zy'")
    }

    @Test func orderedCollectionBulkChangesInterleaveSourceIterationAndReceiverOperations() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | source target added removed addResult removeResult |
            OrderedCollection subclass: #ANSIObservedSource instanceVariableNames: 'observe'.
            ANSIObservedSource compile: 'observe: callback observe := callback'.
            ANSIObservedSource compile: 'do: operation super do: [ :each | operation value: each. observe value ]'.
            OrderedCollection subclass: #ANSIObservedTarget instanceVariableNames: 'events'.
            ANSIObservedTarget compile: 'events: log events := log'.
            ANSIObservedTarget compile: 'add: element events add: #added. ^ super add: element'.
            ANSIObservedTarget compile: 'remove: element events add: #removed. ^ super remove: element'.
            source := ANSIObservedSource with: 1 with: 2.
            target := ANSIObservedTarget new.
            added := OrderedCollection new.
            target events: added.
            source observe: [ added add: target size ].
            addResult := target addAll: source.
            target addLast: 3.
            removed := OrderedCollection new.
            target events: removed.
            source observe: [ removed add: target size ].
            removeResult := target removeAll: source.
            Array with: added asArray with: removed asArray with: target asArray
                with: (addResult == source and: [removeResult == source])
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(#(#added 1 #added 2) #(#removed 2 #removed 1) #(3) true)")
    }

    @Test func orderedCollectionBulkAddUsesAnOverriddenArrayDo() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | target |
            target := OrderedCollection new.
            Array compile: 'do: operation operation value: 3. operation value: 2'.
            target addAll: #(1 2).
            Array with: (target at: 1) with: (target at: 2)
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(3 2)")
    }

    @Test func orderedCollectionBulkAddUsesAnOverriddenAddOnTheStockClass() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | target |
            target := OrderedCollection new.
            OrderedCollection compile: 'add: element ^ self addLast: element + 10'.
            target addAll: #(1 2).
            target asArray
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(11 12)")
    }

    @Test func orderedCollectionBulkAddSupportsLargeArrays() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | target source |
            target := OrderedCollection with: 1.
            source := (Array new: 15000) at: 15000 put: 2; yourself.
            target addAll: source.
            Array with: target size with: target first with: target last
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(15001 1 2)")
    }

    @Test func orderedCollectionBulkCopyAndSelfAddSupportLargeCollections() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | target copied |
            target := OrderedCollection new: 30000.
            target addLast: 1; addAll: (Array new: 14998); addLast: 2.
            copied := target copy.
            target addAll: target.
            Array with: copied size with: target size with: (target at: 15001) with: target last
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(15000 30000 1 2)")
    }

    @Test(arguments: [
        "String new atAllPut: 33",
        "(String withAll: 'abc') atAll: #() put: 33",
        "(ByteArray with: 1) copyReplaceAll: #(2) with: #(256)",
        "(ByteArray with: 1) copyReplacing: 2 withObject: -1",
    ])
    func restrictedCollectionsValidateValuesEvenWhenNoElementsChange(_ source: String) async {
        let session = SmalltalkSession()
        let result = await session.evaluate("[ \(source) ] on: Error do: [ :error | #invalidElement ]")
        #expect(result.error == nil)
        #expect(result.value == "#invalidElement")
    }

    @Test func sortedCollectionCopyReplaceAllChecksReplacementOrderingWithoutMatches() async {
        let session = SmalltalkSession()
        let invalid = await session.evaluate("(SortedCollection with: 1) copyReplaceAll: #(2) with: #(1 #bad)")
        #expect(invalid.error != nil)
        let valid = await session.evaluate("((SortedCollection with: 1) copyReplaceAll: #(1) with: #(3 2)) asArray")
        #expect(valid.error == nil)
        #expect(valid.value == "#(2 3)")
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
