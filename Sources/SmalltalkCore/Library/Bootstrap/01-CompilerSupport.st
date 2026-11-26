"Mutable buffer for token contents and syntax nodes."

Object subclass: #STCompilerList instanceVariableNames: 'storage count'.

STCompilerList compile: 'initialize
    storage := Array new: 8.
    count := 0'.

STCompilerList compile: 'add: element
    | grown |
    count = storage size ifTrue: [
        grown := Array new: storage size * 2.
        1 to: count do: [ :each | grown at: each put: (storage at: each) ].
        storage := grown ].
    count := count + 1.
    storage at: count put: element'.

STCompilerList compile: 'elements
    | result |
    result := Array new: count.
    1 to: count do: [ :each | result at: each put: (storage at: each) ].
    ^ result'.

STCompilerList compile: 'joinedString
    ^ storage joinedStringFrom: 1 to: count'.
