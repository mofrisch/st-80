"Behavior from the ANSI Smalltalk draft (J20 revision 1.9)."

Object subclass: #ANSIDispatchProbe instanceVariableNames: ''.
Object subclass: #ANSIEqualityProbe instanceVariableNames: 'value'.

ANSIEqualityProbe compile: 'value: aValue
    value := aValue'.

ANSIEqualityProbe compile: 'value
    ^ value'.

ANSIEqualityProbe compile: '= other
    ^ other class == self class and: [ value = other value ]'.

ANSIEqualityProbe compile: 'hash
    ^ value hash'.

ANSIDispatchProbe compile: 'touch
    42'.

ANSIDispatchProbe compile: 'doesNotUnderstand: aMessage
    ^ aMessage'.

ANSIDispatchProbe compile: 'handles: anException
    ^ anException messageText = ''selected'''.

Error subclass: #ANSIProbeError instanceVariableNames: ''.
Exception subclass: #ANSIProbeException instanceVariableNames: ''.
Warning subclass: #ANSIProbeWarning instanceVariableNames: ''.

ANSIProbeWarning compile: 'defaultAction
    ^ #customWarning'.

Object subclass: #ANSIClassStateProbe
    instanceVariableNames: 'slot'
    classInstanceVariableNames: 'slot'.

ANSIClassStateProbe subclass: #ANSIClassStateChild
    instanceVariableNames: ''
    classInstanceVariableNames: 'detail'.

ANSIClassStateProbe compile: 'slot
    ^ slot'.

ANSIClassStateProbe compileClass: 'slot
    ^ slot'.

ANSIClassStateProbe compileClass: 'slot: value
    slot := value'.

ANSIClassStateProbe compileClass: 'slotReader
    ^ [ slot ]'.

ANSIClassStateChild compileClass: 'inheritedSlot
    ^ super slot'.

ANSIClassStateChild compileClass: 'detail
    ^ detail'.

ANSIProbeException compile: 'defaultAction
    ^ 40'.

ANSIProbeException compile: 'isResumable
    ^ true'.

TestCase subclass: #ANSISmalltalkTest instanceVariableNames: ''.

ANSISmalltalkTest compile: 'testClassObjectsHaveDistinctMetaclasses
    self assert: ANSIClassStateProbe new class == ANSIClassStateProbe.
    self assert: ANSIClassStateProbe class == ANSIClassStateProbe class.
    self deny: ANSIClassStateProbe class == ANSIClassStateChild class.
    self assert: ANSIClassStateChild class superclass == ANSIClassStateProbe class.
    self assert: ANSIClassStateChild class instanceClass == ANSIClassStateChild.
    self assert: ANSIClassStateChild class class == Metaclass.
    self assert: Metaclass class class == Metaclass.
    self assert: Object class superclass == Class.
    self assert: Object allSuperclasses isEmpty.
    self assert: (ANSIClassStateChild allSuperclasses) equals: (Array with: ANSIClassStateProbe with: Object).
    self assert: (Object allSubclasses includes: ANSIClassStateChild).
    self assert: (ANSIClassStateProbe class allSubclasses includes: ANSIClassStateChild class)'.

ANSISmalltalkTest compile: 'testClassInstanceVariablesBelongToTheReceivingClass
    | read |
    self assert: ANSIClassStateProbe slot isNil.
    self assert: ANSIClassStateChild slot isNil.
    self assert: ANSIClassStateChild detail isNil.
    [
        ANSIClassStateProbe slot: 7.
        read := ANSIClassStateChild slotReader.
        ANSIClassStateChild slot: 42.
        self assert: ANSIClassStateProbe slot equals: 7.
        self assert: ANSIClassStateChild inheritedSlot equals: 42.
        self assert: read value equals: 42.
        self assert: ANSIClassStateChild new slot isNil
    ] ensure: [
        ANSIClassStateProbe slot: nil.
        ANSIClassStateChild slot: nil ]'.

ANSISmalltalkTest compile: 'testMessagePrecedence
    self assert: 3 + 4 * 2 equals: 14.
    self assert: 2 + 3 squared equals: 11.
    self assert: (3 + 4 > 6 ifTrue: [ 42 ] ifFalse: [ 0 ]) equals: 42'.

ANSISmalltalkTest compile: 'testCascadeUsesTheSameReceiver
    | calls factory result |
    calls := 0.
    factory := [ calls := calls + 1. Array new: 2 ].
    result := factory value at: 1 put: 7; at: 2 put: 8; yourself.
    self assert: calls equals: 1.
    self assert: result equals: #(7 8)'.

ANSISmalltalkTest compile: 'testMethodReturnAndSuper
    | probe |
    probe := ANSIDispatchProbe new.
    self assert: probe touch == probe.
    self assert: super setUp == self'.

ANSISmalltalkTest compile: 'testFailedSendCarriesSelectorAndArguments
    | message |
    message := ANSIDispatchProbe new missing: 7 with: 8.
    self assert: message selector equals: #missing:with:.
    self assert: message arguments equals: #(7 8)'.

ANSISmalltalkTest compile: 'testRadixLiteralsAndFloorDivision
    self assert: 2r1010 + 16rFF + 36rZ equals: 300.
    self assert: -16rFF equals: -255.
    self assert: -7 // 3 equals: -3.
    self assert: -7 \\ 3 equals: 2'.

ANSISmalltalkTest compile: 'testLargeIntegerArithmetic
    self assert: 9223372036854775807 + 1 equals: 9223372036854775808.
    self assert: -9223372036854775808 negated equals: 9223372036854775808.
    self assert: 16r1000000000000000000000000 equals: 79228162514264337593543950336.
    self assert: 1000000000000000000000000 squared equals: 1000000000000000000000000000000000000000000000000'.

ANSISmalltalkTest compile: 'testLargeIntegerFloorDivision
    | dividend divisor |
    dividend := 12345678901234567890123456789012345678901234567890.
    divisor := 98765432109876543210987654321.
    self assert: dividend // divisor equals: 124999998860937500014.
    self assert: dividend \\ divisor equals: 23533950614699073961469907396.
    self assert: dividend negated // divisor equals: -124999998860937500015.
    self assert: dividend negated \\ divisor equals: 75231481495177469249517746925.
    self assert: dividend // divisor negated equals: -124999998860937500015.
    self assert: dividend \\ divisor negated equals: -75231481495177469249517746925'.

ANSISmalltalkTest compile: 'testExactFractions
    | rational sum |
    rational := Fraction numerator: 4 denominator: -6.
    self assert: rational numerator equals: -2.
    self assert: rational denominator equals: 3.
    sum := (1 / 3) + (1 / 6).
    self assert: sum equals: (1 / 2).
    self assert: sum * 2 equals: 1.
    self assert: ((1000000000000000000000001 / 3) * 3) equals: 1000000000000000000000001'.

ANSISmalltalkTest compile: 'testScaledDecimalLiterals
    self assert: 123s class equals: ScaledDecimal.
    self assert: 123s scale equals: 0.
    self assert: 1.2300s scale equals: 4.
    self assert: 123s2 printString equals: ''123.00s2''.
    self assert: -0.004s printString equals: ''-0.004s3''.
    self assert: (0s3 printString) equals: ''0.000s3''.
    self assert: (#(-1.20s 7s3) at: 1) scale equals: 2'.

ANSISmalltalkTest compile: 'testScaledDecimalExactArithmetic
    self assert: (0.1s + 0.2s) equals: 0.3s.
    self assert: (2 - 0.125s) printString equals: ''1.875s3''.
    self assert: (0.125s + 2) printString equals: ''2.125s3''.
    self assert: (1.20s * 2.5s) printString equals: ''3.000s3''.
    self assert: 0.20s squared printString equals: ''0.0400s4''.
    self assert: (-2.50s abs) printString equals: ''2.50s2'''.

