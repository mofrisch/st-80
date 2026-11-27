"ANSI collection, indexed access and text protocols (J20 5.7)."

Collection compile: 'allSatisfy: predicate
    self do: [ :each | (predicate value: each) ifFalse: [ ^ false ] ].
    ^ true'.

Collection compile: 'anySatisfy: predicate
    self do: [ :each | (predicate value: each) ifTrue: [ ^ true ] ].
    ^ false'.

Collection compile: 'asArray
    ^ Array withAll: self'.

Collection compile: 'detect: predicate
    ^ self detect: predicate ifNone: [ self error: ''No matching element.'' ]'.

Collection compile: 'detect: predicate ifNone: alternative
    self do: [ :each | (predicate value: each) ifTrue: [ ^ each ] ].
    ^ alternative value'.

Collection compile: 'do: operation separatedBy: separator
    | first |
    first := true.
    self do: [ :each |
        first ifTrue: [ first := false ] ifFalse: [ separator value ].
        operation value: each ]'.

Collection compile: 'inject: initial into: operation
    | result |
    result := initial.
    self do: [ :each | result := operation value: result value: each ].
    ^ result'.

Collection compile: 'notEmpty
    ^ self size ~= 0'.

Collection compile: 'occurrencesOf: target
    | count |
    count := 0.
    self do: [ :each | each = target ifTrue: [ count := count + 1 ] ].
    ^ count'.

Collection compile: 'rehash
    ^ self'.

Collection compile: 'reject: predicate
    ^ self select: [ :each | (predicate value: each) not ]'.

SequenceableCollection compile: 'copyWithout: target
    ^ self reject: [ :each | each = target ]'.

SequenceableCollection compile: 'after: target
    ^ self at: (self indexOf: target ifAbsent: [ self error: ''Element not found.'' ]) + 1'.

SequenceableCollection compile: 'before: target
    ^ self at: (self indexOf: target ifAbsent: [ self error: ''Element not found.'' ]) - 1'.

SequenceableCollection compile: 'at: index ifAbsent: alternative
    (index < 1 or: [ index > self size ]) ifTrue: [ ^ alternative value ].
    ^ self at: index'.

SequenceableCollection compile: 'first
    ^ self at: 1'.

SequenceableCollection compile: 'last
    ^ self at: self size'.

SequenceableCollection compile: 'findFirst: predicate
    1 to: self size do: [ :index |
        (predicate value: (self at: index)) ifTrue: [ ^ index ] ].
    ^ 0'.

SequenceableCollection compile: 'findLast: predicate
    self size to: 1 by: -1 do: [ :index |
        (predicate value: (self at: index)) ifTrue: [ ^ index ] ].
    ^ 0'.

SequenceableCollection compile: 'indexOf: target
    ^ self indexOf: target ifAbsent: [ 0 ]'.

SequenceableCollection compile: 'indexOf: target ifAbsent: alternative
    | index |
    index := self findFirst: [ :each | each = target ].
    index = 0 ifTrue: [ ^ alternative value ].
    ^ index'.

SequenceableCollection compile: 'indexOfSubCollection: target startingAt: start
    ^ self indexOfSubCollection: target startingAt: start ifAbsent: [ 0 ]'.

SequenceableCollection compile: 'indexOfSubCollection: target startingAt: start ifAbsent: alternative
    | length width last offset |
    length := self size.
    ((start isKindOf: Integer) and: [ start between: 1 and: length ])
        ifFalse: [ self error: ''Search start is outside the collection.'' ].
    width := target size.
    width = 0 ifTrue: [ ^ alternative value ].
    last := length - width + 1.
    start to: last do: [ :index |
        offset := 1.
        [ offset <= width and: [ (self at: index + offset - 1) = (target at: offset) ] ]
            whileTrue: [ offset := offset + 1 ].
        offset > width ifTrue: [ ^ index ] ].
    ^ alternative value'.

SequenceableCollection compile: 'from: start to: stop do: operation
    self from: start to: stop keysAndValuesDo: [ :index :element | operation value: element ]'.

SequenceableCollection compile: 'from: start to: stop keysAndValuesDo: operation
    (start < 1 or: [ stop > self size ]) ifTrue: [ self error: ''Invalid collection range.'' ].
    start to: stop do: [ :index | operation value: index value: (self at: index) ]'.

SequenceableCollection compile: 'keysAndValuesDo: operation
    self from: 1 to: self size keysAndValuesDo: operation'.

SequenceableCollection compile: 'reverseDo: operation
    self size to: 1 by: -1 do: [ :index | operation value: (self at: index) ]'.

SequenceableCollection compile: 'with: other do: operation
    self size = other size ifFalse: [ self error: ''The collections must have equal size.'' ].
    self keysAndValuesDo: [ :index :element | operation value: element value: (other at: index) ]'.

SequenceableCollection compile: '_sequenceFrom: elements
    ^ elements'.

