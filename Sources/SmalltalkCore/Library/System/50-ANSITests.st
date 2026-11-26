"Behavior from the ANSI Smalltalk draft (J20 revision 1.9)."

Object subclass: #ANSIDispatchProbe instanceVariableNames: ''.

ANSIDispatchProbe compile: 'touch
    42'.

ANSIDispatchProbe compile: 'doesNotUnderstand: aMessage
    ^ aMessage'.

ANSIDispatchProbe compile: 'handles: anException
    ^ anException messageText = ''selected'''.

Error subclass: #ANSIProbeError instanceVariableNames: ''.
Exception subclass: #ANSIProbeException instanceVariableNames: ''.

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