ANSISmalltalkTest compile: 'testScaledDecimalDivision
    self assert: (1.00s / 8) printString equals: ''0.125s3''.
    self assert: (2 / 4.000s) printString equals: ''0.500s3''.
    self assert: (2s / 3) printString equals: ''0.666666666666666666666666666667s30''.
    self assert: -7.50s // 2s equals: -4.
    self assert: (-7.50s \\ 2s) printString equals: ''0.50s2''.
    self assert: (1s / 1099511627776) scale equals: 40'.

ANSISmalltalkTest compile: 'testScaledDecimalMixedNumericTypes
    self assert: (0.50s + (1 / 3)) equals: (5 / 6).
    self assert: ((1 / 3) + 0.50s) class equals: Fraction.
    self assert: (0.25s + 0.5) class equals: Float.
    self assert: 0.5 + 0.25s equals: 0.75.
    self assert: 1.000s equals: 1.
    self assert: 1 equals: 1.000s.
    self assert: 0.50s equals: (1 / 2).
    self assert: (1 / 2) equals: 0.50s.
    self assert: 0.50s equals: 0.5.
    self assert: 0.5 equals: 0.50s.
    self assert: 1.230s equals: 1.23s.
    self assert: 0.33s < (1 / 3).
    self assert: (1 / 3) > 0.33s'.

ANSISmalltalkTest compile: 'testScaledDecimalConversions
    self assert: (42 asScaledDecimal: 3) printString equals: ''42s0''.
    self assert: (9000000000000000000000000 asScaledDecimal: 2) scale equals: 0.
    self assert: ((1 / 8) asScaledDecimal: 2) equals: 0.13s.
    self assert: ((-1 / 8) asScaledDecimal: 2) equals: -0.13s.
    self assert: (0.125 asScaledDecimal: 4) printString equals: ''0.1250s4''.
    self assert: (2.675 asScaledDecimal: 2) equals: 2.67s.
    self assert: (7.25s asScaledDecimal: 1) equals: 7.3s.
    self assert: (7.25s asScaledDecimal: 4) printString equals: ''7.2500s4''.
    self assert: 1.250s asFraction equals: (5 / 4).
    self assert: -1.50s asInteger equals: -2.
    self assert: -1.50s integerPart printString equals: ''-2.00s2''.
    self assert: -1.50s fractionPart equals: 0.50s.
    self assert: -1.50s truncated equals: -1.
    self assert: -1.50s floor equals: -2.
    self assert: -1.50s ceiling equals: -1'.

ANSISmalltalkTest compile: 'testScaledDecimalWithWideCoefficient
    | number |
    number := 123456789012345678901234567890.000000000000000000000000000001s.
    self assert: number scale equals: 30.
    self assert: (number - 123456789012345678901234567890) printString
        equals: ''0.000000000000000000000000000001s30''.
    self assert: number printString equals: ''123456789012345678901234567890.000000000000000000000000000001s30''.
    self assert: (1s1024 * 2.0s) scale equals: 1024.
    self assert: (1s1024 * 2.0s) equals: 2'.

ANSISmalltalkTest compile: 'testFloatLiteralsAndPrecisionOrdering
    self assert: 1.25 * 2 equals: 2.5.
    self assert: 1.25e2 equals: 125.0.
    self assert: 1.25d2 equals: 125.0.
    self assert: -1.25q2 equals: -125.0.
    self assert: FloatE precision <= FloatD precision.
    self assert: FloatD precision <= FloatQ precision'.

ANSISmalltalkTest compile: 'testCharacterLiteralsAndStringElements
    self assert: (''Az'' at: 1) equals: $A.
    self assert: (Character codePoint: $A codePoint) equals: $A.
    self assert: $A asLowercase equals: $a.
    self assert: $z asUppercase asString equals: ''Z''.
    self assert: Character space equals: ($ ).
    self assert: $9 isDigit'.

ANSISmalltalkTest compile: 'testLiteralArrayValuesAndSymbolIdentity
    | values |
    values := #(nil true false #nil #($A 2)).
    self assert: (values at: 1) == nil.
    self assert: (values at: 2) == true.
    self assert: (values at: 3) == false.
    self deny: (values at: 4) == nil.
    self assert: (values at: 4) == #nil.
    self assert: (values at: 5) equals: #($A 2)'.

ANSISmalltalkTest compile: 'testLexicalBlockBindings
    | Total increase |
    Total := 40.
    increase := [ :amount | Total := Total + amount ].
    self assert: (increase value: 2) equals: 42.
    self assert: ([ :Total | Total + 1 ] value: 6) equals: 7.
    self assert: Total equals: 42'.