SequenceableCollection compile: 'copyFrom: start to: stop
    ^ self _sequenceFrom: (self asArray copyFrom: start to: stop)'.

SequenceableCollection compile: 'copyWith: element
    ^ self copyReplaceFrom: self size + 1 to: self size with: (Array with: element)'.

Array compile: ', other
    ^ self copyReplaceFrom: self size + 1 to: self size with: other'.

SequenceableCollection compile: 'reverse
    ^ self _sequenceFrom: self asArray reverse'.

SequenceableCollection compile: 'copyReplacing: target withObject: replacement
    ^ self _sequenceFrom: (self asArray collect: [ :each |
        each = target ifTrue: [ replacement ] ifFalse: [ each ] ])'.

SequenceableCollection compile: 'copyReplaceFrom: start to: stop withObject: element
    | count replacements |
    count := (stop - start + 1) max: 1.
    replacements := Array new: count.
    replacements atAllPut: element.
    ^ self copyReplaceFrom: start to: stop with: replacements'.

SequenceableCollection compile: 'copyReplaceFrom: start to: stop with: replacements
    | length result position |
    length := self size.
    (start < 1 or: [ stop < (start - 1) or: [ stop > length ] ])
        ifTrue: [ self error: ''Invalid replacement range.'' ].
    result := Array new: length - (stop - start + 1) + replacements size.
    position := 1.
    self from: 1 to: start - 1 do: [ :each | result at: position put: each. position := position + 1 ].
    replacements do: [ :each | result at: position put: each. position := position + 1 ].
    self from: stop + 1 to: length do: [ :each | result at: position put: each. position := position + 1 ].
    ^ self _sequenceFrom: result'.

SequenceableCollection compile: 'copyReplaceAll: target with: replacements
    | matches width count next last index result position cursor |
    width := target size.
    width = 0 ifTrue: [ ^ self copy ].
    matches := Array new: self size // width.
    count := 0.
    next := 1.
    last := self size - width + 1.
    [ next <= last and: [
        index := self indexOfSubCollection: target startingAt: next.
        index ~= 0 ] ] whileTrue: [
        count := count + 1.
        matches at: count put: index.
        next := index + width ].
    result := Array new: self size + (count * (replacements size - width)).
    position := 1.
    cursor := 1.
    1 to: count do: [ :number |
        index := matches at: number.
        self from: cursor to: index - 1 do: [ :each | result at: position put: each. position := position + 1 ].
        replacements do: [ :each | result at: position put: each. position := position + 1 ].
        cursor := index + width ].
    self from: cursor to: self size do: [ :each | result at: position put: each. position := position + 1 ].
    ^ self _sequenceFrom: result'.

Array compile: 'atAll: indices put: element
    | positions |
    positions := Array withAll: indices.
    positions do: [ :index | self at: index ].
    positions do: [ :index | self at: index put: element ]'.

Array compile: 'atAllPut: element
    1 to: self size do: [ :index | self at: index put: element ]'.

Array compile: 'replaceFrom: start to: stop with: replacement
    replacement size = (stop - start + 1) ifFalse: [ self error: ''The replacement has the wrong size.'' ].
    stop < start ifTrue: [
        ((start isKindOf: Integer) and: [ (stop isKindOf: Integer) and: [
            stop >= 1 and: [ start <= self size ] ] ])
            ifFalse: [ self error: ''Invalid replacement range.'' ].
        ^ self ].
    ^ self replaceFrom: start to: stop with: replacement startingAt: 1'.

Array compile: 'replaceFrom: start to: stop with: replacement startingAt: offset
    | elements |
    (start < 1 or: [ stop > self size or: [ stop < start ] ]) ifTrue: [ self error: ''Invalid replacement range.'' ].
    elements := replacement copyFrom: offset to: offset + stop - start.
    start to: stop do: [ :index | self at: index put: (elements at: index - start + 1) ].
    ^ self'.

Array compile: 'replaceFrom: start to: stop withObject: element
    | size |
    size := self size.
    ((start isKindOf: Integer) and: [ (stop isKindOf: Integer) and: [
        (start between: 1 and: size) and: [ stop between: 1 and: size ] ] ])
        ifFalse: [ self error: ''Invalid replacement range.'' ].
    start to: stop do: [ :index | self at: index put: element ].
    ^ self'.

String compileClass: 'withAll: elements
    ^ self _stringWithAll: elements'.

String compileClass: 'with: first
    ^ self withAll: (Array with: first)'.

String compileClass: 'with: first with: second
    ^ self withAll: (Array with: first with: second)'.

String compileClass: 'with: first with: second with: third
    ^ self withAll: (Array with: first with: second with: third)'.

String compileClass: 'with: first with: second with: third with: fourth
    ^ self withAll: (Array with: first with: second with: third with: fourth)'.

