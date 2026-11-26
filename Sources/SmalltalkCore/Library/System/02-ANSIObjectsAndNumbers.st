"ANSI fundamental and numeric protocols (J20 5.3 and 5.6)."

Object compile: 'isKindOf: candidate
    | type |
    type := self class.
    [ type notNil ] whileTrue: [
        type == candidate ifTrue: [ ^ true ].
        type := type superclass ].
    ^ false'.

Object compile: 'isMemberOf: candidate
    ^ self class == candidate'.

Object compile: 'printOn: target
    target nextPutAll: self printString'.

Object compile: 'doesNotUnderstand: message
    ^ (MessageNotUnderstood new receiver: self message: message) signal'.

Number compile: 'between: lower and: upper
    ^ self >= lower and: [ self <= upper ]'.

Number compile: 'min: other
    self <= other ifTrue: [ ^ self ].
    ^ other'.

Number compile: 'max: other
    self >= other ifTrue: [ ^ self ].
    ^ other'.

Number compile: 'asInteger
    ^ self rounded'.

Number compile: 'fractionPart
    ^ self \\ 1'.

Number compile: 'negative
    ^ self < 0'.

Number compile: 'positive
    ^ self >= 0'.

Number compile: 'strictlyPositive
    ^ self > 0'.

Number compile: 'sign
    self < 0 ifTrue: [ ^ -1 ].
    self > 0 ifTrue: [ ^ 1 ].
    ^ 0'.

Number compile: 'quo: divisor
    | quotient |
    quotient := self // divisor.
    (quotient < 0 and: [ (self \\ divisor) ~= 0 ]) ifTrue: [ ^ quotient + 1 ].
    ^ quotient'.

Number compile: 'rem: divisor
    ^ self - ((self quo: divisor) * divisor)'.

Number compile: 'reciprocal
    ^ 1 / self'.

Number compile: 'roundTo: factor
    ^ (self / factor) rounded * factor'.

Number compile: 'truncateTo: factor
    ^ (self quo: factor) * factor'.

Number compile: 'raisedTo: exponent
    (exponent isKindOf: Integer) ifTrue: [ ^ self raisedToInteger: exponent ].
    self < 0 ifTrue: [ self error: ''A negative base requires an integer exponent.'' ].
    self = 0 ifTrue: [
        exponent > 0 ifTrue: [ ^ 0.0 ].
        self error: ''Zero requires a positive exponent.'' ].
    ^ (self asFloat ln * exponent) exp'.

Number compile: 'raisedToInteger: exponent
    | power factor result |
    (exponent isKindOf: Integer) ifFalse: [ self error: ''Expected an integer exponent.'' ].
    power := exponent abs.
    factor := self.
    result := self * 0 + 1.
    [ power > 0 ] whileTrue: [
        power odd ifTrue: [ result := result * factor ].
        power := power // 2.
        power > 0 ifTrue: [ factor := factor squared ] ].
    exponent < 0 ifTrue: [ ^ result reciprocal ].
    ^ result'.

Integer compile: 'sqrt ^ self asFloat sqrt'.
Fraction compile: 'sqrt ^ self asFloat sqrt'.
ScaledDecimal compile: 'sqrt ^ self asFloat sqrt'.

Integer compile: 'ceiling ^ self'.
Integer compile: 'floor ^ self'.
Integer compile: 'rounded ^ self'.
Integer compile: 'truncated ^ self'.
Integer compile: 'asFraction ^ self'.
Integer compile: 'integerPart ^ self'.

Integer compile: 'even
    ^ (self bitAnd: 1) = 0'.

Integer compile: 'odd
    ^ self even not'.

Integer compile: 'allMask: mask
    ^ (self bitAnd: mask) = mask'.

Integer compile: 'anyMask: mask
    ^ (self bitAnd: mask) ~= 0'.

Integer compile: 'noMask: mask
    ^ (self bitAnd: mask) = 0'.

Integer compile: 'factorial
    | result |
    self < 0 ifTrue: [ self error: ''Factorial requires a nonnegative integer.'' ].
    result := 1.
    2 to: self do: [ :factor | result := result * factor ].
    ^ result'.

Integer compile: 'gcd: other
    | a b remainder |
    a := self abs.
    b := other abs.
    (b isKindOf: Integer) ifFalse: [ self error: ''Expected an integer.'' ].
    [ b ~= 0 ] whileTrue: [
        remainder := a \\ b.
        a := b.
        b := remainder ].
    ^ a'.

Integer compile: 'lcm: other
    | divisor |
    divisor := self gcd: other.
    divisor = 0 ifTrue: [ ^ 0 ].
    ^ ((self // divisor) * other) abs'.

Integer compile: 'printOn: output base: base showRadix: showRadix
    | digits |
    showRadix ifFalse: [ ^ output nextPutAll: (self printStringRadix: base) ].
    digits := self abs printStringRadix: base.
    self < 0 ifTrue: [ output nextPut: $- ].
    output nextPutAll: base printString; nextPut: $r; nextPutAll: digits'.

Fraction compile: 'asFraction ^ self'.
Fraction compile: 'integerPart ^ self floor'.

Float compile: 'integerPart
    ^ self floor asFloat'.

Float compile: 'degreesToRadians
    ^ self * Float pi / 180'.

Float compile: 'radiansToDegrees
    ^ self * 180 / Float pi'.

Float compile: 'log: base
    ^ self ln / base ln'.

Float compile: 'floorLog: base
    ^ (self log: base) floor'.

Transcript compile: 'nextPut: character
    (character isKindOf: Character) ifFalse: [ self error: ''Transcript expects a character.'' ].
    character = Character cr ifTrue: [ ^ self cr ].
    self show: character asString'.

Transcript compile: 'nextPutAll: characters
    ((characters isKindOf: String) and: [ (characters includes: Character cr) not ])
        ifTrue: [ ^ self show: characters ].
    characters do: [ :character | self nextPut: character ]'.

Transcript compile: 'space
    self nextPut: Character space'.

Transcript compile: 'tab
    self nextPut: Character tab'.

Transcript compile: 'flush
    ^ self'.

Number compile: 'to: stop
    ^ Interval from: self to: stop'.

Number compile: 'to: stop by: step
    ^ Interval from: self to: stop by: step'.

Fraction compile: 'to: stop do: operation
    (self to: stop) do: operation'.

Fraction compile: 'to: stop by: step do: operation
    (self to: stop by: step) do: operation'.

ScaledDecimal compile: 'to: stop do: operation
    (self to: stop) do: operation'.

ScaledDecimal compile: 'to: stop by: step do: operation
    (self to: stop by: step) do: operation'.

Float compile: 'to: stop do: operation
    (self to: stop) do: operation'.

Float compile: 'to: stop by: step do: operation
    (self to: stop by: step) do: operation'.