ANSISmalltalkTest compile: 'testValuableProtocol
    | block |
    block := [ :a :b :c | a * b + c ].
    self assert: block argumentCount equals: 3.
    self assert: (block valueWithArguments: #(6 7 1)) equals: 43.
    self assert: (6 perform: #* withArguments: #(7)) equals: 42'.

ANSISmalltalkTest compile: 'testBooleanShortCircuitAndLoop
    | count |
    count := 0.
    self deny: (false and: [ count := 99. true ]).
    self assert: (true or: [ count := 99. false ]).
    self assert: count equals: 0.
    [ count := count + 1. count < 3 ] whileTrue.
    self assert: count equals: 3.
    self assert: true | false.
    self deny: true & false'.

ANSISmalltalkTest compile: 'testCleanupRunsInUnwindOrder
    | order |
    order := Array new: 2.
    self assert: (self returnThroughCleanup: order) equals: 42.
    self assert: order equals: #(1 2).
    [ 0 ] ifCurtailed: [ self fail: ''Unexpected cleanup on normal return.'' ].
    [ 0 ] ensure: [ order at: 1 put: 3 ].
    self assert: order equals: #(3 2)'.

ANSISmalltalkTest compile: 'returnThroughCleanup: order
    [ [ ^ 42 ] ensure: [ order at: 1 put: 1 ] ]
        ifCurtailed: [ order at: 2 put: (order at: 1) + 1 ].
    ^ 0'.

ANSISmalltalkTest compile: 'testExceptionNormalCompletion
    | called |
    called := false.
    self assert: ([ 42 ] on: Error do: [ :exception | called := true ]) equals: 42.
    self deny: called'.

ANSISmalltalkTest compile: 'testExceptionSignalersAndMetadata
    | instance handled |
    instance := ANSIProbeError new.
    self assert: instance messageText isNil.
    self deny: instance isResumable.
    self assert: (Error handles: instance).
    self assert: (Exception handles: instance).
    self deny: (ANSIProbeException handles: instance).
    instance messageText: ''instance''; tag: #example.
    self assert: ([ instance signal ] on: Error do: [ :exception | exception ]) == instance.
    self assert: instance messageText equals: ''instance''.
    self assert: instance tag equals: #example.
    instance tag: nil.
    self assert: instance tag isNil.
    handled := [ ANSIProbeError signal: ''class'' ] on: Exception do: [ :exception | exception ].
    self assert: handled class equals: ANSIProbeError.
    self assert: handled description equals: ''class''.
    self assert: handled tag equals: ''class''.
    self assert: ([ Error signal ] on: Error do: [ :exception | exception messageText ]) isNil.
    self assert: ([ self error: ''object'' ] on: Error do: [ :exception | exception messageText ]) equals: ''object'''.

ANSISmalltalkTest compile: 'testExceptionSelectsNearestMatchingHandler
    self assert: ([
        [ [ ANSIProbeError signal ] on: ANSIProbeException do: [ :exception | 1 ] ]
            on: Error do: [ :exception | 42 ] ]
        on: Exception do: [ :exception | 0 ]) equals: 42'.

ANSISmalltalkTest compile: 'testExceptionFromAnActionUsesTheOuterEnvironment
    | handled |
    handled := [
        [ ANSIProbeError signal: ''original'' ] on: Error do: [ :exception |
            self assert: exception messageText equals: ''original''.
            Error signal: ''replacement'' ] ]
        on: Exception do: [ :exception | exception messageText ].
    self assert: handled equals: ''replacement'''.

ANSISmalltalkTest compile: 'testExceptionHandlerRunsBeforeUnwindBlocks
    | order answer |
    order := ''''.
    answer := [
        [ [ Error signal. self fail: ''The signal should not return.'' ]
            ensure: [ order := order , ''ensure '' ] ]
            ifCurtailed: [ order := order , ''curtailed'' ] ]
        on: Error do: [ :exception | order := order , ''handler ''. Array with: 42 ].
    self assert: answer equals: #(42).
    self assert: order equals: ''handler ensure curtailed'''.

ANSISmalltalkTest compile: 'testExceptionActionCanReturnFromItsHomeMethod
    | order |
    order := Array new: 2.
    self assert: (self returnThroughException: order) equals: 42.
    self assert: order equals: #(1 2)'.

ANSISmalltalkTest compile: 'returnThroughException: order
    [ [ Error signal ] ensure: [ order at: 2 put: (order at: 1) + 1 ] ]
        on: Error do: [ :exception | order at: 1 put: 1. ^ 42 ].
    ^ 0'.

ANSISmalltalkTest compile: 'testExceptionSelectorUsesHandles
    | selector |
    selector := ANSIDispatchProbe new.
    self assert: ([ Error signal: ''selected'' ] on: selector do: [ :exception | 42 ]) equals: 42.
    self assert: ([
        [ Error signal: ''different'' ] on: selector do: [ :exception | 1 ] ]
        on: Error do: [ :exception | 42 ]) equals: 42'.

ANSISmalltalkTest compile: 'testExceptionDefaultAction
    self assert: ANSIProbeException signal + 2 equals: 42'.

ANSISmalltalkTest compile: 'testArrayFactoriesAndIndexedCopy
    | original copy |
    original := Array with: 7 with: 8 with: 9.
    copy := Array withAll: original.
    copy at: 1 put: 42.
    self assert: original equals: #(7 8 9).
    self assert: (copy copyFrom: 1 to: 2) equals: #(42 8).
    self assert: (copy at: 4 ifAbsent: [ 0 ]) equals: 0.
    self assert: (copy at: 2 ifAbsent: [ self fail: ''Existing element reported missing.'' ]) equals: 8'.

ANSISmalltalkTest compile: 'testLargeArrayIsOneBasedAndInitiallyNil
    | array |
    array := Array new: 65535.
    self assert: array size equals: 65535.
    self assert: (array at: 1) isNil.
    self assert: (array at: 65535) isNil.
    array at: 65535 put: 42.
    self assert: (array at: 65535) equals: 42'.

ANSISmalltalkTest compile: 'testObjectCopyClassTestsAndHash
    | counter copy |
    counter := Counter new add: 7.
    copy := counter copy.
    copy increment.
    self assert: counter value equals: 7.
    self assert: copy value equals: 8.
    self assert: (counter isMemberOf: Counter).
    self assert: (counter isKindOf: Object).
    self deny: (counter isMemberOf: Object).
    self assert: 0.50s hash equals: (1 / 2) hash.
    self assert: (Array with: 7) hash equals: #(7) hash.
    self assert: counter identityHash equals: counter identityHash'.

ANSISmalltalkTest compile: 'testIntegerBitAndNumberTheoryProtocols
    | high |
    high := 1 bitShift: 97.
    self assert: high highBit equals: 98.
    self assert: (high bitAt: 98) equals: 1.
    self assert: (high bitAt: 98 put: 0) equals: 0.
    self assert: ((high bitOr: 5) bitXor: high) equals: 5.
    self assert: (high bitShift: -97) equals: 1.
    self assert: (13 allMask: 5).
    self assert: (13 anyMask: 6).
    self assert: (13 noMask: 2).
    self assert: -7 odd.
    self assert: (48 gcd: -18) equals: 6.
    self assert: (21 lcm: 6) equals: 42.
    self assert: 0 factorial equals: 1.
    self assert: 20 factorial equals: 2432902008176640000.
    self assert: (-384839 printStringRadix: 36) equals: ''-88XZ'''.

ANSISmalltalkTest compile: 'testNumericConversionsAndIntervals
    self assert: (3 between: 1 and: 3).
    self assert: (4 asFraction) equals: 4.
    self assert: 0.125 asFraction equals: (1 / 8).
    self assert: -2.5 asInteger equals: -3.
    self assert: ((-7 / 2) quo: 1) equals: -3.
    self assert: ((-7 / 2) rem: 1) equals: (-1 / 2).
    self assert: (2 raisedTo: 100) equals: 1267650600228229401496703205376.
    self assert: (2 raisedToInteger: -3) equals: (1 / 8).
    self assert: ((8.5s roundTo: 2s) = 8s).
    self assert: ((8.5s truncateTo: 3s) = 6s).
    self assert: (9 to: 1 by: -3) asArray equals: #(9 6 3).
    self assert: (1 to: 9 by: -3) isEmpty.
    self assert: (0.5s to: 1.5s by: 0.5s) asArray equals: #(0.5s 1.0s 1.5s).
    self assert: (90.0 degreesToRadians sin - 1.0) abs < 0.000000001'.

ANSISmalltalkTest compile: 'testCollectionSearchingAndEnumeration
    | values order |
    values := #(1 3 2 3).
    self assert: (values allSatisfy: [ :each | each > 0 ]).
    self deny: (values anySatisfy: [ :each | each > 3 ]).
    self assert: (values detect: [ :each | each even ]) equals: 2.
    self assert: (values detect: [ :each | each > 3 ] ifNone: [ 42 ]) equals: 42.
    self assert: (values inject: 0 into: [ :sum :each | sum + each ]) equals: 9.
    self assert: (values occurrencesOf: 3) equals: 2.
    self assert: (values indexOf: 3) equals: 2.
    self assert: (values findLast: [ :each | each = 3 ]) equals: 4.
    self assert: (values indexOfSubCollection: #(3 2) startingAt: 1) equals: 2.
    self assert: (values indexOfSubCollection: #(3 2) startingAt: 3 ifAbsent: [ 42 ]) equals: 42.
    self assert: (values before: 3) equals: 1.
    self assert: (values after: 3) equals: 2.
    order := 0.
    values from: 2 to: 3 keysAndValuesDo: [ :index :value | order := order * 100 + (index * 10) + value ].
    self assert: order equals: 2332'.

ANSISmalltalkTest compile: 'testSequenceCopyAndOverlappingReplacement
    | values |
    self assert: (#(1 2 1 2 3) copyReplaceAll: #(1 2) with: #(9)) equals: #(9 9 3).
    self assert: (#(1 2) copyReplaceFrom: 2 to: 1 withObject: 42) equals: #(1 42 2).
    self assert: (#(1 2 1) copyReplacing: 1 withObject: 42) equals: #(42 2 42).
    self assert: (#(1 2 1 3) copyWithout: 1) equals: #(2 3).
    values := Array withAll: #(1 2 3 4).
    values replaceFrom: 2 to: 4 with: values startingAt: 1.
    self assert: values equals: #(1 1 2 3).
    values atAll: #(1 3) put: 42.
    self assert: values equals: #(42 1 42 3)'.

ANSISmalltalkTest compile: 'testStringFactoriesAndReadableStringProtocols
    | text alias copy |
    text := String with: $A with: $é with: $B.
    alias := text.
    copy := text copy.
    text at: 2 put: $猫.
    self assert: alias equals: ''A猫B''.
    self assert: copy equals: ''AéB''.
    text replaceFrom: 1 to: 2 with: ''xY''.
    self assert: text equals: ''xYB''.
    self assert: text hash equals: ''xYB'' hash.
    self assert: text asLowercase equals: ''xyb''.
    self assert: (text sameAs: #Xyb).
    self assert: (#bravo between: ''ALPHA'' and: ''Charlie'').
    self assert: (''a,,bc,'' subStrings: '','') equals: #(''a'' ''bc'').
    self assert: #Ab size equals: 2.
    self assert: (#Ab at: 1) equals: $A.
    text := ''a'' , ''b''.
    text at: 2 put: $c.
    self assert: text equals: ''ac'''.

ANSISmalltalkTest compile: 'testExceptionRetryReturnAndResignal
    | attempts value |
    attempts := 0.
    value := [
        attempts := attempts + 1.
        attempts = 1 ifTrue: [ Error signal ].
        42
    ] on: Error do: [ :exception | exception retry ].
    self assert: attempts equals: 2.
    self assert: value equals: 42.
    self assert: ([ Error signal ] on: Error do: [ :exception | exception retryUsing: [ 42 ] ]) equals: 42.
    self assert: ([ Error signal ] on: Error do: [ :exception | exception return: 42 ]) equals: 42.
    value := [
        [ Error signal ] on: Error do: [ :exception | exception resignalAs: (ANSIProbeException new messageText: ''replacement'') ]
    ] on: ANSIProbeException do: [ :exception | exception resume: 42 ].
    self assert: value equals: 42'.

ANSISmalltalkTest compile: 'testExceptionResumeOuterPassAndSets
    | value |
    value := [
        [ 1 + ANSIProbeException signal ] on: ANSIProbeException do: [ :exception |
            self assert: exception isNested.
            exception resume: exception outer + 1 ]
    ] on: Exception do: [ :exception | exception resume: 40 ].
    self assert: value equals: 42.
    value := [
        [ Error signal ] on: Error do: [ :exception | exception pass ]
    ] on: ANSIProbeException , Error do: [ :exception | 42 ].
    self assert: value equals: 42'.

ANSISmalltalkTest compile: 'testStandardErrorsCarryTheirArguments
    | object |
    object := Object new.
    self assert: ([ object ansiMissing: 7 ] on: MessageNotUnderstood do: [ :exception |
        self assert: exception receiver == object.
        self assert: exception message selector equals: #ansiMissing:.
        self assert: exception message arguments equals: #(7).
        exception resume: 42 ]) equals: 42.
    self assert: ([ 7 / 0 ] on: ZeroDivide do: [ :exception |
        self assert: exception dividend equals: 7.
        exception resume: 42 ]) equals: 42'.

ANSISmalltalkTest compile: 'testBagCountsAndRemovesOccurrences
    | bag copy |
    bag := Bag new: 12.
    self assert: bag isEmpty.
    bag add: 7 withOccurrences: 3; addAll: #(7 9 9).
    self assert: bag size equals: 6.
    self assert: (bag occurrencesOf: 7) equals: 4.
    self assert: (bag remove: 7) equals: 7.
    bag removeAll: #(9 9).
    self assert: (bag occurrencesOf: 7) equals: 3.
    self assert: (bag remove: 9 ifAbsent: [ 42 ]) equals: 42.
    copy := bag copy.
    copy add: 7.
    self assert: (bag occurrencesOf: 7) equals: 3.
    self assert: (copy occurrencesOf: 7) equals: 4.
    self assert: ((bag collect: [ :each | each + 1 ]) occurrencesOf: 8) equals: 3'.

ANSISmalltalkTest compile: 'testSetUsesEqualityAndSuppressesDuplicates
    | values transformed |
    values := Set with: 1 with: 1.0 with: (1 / 2) with: 0.50s.
    self assert: values size equals: 2.
    values addAll: #(1 2 2).
    self assert: values size equals: 3.
    self assert: (values includes: 0.5).
    self assert: (values occurrencesOf: 1) equals: 1.
    self assert: (values remove: 1.0) equals: 1.
    self deny: (values includes: 1).
    transformed := values collect: [ :each | 9 ].
    self assert: transformed class equals: Set.
    self assert: transformed size equals: 1.
    self deny: (values respondsTo: #at:)'.

ANSISmalltalkTest compile: 'testOrderedCollectionInsertsAndRemovesAtBoundaries
    | values |
    values := OrderedCollection new: 8.
    self assert: values isEmpty.
    values addFirst: 3; addLast: 6; add: 5 before: 6; add: 4 afterIndex: 1.
    values addAllFirst: #(1 2); addAllLast: #(7 8).
    values addAll: #(0) afterIndex: 0.
    values addAll: #(9 10) beforeIndex: values size + 1.
    self assert: values asArray equals: #(0 1 2 3 4 5 6 7 8 9 10).
    self assert: values removeFirst equals: 0.
    self assert: values removeLast equals: 10.
    self assert: (values removeAtIndex: 4) equals: 4.
    values at: 4 put: 42.
    self assert: values asArray equals: #(1 2 3 42 6 7 8 9)'.

ANSISmalltalkTest compile: 'testOrderedCollectionSnapshotsOverlappingUpdates
    | values copy |
    values := OrderedCollection with: 1 with: 2 with: 3 with: 4.
    values replaceFrom: 2 to: 4 with: values startingAt: 1.
    self assert: values asArray equals: #(1 1 2 3).
    values addAll: values afterIndex: 2.
    self assert: values asArray equals: #(1 1 1 1 2 3 2 3).
    copy := values copy.
    copy atAll: #(1 8) put: nil.
    self assert: copy first isNil.
    self assert: values first equals: 1.
    self assert: (values reverse class == OrderedCollection)'.

ANSISmalltalkTest compile: 'testByteArrayFactoriesBoundsAndReplacement
    | bytes sizeLimit |
    sizeLimit := ByteArray new: 65535.
    self assert: sizeLimit last equals: 0.
    sizeLimit at: 65535 put: 255.
    self assert: sizeLimit last equals: 255.
    bytes := ByteArray with: 10 with: 20 with: 30.
    bytes replaceFrom: 2 to: 3 with: bytes startingAt: 1.
    self assert: bytes asArray equals: #(10 10 20).
    self assert: ([ bytes replaceFrom: 1 to: 2 with: #(99 256). false ]
        on: Error do: [ :exception | true ]).
    self assert: bytes asArray equals: #(10 10 20).
    self assert: ([ bytes at: 1 put: 1.0. false ] on: Error do: [ :exception | true ]).
    self assert: (bytes reverse class == ByteArray)'.

ANSISmalltalkTest compile: 'testSortedCollectionInsertionAndResorting
    | values comparator |
    values := SortedCollection withAll: #(5 3 1 3).
    values add: 2; addAll: #(4 0).
    self assert: values asArray equals: #(0 1 2 3 3 4 5).
    comparator := [ :left :right | left > right ].
    values sortBlock: comparator.
    self assert: values asArray equals: #(5 4 3 3 2 1 0).
    self assert: values sortBlock == comparator.
    self assert: (values add: 3) equals: 3.
    self assert: values removeFirst equals: 5.
    self assert: values removeLast equals: 0.
    self assert: values asArray equals: #(4 3 3 3 2 1).
    self assert: ([ values sortBlock: [ :left :right | Error signal ]. false ]
        on: Error do: [ :exception | true ]).
    self assert: values sortBlock == comparator.
    self assert: values asArray equals: #(4 3 3 3 2 1)'.

ANSISmalltalkTest compile: 'testSortedCollectionResultsKeepTheirRequiredOrdering
    | values filtered replaced mapped |
    values := #(3 2 1 2) asSortedCollection: [ :left :right | left > right ].
    filtered := values select: [ :each | each odd ].
    self assert: filtered class equals: SortedCollection.
    self assert: filtered asArray equals: #(3 1).
    replaced := values copyReplaceFrom: 1 to: 2 with: #(0 9).
    self assert: replaced asArray equals: #(9 2 1 0).
    self assert: replaced sortBlock == values sortBlock.
    mapped := values collect: [ :each | each negated ].
    self assert: mapped class equals: OrderedCollection.
    self assert: mapped asArray equals: #(-3 -2 -2 -1).
    self assert: values reverse asArray equals: #(1 2 2 3).
    self deny: (values respondsTo: #at:put:)'.

ANSISmalltalkTest compile: 'testCollectionConversions
    | source descending |
    source := OrderedCollection withAll: #(3 1 3 0).
    self assert: source asBag class equals: Bag.
    self assert: (source asBag occurrencesOf: 3) equals: 2.
    self assert: source asSet class equals: Set.
    self assert: source asSet size equals: 3.
    self assert: source asSet asOrderedCollection class equals: OrderedCollection.
    self assert: source asByteArray class equals: ByteArray.
    self assert: source asByteArray asArray equals: #(3 1 3 0).
    self assert: source asSortedCollection asArray equals: #(0 1 3 3).
    descending := source asSortedCollection: [ :left :right | left > right ].
    self assert: descending asArray equals: #(3 3 1 0).
    self assert: descending asSortedCollection sortBlock == descending sortBlock.
    self assert: ([ #(0 256) asByteArray. false ] on: Error do: [ :exception | true ])'.

ANSISmalltalkTest compile: 'testDictionaryUsesEquivalentKeys
    | table first equivalent |
    table := Dictionary new: 16.
    self assert: table isEmpty.
    first := Array with: #key.
    equivalent := Array with: #key.
    self deny: first == equivalent.
    self assert: (table at: first put: 7) equals: 7.
    self assert: (table at: equivalent) equals: 7.
    table at: equivalent put: 42.
    self assert: table size equals: 1.
    self assert: (table at: first) equals: 42.
    self assert: (table includesKey: equivalent).
    self assert: (table removeKey: equivalent) equals: 42.
    self deny: (table includesKey: first)'.

ANSISmalltalkTest compile: 'testIdentityDictionaryKeepsEquivalentKeysSeparate
    | table first second query copied |
    first := String withAll: ''key''.
    second := first copy.
    query := first copy.
    table := IdentityDictionary new: 4.
    table at: first put: 1; at: second put: 2.
    self assert: first equals: second.
    self deny: first == second.
    self assert: table size equals: 2.
    self assert: table keys size equals: 2.
    self assert: (table at: first) equals: 1.
    self assert: (table at: second) equals: 2.
    self assert: (table at: query ifAbsent: [ 42 ]) equals: 42.
    copied := IdentityDictionary withAll: table.
    self assert: copied size equals: 2.
    self assert: (copied at: first) equals: 1.
    self assert: (table removeKey: first) equals: 1.
    self assert: (table at: second) equals: 2.
    table at: second put: (Array with: 7).
    self assert: (table includes: (Array with: 7)).
    self assert: (table keyAtValue: (Array with: 7)) == second'.

ANSISmalltalkTest compile: 'testDictionaryDistinguishesNilValuesFromAbsentKeys
    | table calls answer |
    table := Dictionary new.
    calls := 0.
    table at: #stored put: nil.
    self assert: (table includesKey: #stored).
    self assert: (table at: #stored ifAbsent: [ calls := calls + 1 ]) isNil.
    self assert: (table at: #stored ifAbsentPut: [ calls := calls + 1 ]) isNil.
    self assert: calls equals: 0.
    answer := table at: #missing ifAbsentPut: [ calls := calls + 1. 42 ].
    self assert: answer equals: 42.
    self assert: (table at: #missing ifAbsentPut: [ calls := calls + 1 ]) equals: 42.
    self assert: calls equals: 1.
    self assert: (table removeKey: #stored ifAbsent: [ calls := calls + 1 ]) isNil.
    self deny: (table includesKey: #stored).
    self assert: calls equals: 1'.

ANSISmalltalkTest compile: 'testDictionaryEnumeratesKeysAndValues
    | table seen keys sum |
    table := Dictionary new at: #a put: 7; at: #b put: 7; at: #c put: 3; yourself.
    seen := Dictionary new.
    keys := Set new.
    table keysAndValuesDo: [ :key :value | seen at: key put: value ].
    table keysDo: [ :key | keys add: key ].
    self assert: keys size equals: 3.
    self assert: (keys includes: #c).
    self assert: (seen at: #a) equals: 7.
    self assert: (seen at: #c) equals: 3.
    sum := table inject: 0 into: [ :total :value | total + value ].
    self assert: sum equals: 17.
    self assert: table values size equals: 3.
    self assert: (table occurrencesOf: 7) equals: 2.
    self assert: (table keyAtValue: 3) equals: #c.
    self assert: (table keyAtValue: 42 ifAbsent: [ #absent ]) equals: #absent'.

ANSISmalltalkTest compile: 'testDictionaryCollectionOperationsPreserveKeysAndType
    | dictionary first second mapped selected rejected |
    first := Array with: 7.
    second := Array with: 7.
    dictionary := IdentityDictionary new at: first put: 2; at: second put: 3; yourself.
    mapped := dictionary collect: [ :value | value squared ].
    selected := dictionary select: [ :value | value even ].
    rejected := dictionary reject: [ :value | value even ].
    self assert: mapped class equals: IdentityDictionary.
    self assert: selected class equals: IdentityDictionary.
    self assert: rejected class equals: IdentityDictionary.
    self assert: mapped size equals: 2.
    self assert: (mapped at: first) equals: 4.
    self assert: (mapped at: second) equals: 9.
    self deny: (selected includesKey: second).
    self assert: (selected at: first) equals: 2.
    self assert: (rejected at: second) equals: 3'.

ANSISmalltalkTest compile: 'testDictionaryCopiesMergesAndRemovesKeyGroups
    | original copy updates missing |
    original := Dictionary new at: #a put: 1; at: #b put: 2; yourself.
    copy := Dictionary withAll: original.
    updates := Dictionary new at: #b put: 42; at: #c put: 3; yourself.
    copy addAll: updates.
    self assert: (original at: #b) equals: 2.
    self assert: (copy at: #b) equals: 42.
    self assert: copy size equals: 3.
    missing := OrderedCollection new.
    copy removeAllKeys: #(missing a c) ifAbsent: [ :key | missing add: key ].
    self assert: missing asArray equals: #(missing).
    self assert: copy keys equals: #(b).
    original removeAllKeys: #(a b).
    self assert: original isEmpty'.

ANSISmalltalkTest compile: 'testDictionaryEnumerationVisitsASnapshot
    | table seen |
    table := Dictionary new at: #a put: 1; at: #b put: 2; yourself.
    seen := Dictionary new.
    table keysAndValuesDo: [ :key :value |
        seen at: key put: value.
        table at: #b put: 99.
        table at: #new put: 42 ].
    self assert: seen size equals: 2.
    self assert: (seen at: #b) equals: 2.
    self assert: (table at: #b) equals: 99.
    self assert: (table at: #new) equals: 42'.

ANSISmalltalkTest compile: 'testReadStreamPeekAndPosition
    | stream empty |
    stream := ReadStream on: #(nil 7 8).
    empty := ReadStream on: #().
    self assert: empty isEmpty.
    self assert: empty atEnd.
    self assert: empty peek isNil.
    self deny: (empty peekFor: nil).
    self assert: (stream peekFor: nil).
    self assert: stream position equals: 0.
    self assert: stream next isNil.
    self deny: (stream nextMatchFor: 42).
    self assert: stream position equals: 2.
    self assert: stream next equals: 8.
    self assert: stream atEnd.
    self deny: stream isEmpty.
    stream reset.
    stream position: 1.
    self assert: stream peek equals: 7.
    stream skip: 100.
    self assert: stream atEnd.
    self assert: stream position equals: 3.
    self assert: ([ stream position: 3. false ] on: Error do: [ :exception | true ]).
    stream reset; setToEnd.
    self assert: stream atEnd'.

ANSISmalltalkTest compile: 'testReadStreamSlicesAndDelimiters
    | text bytes prefix |
    text := ReadStream on: ''ab,cd;ef''.
    self assert: (text next: 0) class equals: String.
    self assert: (text upTo: $,) equals: ''ab''.
    self assert: text position equals: 3.
    self assert: (text skipTo: $;).
    self assert: (text upTo: $!) equals: ''ef''.
    self assert: text atEnd.
    self assert: (text upTo: $!) equals: ''''.
    self assert: text contents equals: ''ab,cd;ef''.
    bytes := ReadStream on: (ByteArray with: 1 with: 2 with: 255).
    prefix := bytes next: 2.
    self assert: prefix class equals: ByteArray.
    self assert: prefix asArray equals: #(1 2).
    self assert: (bytes next: 8) asArray equals: #(255).
    self assert: bytes atEnd'.

ANSISmalltalkTest compile: 'testReadStreamNextLineSupportsCommonLineEndings
    | text stream line |
    text := ''one'' , (String with: Character cr with: Character lf)
        , ''two'' , Character cr asString
        , ''three'' , Character lf asString , ''four''.
    stream := ReadStream on: text.
    self assert: stream nextLine equals: ''one''.
    self assert: stream nextLine equals: ''two''.
    self assert: stream nextLine equals: ''three''.
    self assert: stream nextLine equals: ''four''.
    self assert: stream atEnd.
    line := ReadStream on: (String with: Character lf).
    self assert: line nextLine equals: ''''.
    self assert: line atEnd'.

ANSISmalltalkTest compile: 'testWriteStreamOverwritesAndAppendsWithoutWriteBack
    | original writer snapshot |
    original := String withAll: ''café''.
    writer := WriteStream with: original.
    self assert: writer position equals: 4.
    writer nextPut: $!.
    writer position: 2.
    writer nextPut: $猫.
    self assert: writer contents equals: ''ca猫é!''.
    writer setToEnd; space; tab; cr; flush.
    self assert: writer contents equals: (''ca猫é!'' , (String with: Character space with: Character tab with: Character lf)).
    self assert: original equals: ''café''.
    snapshot := writer contents.
    snapshot at: 1 put: $x.
    self assert: writer contents first equals: $c.
    self deny: (writer respondsTo: #next)'.

ANSISmalltalkTest compile: 'testWriteStreamValidatesAByteBatchBeforeWriting
    | writer bytes |
    writer := WriteStream with: (ByteArray with: 0 with: 255).
    writer position: 1.
    self assert: ([ writer nextPutAll: #(8 256). false ]
        on: Error do: [ :exception | true ]).
    self assert: writer position equals: 1.
    self assert: writer contents asArray equals: #(0 255).
    writer nextPutAll: #(12 13).
    bytes := writer contents.
    self assert: bytes class equals: ByteArray.
    self assert: bytes asArray equals: #(0 12 13).
    self assert: writer position equals: 3'.

ANSISmalltalkTest compile: 'testReadWriteStreamMovesBetweenReadingAndWriting
    | stream initial replay |
    initial := OrderedCollection with: 1 with: 2 with: 3.
    stream := ReadWriteStream with: initial.
    self assert: stream atEnd.
    stream reset.
    self assert: stream next equals: 1.
    stream nextPut: 42.
    self assert: stream next equals: 3.
    self assert: stream atEnd.
    stream nextPut: nil.
    self assert: stream contents class equals: OrderedCollection.
    self assert: stream contents asArray equals: #(1 42 3 nil).
    self assert: initial asArray equals: #(1 2 3).
    replay := OrderedCollection new.
    stream reset; do: [ :each | replay add: each ].
    self assert: replay asArray equals: #(1 42 3 nil).
    self assert: stream atEnd.
    stream := ReadWriteStream on: (Array with: 9).
    self assert: stream next equals: 9'.

ANSISmalltalkTest compile: 'testWriteStreamAcceptsObjectAndRadixPrinting
    | writer |
    writer := WriteStream with: String new.
    ''hi'' printOn: writer.
    writer space.
    255 printOn: writer base: 16 showRadix: true.
    self assert: writer contents equals: (''hi'' printString , '' 16rFF'').
    writer close.
    self assert: ([ writer nextPut: $x. false ] on: Error do: [ :exception | true ])'.

ANSISmalltalkTest compile: 'testDurationComponentsAndPrinting
    | duration |
    duration := Duration days: -3 hours: -5 minutes: -4 seconds: ( -5 / 2 ).
    self assert: duration days equals: -3.
    self assert: duration hours equals: -5.
    self assert: duration minutes equals: -4.
    self assert: duration seconds equals: (-5 / 2).
    self assert: duration printString equals: ''-3:05:04:02.5''.
    self assert: duration abs printString equals: ''3:05:04:02.5''.
    self assert: Duration zero printString equals: ''0:00:00:00''.
    self assert: Duration zero positive.
    self deny: Duration zero negative.
    self assert: (Duration seconds: (1 / 3)) seconds equals: (1 / 3).
    self assert: (Duration seconds: (1 / 3)) printString
        equals: ''0:00:00:00.333333333333333333333333333333'''.

ANSISmalltalkTest compile: 'testDurationArithmeticAndOrdering
    | a b |
    a := Duration seconds: (1 / 3).
    b := Duration seconds: 0.25s2.
    self assert: (a + b) asSeconds equals: (7 / 12).
    self assert: (a - b) asSeconds equals: (1 / 12).
    self assert: (a * 3) asSeconds equals: 1.
    self assert: (b * 2.0) asSeconds equals: (1 / 2).
    self assert: (b / 2) asSeconds equals: (1 / 8).
    self assert: a / b equals: (4 / 3).
    self assert: b < a.
    self assert: b <= b copy.
    self assert: a > b.
    self assert: a >= b.
    self assert: (b between: Duration zero and: a).
    self assert: (b min: a) == b.
    self assert: (b max: a) == a.
    self assert: b equals: (Duration seconds: (1 / 4)).
    self deny: b ~= (Duration seconds: (1 / 4)).
    self deny: b = (1 / 4).
    self assert: b hash equals: (Duration seconds: (1 / 4)) hash.
    self assert: ([ a / 0 ] on: ZeroDivide do: [ :exception | #caught ]) equals: #caught.
    self assert: ([ a / Duration zero ] on: ZeroDivide do: [ :exception | exception dividend ])
        equals: (1 / 3)'.

ANSISmalltalkTest compile: 'testDateAndTimeCalendarAndTimeOfDay
    | date |
    date := DateAndTime year: 2024 month: 2 day: 29 hour: 20 minute: 4 second: 5.125s3.
    self assert: date year equals: 2024.
    self assert: date month equals: 2.
    self assert: date monthName equals: ''February''.
    self assert: date monthAbbreviation equals: ''Feb''.
    self assert: date dayOfMonth equals: 29.
    self assert: date dayOfYear equals: 60.
    self assert: date dayOfWeek equals: 5.
    self assert: date dayOfWeekName equals: ''Thursday''.
    self assert: date dayOfWeekAbbreviation equals: ''Thu''.
    self assert: date isLeapYear.
    self assert: date hour equals: 20.
    self assert: date hour24 equals: 20.
    self assert: date hour12 equals: 8.
    self assert: date meridianAbbreviation equals: ''PM''.
    self assert: date minute equals: 4.
    self assert: date second equals: (41 / 8).
    self assert: date printString equals: '' 2024-02-29T20:04:05.125+00:00''.
    self assert: date equals: (DateAndTime year: 2024 day: 60 hour: 20 minute: 4 second: (41 / 8))'.

ANSISmalltalkTest compile: 'testDateAndTimeOffsetsAndComparison
    | date utc next offset |
    offset := Duration days: 0 hours: 5 minutes: 45 seconds: (1 / 2).
    date := DateAndTime year: 2024 day: 1 hour: 0 minute: 0 second: (1 / 4) offset: offset.
    utc := date asUTC.
    self assert: date offset equals: offset.
    self assert: utc offset equals: Duration zero.
    self assert: utc equals: date.
    self deny: utc ~= date.
    self assert: utc hash equals: date hash.
    self assert: date asLocal printString equals: utc printString.
    self assert: utc dayOfWeek equals: 1.
    self assert: utc hour12 equals: 6.
    self assert: utc timeZoneName equals: ''UTC''.
    self assert: date timeZoneAbbreviation equals: ''UTC+05:45:00.5''.
    self assert: date printString equals: '' 2024-01-01T00:00:00.25+05:45:00.5''.
    self assert: utc printString equals: '' 2023-12-31T18:14:59.75+00:00''.
    self assert: (utc offset: offset) printString equals: date printString.
    next := date + (Duration seconds: (1 / 3)).
    self assert: next offset equals: offset.
    self assert: (next - date) asSeconds equals: (1 / 3).
    self assert: (next - (Duration seconds: (1 / 3))) equals: date.
    self assert: date < next.
    self assert: date <= utc.
    self assert: next > utc.
    self assert: next >= date.
    self assert: (utc between: date and: next).
    self assert: (next min: date) == date.
    self assert: (date max: next) == next.
    self deny: date = Duration zero'.

ANSISmalltalkTest compile: 'testDateAndTimeAcrossGregorianBoundaries
    | ancient epoch previous distant century reform |
    ancient := DateAndTime year: -1199 month: 1 day: 5 hour: 20 minute: 33 second: 14.321s3
        offset: (Duration seconds: -18000).
    self assert: ancient printString equals: ''-1199-01-05T20:33:14.321-05:00''.
    epoch := DateAndTime year: 1 day: 1 hour: 0 minute: 0 second: 0.
    self assert: epoch dayOfWeek equals: 2.
    self assert: epoch hour12 equals: 12.
    self assert: epoch meridianAbbreviation equals: ''AM''.
    previous := epoch - (Duration seconds: 1).
    self assert: previous year equals: 0.
    self assert: previous dayOfYear equals: 366.
    self assert: previous isLeapYear.
    self assert: previous printString equals: '' 0000-12-31T23:59:59+00:00''.
    century := DateAndTime year: 1900 day: 60 hour: 0 minute: 0 second: 0.
    self deny: century isLeapYear.
    self assert: century month equals: 3.
    self assert: (DateAndTime year: 2000 day: 60 hour: 0 minute: 0 second: 0) month equals: 2.
    reform := DateAndTime year: 1582 month: 10 day: 15 hour: 0 minute: 0 second: 0.
    self assert: (reform - (Duration seconds: 86400)) dayOfMonth equals: 14.
    distant := DateAndTime year: -10000000000000000000400 day: 60 hour: 0 minute: 0 second: 0.
    self assert: distant year equals: -10000000000000000000400.
    self assert: distant month equals: 2.
    self assert: distant dayOfMonth equals: 29.
    self assert: (distant + (Duration seconds: 86400)) dayOfMonth equals: 1'.

ANSISmalltalkTest compile: 'testDateAndTimeRejectsOutOfRangeComponents
    | invalid |
    invalid := Array
        with: [ DateAndTime year: 1900 month: 2 day: 29 hour: 0 minute: 0 second: 0 ]
        with: [ DateAndTime year: 2023 day: 366 hour: 0 minute: 0 second: 0 ]
        with: [ DateAndTime year: 2024 day: 1 hour: 24 minute: 0 second: 0 ]
        with: [ DateAndTime year: 2024 day: 1 hour: 0 minute: 0 second: 60 ].
    invalid do: [ :each |
        self assert: ([ each value. false ] on: Error do: [ :exception | true ]) ].
    self assert: ([
        DateAndTime year: 2024 day: 0 hour: 0 minute: 0 second: 0. false ]
        on: Error do: [ :exception | true ]).
    self assert: ([
        DateAndTime year: 2024 month: 13 day: 1 hour: 0 minute: 0 second: 0. false ]
        on: Error do: [ :exception | true ]).
    self assert: ([
        DateAndTime year: 2024 month: 1 day: 1 hour: 0 minute: -1 second: 0. false ]
        on: Error do: [ :exception | true ]).
    self assert: ([
        DateAndTime year: 2024 day: 1 hour: 0 minute: 0 second: -0.5. false ]
        on: Error do: [ :exception | true ]).
    self assert: ([
        DateAndTime now offset: (Duration seconds: 86401). false ]
        on: Error do: [ :exception | true ])'.

ANSISmalltalkTest compile: 'testDateAndTimeClock
    | now precision |
    now := DateAndTime now.
    precision := DateAndTime clockPrecision.
    self assert: now class equals: DateAndTime.
    self assert: now offset equals: Duration zero.
    self assert: (now second >= 0 and: [ now second < 60 ]).
    self assert: precision class equals: Duration.
    self assert: precision asSeconds > 0'.

ANSISmalltalkTest compile: 'testNotificationDefaultsToNilAndContinues
    | answer after |
    answer := Notification signal: ''A notification''.
    after := 42.
    self assert: answer isNil.
    self assert: after equals: 42.
    self assert: Notification new isResumable.
    self assert: Notification superclass == Exception'.

ANSISmalltalkTest compile: 'testNotificationResumeReturnsToTheSignal
    | result |
    result := [ (Notification signal: ''Resume here'') + 2 ] on: Notification do: [ :exception |
        self assert: exception messageText equals: ''Resume here''.
        self assert: exception tag equals: ''Resume here''.
        exception resume: 40 ].
    self assert: result equals: 42'.

ANSISmalltalkTest compile: 'testWarningUsesTheNearestHandlerAndCanResume
    | result |
    self assert: Warning superclass == Notification.
    self assert: Warning new isResumable.
    self deny: (Error handles: Warning new).
    self assert: (Notification handles: Warning new).
    result := [
        [ (Warning signal: ''First handler'') + 2 ] on: Warning do: [ :exception |
            self assert: exception isNested.
            exception resume: 40 ]
    ] on: Notification do: [ :exception | self fail: ''The outer handler ran.'' ].
    self assert: result equals: 42'.

ANSISmalltalkTest compile: 'testWarningCanPassToANotificationHandler
    | result |
    result := [
        [ (Warning signal: ''Pass outward'') + 2 ] on: Warning do: [ :exception | exception pass ]
    ] on: Notification do: [ :exception |
        self assert: exception class == Warning.
        exception resume: 40 ].
    self assert: result equals: 42'.

ANSISmalltalkTest compile: 'testWarningSubclassCanDefineItsDefaultAction
    self assert: ANSIProbeWarning signal equals: #customWarning.
    self assert: ([ ANSIProbeWarning signal ] on: Warning do: [ :exception | exception class ])
        equals: ANSIProbeWarning'.

ANSISmalltalkTest compile: 'testSequenceEqualityUsesClassSizeAndIndexedElements
    | bytes ordered sorted descending interval |
    bytes := ByteArray with: 0 with: 2.
    self assert: bytes equals: ((ByteArray new: 2) at: 2 put: 2; yourself).
    self assert: bytes hash equals: (ByteArray with: 0 with: 2) hash.
    self deny: bytes = #(0 2).
    ordered := OrderedCollection with: 3 with: 2.
    self assert: ordered equals: (OrderedCollection with: 3 with: 2).
    self deny: ordered = (OrderedCollection with: 2 with: 3).
    self deny: ordered = (OrderedCollection with: 3).
    self deny: ordered == ordered copy.
    sorted := SortedCollection with: 3 with: 2.
    descending := (SortedCollection sortBlock: [ :left :right | left > right ]) add: 2; add: 3; yourself.
    self assert: sorted equals: (SortedCollection with: 2 with: 3).
    self deny: sorted = descending.
    interval := 1 to: 7 by: 2.
    self assert: interval equals: (1 to: 8 by: 2).
    self assert: interval hash equals: (1 to: 8 by: 2) hash.
    self deny: interval = #(1 3 5 7).
    self deny: interval = (1 to: 10 by: 3).
    self deny: (1 to: 1000000000000000000000) = (2 to: 1000000000000000000001)'.

ANSISmalltalkTest compile: 'testSequenceKeysRespectValueOrIdentityLookup
    | first equivalent dictionary identities |
    first := OrderedCollection with: (ByteArray with: 1).
    equivalent := OrderedCollection with: (ByteArray with: 1).
    dictionary := Dictionary new at: first put: 42; yourself.
    identities := IdentityDictionary new at: first put: 42; yourself.
    self assert: (dictionary at: equivalent) equals: 42.
    self deny: (identities includesKey: equivalent).
    self assert: (identities at: first) equals: 42'.

ANSISmalltalkTest compile: 'testArrayComparisonAndMembershipSendElementEquality
    | first equivalent different |
    first := ANSIEqualityProbe new value: 7; yourself.
    equivalent := ANSIEqualityProbe new value: 7; yourself.
    different := ANSIEqualityProbe new value: 8; yourself.
    self assert: first = equivalent.
    self deny: first ~= equivalent.
    self assert: first ~= different.
    self assert: first ~~ equivalent.
    self assert: (Array with: first) equals: (Array with: equivalent).
    self assert: ((Array with: first) includes: equivalent).
    self deny: ((Array with: first) includes: different).
    self assert: (Set with: first with: equivalent) size equals: 1'.

ANSISmalltalkTest compile: 'testStringEqualityAndMembershipUseCharacterElements
    | composed decomposed |
    composed := String with: (Character codePoint: 233).
    decomposed := String with: $e with: (Character codePoint: 769).
    self assert: composed size equals: 1.
    self assert: decomposed size equals: 2.
    self deny: composed = decomposed.
    self deny: composed asSymbol == decomposed asSymbol.
    self assert: composed hash equals: composed copy hash.
    self assert: (decomposed includes: $e).
    self deny: (decomposed includes: composed first)'.

ANSISmalltalkTest compile: 'testCyclicSequencesRetainStructuralEquality
    | left right leftArray rightArray |
    leftArray := Array new: 1.
    rightArray := Array new: 1.
    left := OrderedCollection with: leftArray with: 7.
    right := OrderedCollection with: rightArray with: 7.
    leftArray at: 1 put: left.
    rightArray at: 1 put: right.
    self assert: left equals: right.
    self assert: left hash equals: right hash.
    self assert: leftArray equals: rightArray.
    right at: 2 put: 8.
    self assert: left ~= right.
    self deny: leftArray = rightArray'.