String compile: '_sequenceFrom: elements
    ^ String withAll: elements'.

String compile: 'isEmpty
    ^ self size = 0'.

String compile: 'collect: operation
    ^ self _sequenceFrom: (self asArray collect: operation)'.

String compile: 'select: predicate
    ^ self _sequenceFrom: (self asArray select: predicate)'.

String compile: 'subStrings: separators
    | words characters start |
    (separators allSatisfy: [ :element | element isKindOf: Character ])
        ifFalse: [ self error: ''Substring separators must be characters.'' ].
    characters := self asArray.
    words := Array new: 0.
    start := 1.
    self keysAndValuesDo: [ :index :element |
        (separators includes: element) ifTrue: [
            index > start ifTrue: [
                words := words copyWith: (String withAll: (characters copyFrom: start to: index - 1)) ].
            start := index + 1 ] ].
    start <= characters size ifTrue: [
        words := words copyWith: (String withAll: (characters copyFrom: start to: characters size)) ].
    ^ words'.

String compile: 'atAll: indices put: element
    | copy positions |
    (element isKindOf: Character) ifFalse: [ self error: ''A string element must be a character.'' ].
    self _hasPrimitiveAtPut ifFalse: [
        positions := Array withAll: indices.
        positions do: [ :index | self at: index ].
        positions do: [ :index | self at: index put: element ].
        ^ self ].
    copy := self asArray.
    copy atAll: indices put: element.
    self _replaceCharacters: copy'.

String compile: 'atAllPut: element
    (element isKindOf: Character) ifFalse: [ self error: ''A string element must be a character.'' ].
    self _hasPrimitiveAtPut ifFalse: [
        1 to: self size do: [ :index | self at: index put: element ].
        ^ self ].
    self _replaceCharacters: ((Array new: self size) atAllPut: element; yourself)'.

String compile: 'replaceFrom: start to: stop with: replacement
    | copy |
    copy := self asArray.
    copy replaceFrom: start to: stop with: replacement.
    self _replaceCharacters: copy.
    ^ self'.

String compile: 'replaceFrom: start to: stop with: replacement startingAt: offset
    | copy |
    copy := self asArray.
    copy replaceFrom: start to: stop with: replacement startingAt: offset.
    self _replaceCharacters: copy.
    ^ self'.

String compile: 'replaceFrom: start to: stop withObject: element
    | copy |
    copy := self asArray.
    copy replaceFrom: start to: stop withObject: element.
    self _replaceCharacters: copy.
    ^ self'.

Symbol compile: '_sequenceFrom: elements
    ^ (String withAll: elements) asSymbol'.

Symbol compile: ', other
    ^ self asString , other'.

Symbol compile: 'isEmpty
    ^ self size = 0'.

Symbol compile: 'includes: element
    ^ (self indexOf: element) ~= 0'.

Symbol compile: 'collect: operation
    ^ self _sequenceFrom: (self asArray collect: operation)'.

Symbol compile: 'select: predicate
    ^ self _sequenceFrom: (self asArray select: predicate)'.

Symbol compile: 'subStrings: separators
    ^ self asString subStrings: separators'.

Interval compileClass: 'from: first to: last
    ^ self from: first to: last by: 1'.

Interval compileClass: 'from: first to: last by: increment
    ^ self new initializeFrom: first to: last by: increment'.

Interval compile: 'initializeFrom: first to: last by: increment
    increment = 0 ifTrue: [ self error: ''The interval step must be nonzero.'' ].
    start := first.
    step := increment.
    count := (((last - first) // increment) + 1) max: 0.
    ^ self'.

Interval compile: 'size
    ^ count'.

Interval compile: 'isEmpty
    ^ self size = 0'.

Interval compile: 'at: index
    ((index isKindOf: Integer) and: [ index between: 1 and: count ])
        ifFalse: [ self error: ''Index outside interval.'' ].
    ^ self _elementAt: index'.

Interval compile: '_elementAt: index
    ^ self _coerceElement: (index - 1) * step + start'.

Interval compile: 'do: operation
    1 to: count do: [ :index | operation value: (self _elementAt: index) ]'.

Interval compile: 'includes: element
    ^ self anySatisfy: [ :each | each = element ]'.

Interval compile: 'collect: operation
    ^ self asArray collect: operation'.

Interval compile: 'select: predicate
    ^ self asArray select: predicate'.

Interval compile: 'copyFrom: first to: last
    | result |
    ((first isKindOf: Integer) and: [
        (last isKindOf: Integer) and: [
            (first between: 1 and: count) and: [ last between: 1 and: count ] ] ])
        ifFalse: [ self error: ''Invalid interval range.'' ].
    result := Array new: ((last - first + 1) max: 0).
    first to: last do: [ :index | result at: index - first + 1 put: (self at: index) ].
    ^ self _sequenceFrom: result'.

Interval compile: ', other
    ^ self asArray , other'.
