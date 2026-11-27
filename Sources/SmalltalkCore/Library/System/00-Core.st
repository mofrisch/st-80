"The small source-level core. Primitive operations stay in the host VM."
Object compile: 'initialize
    ^ self'.

"ANSI <failedMessage> protocol (§5.3.6). The global Message is the
standard name; FailedMessage remains a synonym for Smalltalk-80 callers."
Object subclass: #Message instanceVariableNames: 'selector arguments'.
Message compile: 'selector
    ^ selector'.
Message compile: 'arguments
    ^ arguments'.

Character compileClass: 'codePoint: point
    ^ point asCharacter'.
Character compileClass: 'cr
    ^ self codePoint: 13'.
Character compileClass: 'lf
    ^ self codePoint: 10'.
Character compileClass: 'space
    ^ self codePoint: 32'.
Character compileClass: 'tab
    ^ self codePoint: 9'.

"ANSI allows a single float format. FloatE/FloatD/FloatQ are aliases of
Float and share this IEEE 754 binary64 characterization."
Float compileClass: 'radix ^ 2'.
Float compileClass: 'precision ^ 53'.
Float compileClass: 'emin ^ -1021'.
Float compileClass: 'emax ^ 1024'.
Float compileClass: 'denormalized ^ true'.
Float compileClass: 'epsilon ^ 2.220446049250313e-16'.
Float compileClass: 'fmax ^ 1.7976931348623157e308'.
Float compileClass: 'fmin ^ self fminNormalized'.
Float compileClass: 'fminNormalized ^ 2.2250738585072014e-308'.
Float compileClass: 'fminDenormalized ^ 4.9406564584124654e-324'.
Float compileClass: 'pi ^ 3.141592653589793'.
Float compileClass: 'e ^ 2.718281828459045'.

Fraction compileClass: 'numerator: top denominator: bottom
    ^ self _fractionNumerator: top denominator: bottom'.

Array compileClass: 'with: first
    ^ (self new: 1) at: 1 put: first; yourself'.
Array compileClass: 'with: first with: second
    ^ (self new: 2) at: 1 put: first; at: 2 put: second; yourself'.
Array compileClass: 'with: first with: second with: third
    ^ (self new: 3) at: 1 put: first; at: 2 put: second; at: 3 put: third; yourself'.
Array compileClass: 'with: first with: second with: third with: fourth
    ^ (self new: 4) at: 1 put: first; at: 2 put: second; at: 3 put: third; at: 4 put: fourth; yourself'.
Array compileClass: 'withAll: elements
    | result index |
    result := self new: elements size.
    index := 1.
    elements do: [ :each | result at: index put: each. index := index + 1 ].
    ^ result'.

Array compile: 'at: index ifAbsent: alternative
    (index < 1 or: [ index > self size ]) ifTrue: [ ^ alternative value ].
    ^ self at: index'.
Array compile: 'first
    ^ self at: 1'.
Array compile: 'last
    ^ self at: self size'.
Array compile: 'copyFrom: start to: stop
    | result |
    stop < start ifTrue: [ ^ self class new ].
    self at: start; at: stop.
    result := self class new: stop - start + 1.
    start to: stop do: [ :index | result at: index - start + 1 put: (self at: index) ].
    ^ result'.
Array compile: 'reverse
    | result |
    result := self class new: self size.
    1 to: self size do: [ :index | result at: self size - index + 1 put: (self at: index) ].
    ^ result'.

Integer compile: 'min: other
    self < other ifTrue: [ ^ self ].
    ^ other'.
Integer compile: 'max: other
    self > other ifTrue: [ ^ self ].
    ^ other'.
Integer compile: 'clampFrom: lower to: upper
    ^ (self max: lower) min: upper'.

Object subclass: #Counter instanceVariableNames: 'count'.
Counter compile: 'initialize
    count := 0'.
Counter compile: 'increment
    count := count + 1'.
Counter compile: 'add: amount
    count := count + amount'.
Counter compile: 'value
    ^ count'.
