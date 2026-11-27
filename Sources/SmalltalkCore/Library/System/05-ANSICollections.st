"ANSI collection factories and concrete collections (J20 5.7)."

Collection compileClass: 'with: element
    ^ self withAll: (Array with: element)'.

Collection compileClass: 'with: first with: second
    ^ self withAll: (Array with: first with: second)'.

Collection compileClass: 'with: first with: second with: third
    ^ self withAll: (Array with: first with: second with: third)'.

Collection compileClass: 'with: first with: second with: third with: fourth
    ^ self withAll: (Array with: first with: second with: third with: fourth)'.

Collection compileClass: 'withAll: elements
    ^ (self new: elements size) addAll: elements; yourself'.

Collection compile: 'asBag
    ^ Bag withAll: self'.

Collection compile: 'asByteArray
    ^ ByteArray withAll: self'.

Collection compile: 'asOrderedCollection
    ^ OrderedCollection withAll: self'.

Collection compile: 'asSet
    ^ Set withAll: self'.

Collection compile: 'asSortedCollection
    ^ SortedCollection withAll: self'.

Collection compile: 'asSortedCollection: comparator
    ^ (SortedCollection sortBlock: comparator) addAll: self; yourself'.

SequenceableCollection subclass: #OrderedCollection instanceVariableNames: 'storage tally'.

OrderedCollection compileClass: 'new: capacity
    ^ self new _reserve: capacity; yourself'.

OrderedCollection compile: 'initialize
    storage := Array new: 0.
    tally := 0'.

OrderedCollection compile: 'size
    ^ tally'.

OrderedCollection compile: 'isEmpty
    ^ tally = 0'.

OrderedCollection compile: 'includes: element
    ^ (self indexOf: element) ~= 0'.

OrderedCollection compile: '_reserve: capacity
    | replacement |
    ((capacity isKindOf: Integer) and: [ capacity >= 0 ])
        ifFalse: [ self error: ''Capacity must be a nonnegative integer.'' ].
    capacity <= storage size ifTrue: [ ^ self ].
    replacement := Array new: capacity.
    1 to: tally do: [ :index | replacement at: index put: (storage at: index) ].
    storage := replacement'.

OrderedCollection compile: '_makeRoomFor: additional
    | required preferred |
    required := tally + additional.
    required <= storage size ifTrue: [ ^ self ].
    preferred := ((storage size * 2) max: 4) min: 65535.
    self _reserve: (required max: preferred)'.

OrderedCollection compile: '_checkIndex: index
    ((index isKindOf: Integer) and: [ index between: 1 and: tally ])
        ifFalse: [ self error: ''Index outside collection.'' ]'.

OrderedCollection compile: '_checkInsertionIndex: index
    ((index isKindOf: Integer) and: [ index between: 1 and: tally + 1 ])
        ifFalse: [ self error: ''Insertion index outside collection.'' ]'.

OrderedCollection compile: 'at: index
    self _checkIndex: index.
    ^ storage at: index'.

OrderedCollection compile: 'at: index put: element
    self _checkIndex: index.
    ^ storage at: index put: element'.

OrderedCollection compile: 'asArray
    ^ storage copyFrom: 1 to: tally'.

OrderedCollection compile: 'do: operation
    self asArray do: operation'.

OrderedCollection compile: 'collect: operation
    ^ self class withAll: (self asArray collect: operation)'.

OrderedCollection compile: 'select: predicate
    ^ self class withAll: (self asArray select: predicate)'.

OrderedCollection compile: 'copy
    ^ self class withAll: self'.

OrderedCollection compile: '_sequenceFrom: elements
    ^ self class withAll: elements'.

OrderedCollection compile: ', other
    ^ self copy addAll: other; yourself'.

OrderedCollection compile: 'add: element
    ^ self addLast: element'.

OrderedCollection compile: 'addFirst: element
    ^ self add: element beforeIndex: 1'.

OrderedCollection compile: 'addLast: element
    ^ self add: element beforeIndex: tally + 1'.

OrderedCollection compile: 'add: element beforeIndex: index
    self _checkInsertionIndex: index.
    self _makeRoomFor: 1.
    self _spliceAt: index remove: 0 with: (Array with: element).
    ^ element'.

OrderedCollection compile: 'add: element afterIndex: index
    ^ self add: element beforeIndex: index + 1'.

OrderedCollection compile: '_positionOf: target
    ^ self indexOf: target ifAbsent: [ self error: ''Element not found.'' ]'.

OrderedCollection compile: 'add: element after: target
    ^ self add: element afterIndex: (self _positionOf: target)'.

OrderedCollection compile: 'add: element before: target
    ^ self add: element beforeIndex: (self _positionOf: target)'.

OrderedCollection compile: 'addAll: additions
    (self _tryAddAll: additions) ifFalse: [
        additions do: [ :each | self add: each ] ].
    ^ additions'.

OrderedCollection compile: 'addAllFirst: additions
    ^ self addAll: additions beforeIndex: 1'.

OrderedCollection compile: 'addAllLast: additions
    ^ self addAll: additions beforeIndex: tally + 1'.

OrderedCollection compile: 'addAll: additions beforeIndex: index
    | incoming width |
    self _checkInsertionIndex: index.
    incoming := additions asArray.
    width := incoming size.
    width = 0 ifTrue: [ ^ additions ].
    self _makeRoomFor: width.
    self _spliceAt: index remove: 0 with: incoming.
    ^ additions'.

OrderedCollection compile: 'addAll: additions afterIndex: index
    ^ self addAll: additions beforeIndex: index + 1'.

OrderedCollection compile: 'addAll: additions after: target
    ^ self addAll: additions afterIndex: (self _positionOf: target)'.

OrderedCollection compile: 'addAll: additions before: target
    ^ self addAll: additions beforeIndex: (self _positionOf: target)'.

OrderedCollection compile: 'removeAtIndex: index
    | removed |
    self _checkIndex: index.
    removed := storage at: index.
    self _spliceAt: index remove: 1 with: #().
    ^ removed'.

OrderedCollection compile: 'removeFirst
    ^ self removeAtIndex: 1'.

OrderedCollection compile: 'removeLast
    ^ self removeAtIndex: tally'.

OrderedCollection compile: 'remove: element
    ^ self remove: element ifAbsent: [ self error: ''Element not found.'' ]'.

OrderedCollection compile: 'remove: element ifAbsent: alternative
    | index |
    index := self indexOf: element.
    index = 0 ifTrue: [ ^ alternative value ].
    ^ self removeAtIndex: index'.

OrderedCollection compile: 'removeAll: removals
    removals do: [ :each | self remove: each ].
    ^ removals'.

OrderedCollection compile: 'atAll: indices put: element
    | positions |
    positions := Array withAll: indices.
    positions do: [ :index | self _checkIndex: index ].
    positions do: [ :index | self at: index put: element ]'.

OrderedCollection compile: 'atAllPut: element
    1 to: self size do: [ :index | self at: index put: element ]'.

OrderedCollection compile: 'replaceFrom: start to: stop with: replacement
    replacement size = (stop - start + 1) ifFalse: [ self error: ''The replacement has the wrong size.'' ].
    stop < start ifTrue: [
        self _checkIndex: start.
        self _checkIndex: stop.
        ^ self ].
    ^ self replaceFrom: start to: stop with: replacement startingAt: 1'.

OrderedCollection compile: 'replaceFrom: start to: stop with: replacement startingAt: offset
    | copy |
    self _checkIndex: start.
    self _checkIndex: stop.
    copy := storage copy.
    copy replaceFrom: start to: stop with: replacement startingAt: offset.
    storage := copy.
    ^ self'.

OrderedCollection compile: 'replaceFrom: start to: stop withObject: element
    | copy |
    self _checkIndex: start.
    self _checkIndex: stop.
    copy := storage copy.
    copy replaceFrom: start to: stop withObject: element.
    storage := copy.
    ^ self'.

Collection subclass: #UnorderedCollection instanceVariableNames: 'elements'.
UnorderedCollection subclass: #Bag instanceVariableNames: ''.
UnorderedCollection subclass: #Set instanceVariableNames: ''.

UnorderedCollection compileClass: 'new: capacity
    ^ self new _reserve: capacity; yourself'.

UnorderedCollection compile: 'initialize
    elements := OrderedCollection new'.

UnorderedCollection compile: '_reserve: capacity
    elements _reserve: capacity'.

UnorderedCollection compile: 'size
    ^ elements size'.

UnorderedCollection compile: 'isEmpty
    ^ elements isEmpty'.

UnorderedCollection compile: 'includes: element
    ^ elements includes: element'.

UnorderedCollection compile: 'asArray
    ^ elements asArray'.

UnorderedCollection compile: 'do: operation
    elements do: operation'.

UnorderedCollection compile: 'collect: operation
    ^ self class withAll: (elements collect: operation)'.

UnorderedCollection compile: 'select: predicate
    ^ self class withAll: (elements select: predicate)'.

UnorderedCollection compile: 'copy
    ^ self class withAll: self'.

UnorderedCollection compile: 'addAll: additions
    additions do: [ :each | self add: each ].
    ^ additions'.

UnorderedCollection compile: 'remove: element
    ^ elements remove: element'.

UnorderedCollection compile: 'remove: element ifAbsent: alternative
    ^ elements remove: element ifAbsent: alternative'.

UnorderedCollection compile: 'removeAll: removals
    removals do: [ :each | self remove: each ].
    ^ removals'.

Bag compile: 'add: element
    element isNil ifTrue: [ self error: ''A bag element must be non-nil.'' ].
    ^ elements addLast: element'.

Bag compile: 'add: element withOccurrences: count
    ((count isKindOf: Integer) and: [ count >= 0 ])
        ifFalse: [ self error: ''Occurrence count must be a nonnegative integer.'' ].
    count timesRepeat: [ self add: element ].
    ^ element'.

Set compile: 'add: element
    element isNil ifTrue: [ self error: ''A set element must be non-nil.'' ].
    (elements includes: element) ifFalse: [ elements addLast: element ].
    ^ element'.

SequenceableCollection subclass: #ByteArray instanceVariableNames: 'storage'.

ByteArray compileClass: 'new: count
    ^ self new _size: count; yourself'.

ByteArray compileClass: 'withAll: elements
    ^ self new _initializeFrom: elements; yourself'.

ByteArray compile: 'initialize
    storage := Array new: 0'.

ByteArray compile: '_size: count
    storage := Array new: count'.

ByteArray compile: '_initializeFrom: elements
    | bytes |
    bytes := elements asArray.
    bytes do: [ :each | self _checkByte: each ].
    storage := bytes'.

ByteArray compile: '_checkByte: element
    ((element isKindOf: Integer) and: [ element between: 0 and: 255 ])
        ifFalse: [ self error: ''A byte must be an integer from 0 to 255.'' ]'.

ByteArray compile: 'size
    ^ storage size'.

ByteArray compile: 'isEmpty
    ^ storage isEmpty'.

ByteArray compile: 'at: index
    "An unfilled slot represents the default byte zero."
    ^ (storage at: index) ifNil: [ 0 ]'.

ByteArray compile: 'at: index put: element
    self _checkByte: element.
    ^ storage at: index put: element'.

ByteArray compile: 'do: operation
    storage do: [ :each | operation value: (each ifNil: [ 0 ]) ]'.

ByteArray compile: 'asArray
    ^ storage collect: [ :each | each ifNil: [ 0 ] ]'.

ByteArray compile: 'includes: element
    ^ self anySatisfy: [ :each | each = element ]'.

ByteArray compile: 'collect: operation
    ^ self _sequenceFrom: (self asArray collect: operation)'.

ByteArray compile: 'select: predicate
    ^ self _sequenceFrom: (self asArray select: predicate)'.

ByteArray compile: 'copy
    ^ self class withAll: self'.

ByteArray compile: 'copyReplaceAll: target with: replacements
    | bytes |
    bytes := Array withAll: replacements.
    bytes do: [ :each | self _checkByte: each ].
    ^ super copyReplaceAll: target with: bytes'.

ByteArray compile: 'copyReplacing: target withObject: replacement
    self _checkByte: replacement.
    ^ super copyReplacing: target withObject: replacement'.

ByteArray compile: '_sequenceFrom: elements
    ^ self class withAll: elements'.

ByteArray compile: ', other
    ^ self copyReplaceFrom: self size + 1 to: self size with: other'.

ByteArray compile: 'atAll: indices put: element
    | positions |
    self _checkByte: element.
    positions := Array withAll: indices.
    positions do: [ :index | storage at: index ].
    positions do: [ :index | self at: index put: element ]'.

ByteArray compile: 'atAllPut: element
    self _checkByte: element.
    1 to: self size do: [ :index | self at: index put: element ]'.

ByteArray compile: 'replaceFrom: start to: stop with: replacement
    replacement size = (stop - start + 1) ifFalse: [ self error: ''The replacement has the wrong size.'' ].
    stop < start ifTrue: [
        storage replaceFrom: start to: stop with: replacement.
        ^ self ].
    ^ self replaceFrom: start to: stop with: replacement startingAt: 1'.

ByteArray compile: 'replaceFrom: start to: stop with: replacement startingAt: offset
    | bytes copy |
    bytes := replacement copyFrom: offset to: offset + stop - start.
    bytes do: [ :each | self _checkByte: each ].
    copy := storage copy.
    copy replaceFrom: start to: stop with: bytes.
    storage := copy.
    ^ self'.

ByteArray compile: 'replaceFrom: start to: stop withObject: element
    | copy |
    self _checkByte: element.
    copy := storage copy.
    copy replaceFrom: start to: stop withObject: element.
    storage := copy.
    ^ self'.

SequenceableCollection subclass: #SortedCollection instanceVariableNames: 'state'.

SortedCollection compileClass: '_defaultSortBlock
    ^ [ :left :right | left < right ]'.

SortedCollection compileClass: 'new: capacity
    ^ self new _reserve: capacity; yourself'.

SortedCollection compileClass: 'sortBlock: comparator
    ^ self new sortBlock: comparator; yourself'.

SortedCollection compileClass: 'withAll: elements
    self == SortedCollection ifTrue: [ ^ self new _sortElementsFrom: elements ].
    ^ self new addAll: elements; yourself'.

SortedCollection compile: 'initialize
    state := Array with: self class _defaultSortBlock with: OrderedCollection new'.

SortedCollection compile: '_elements
    ^ state at: 2'.

SortedCollection compile: '_reserve: capacity
    self _elements _reserve: capacity'.

SortedCollection compile: 'size
    ^ self _elements size'.

SortedCollection compile: 'isEmpty
    ^ self _elements isEmpty'.

SortedCollection compile: 'at: index
    ^ self _elements at: index'.

SortedCollection compile: 'do: operation
    self _elements do: operation'.

SortedCollection compile: 'asArray
    ^ self _elements asArray'.

SortedCollection compile: 'includes: element
    ^ self _elements includes: element'.

SortedCollection compile: 'sortBlock
    ^ state at: 1'.

SortedCollection compile: 'sortBlock: comparator
    comparator argumentCount = 2 ifFalse: [ self error: ''Expected a two-argument sort block.'' ].
    state := Array with: comparator with: (self _sorted: self asArray by: comparator)'.

SortedCollection compile: '_sorted: source by: comparator
    | current target count width start middle stop left right position item swap |
    count := source size.
    count < 2 ifTrue: [ ^ OrderedCollection withAll: source ].
    current := source.
    target := Array new: count.
    width := 1.
    [ width < count ] whileTrue: [
        start := 1.
        [ start <= count ] whileTrue: [
            middle := (start + width) min: count + 1.
            stop := (start + (width * 2)) min: count + 1.
            left := start.
            right := middle.
            position := start.
            [ position < stop ] whileTrue: [
                (left >= middle or: [
                    right < stop and: [ comparator value: (current at: right) value: (current at: left) ] ])
                    ifTrue: [ item := current at: right. right := right + 1 ]
                    ifFalse: [ item := current at: left. left := left + 1 ].
                target at: position put: item.
                position := position + 1 ].
            start := stop ].
        swap := current.
        current := target.
        target := swap.
        width := width * 2 ].
    ^ OrderedCollection withAll: current'.

SortedCollection compile: '_sortElementsFrom: elements
    state at: 2 put: (self _sorted: (Array withAll: elements) by: self sortBlock).
    ^ self'.

SortedCollection compile: 'add: element
    ^ self _elements add: element beforeIndex: (self _insertionIndexOf: element)'.

SortedCollection compile: '_insertionIndexOf: element
    | lower upper middle |
    lower := 1.
    upper := self size + 1.
    [ lower < upper ] whileTrue: [
        middle := (lower + upper) // 2.
        (self sortBlock value: element value: (self at: middle))
            ifTrue: [ upper := middle ] ifFalse: [ lower := middle + 1 ] ].
    ^ lower'.

SortedCollection compile: 'addAll: additions
    additions do: [ :each | self add: each ].
    ^ additions'.

SortedCollection compile: 'remove: element
    ^ self _elements remove: element'.

SortedCollection compile: 'remove: element ifAbsent: alternative
    ^ self _elements remove: element ifAbsent: alternative'.

SortedCollection compile: 'removeAll: removals
    removals do: [ :each | self remove: each ].
    ^ removals'.

SortedCollection compile: 'removeAtIndex: index
    ^ self _elements removeAtIndex: index'.

SortedCollection compile: 'removeFirst
    ^ self _elements removeFirst'.

SortedCollection compile: 'removeLast
    ^ self _elements removeLast'.

SortedCollection compile: 'collect: operation
    ^ self _elements collect: operation'.

SortedCollection compile: 'select: predicate
    ^ self _sequenceFrom: (self _elements select: predicate)'.

SortedCollection compile: 'reverse
    ^ self _elements reverse'.

SortedCollection compile: 'copy
    ^ self _sequenceFrom: self'.

SortedCollection compile: 'copyReplaceAll: target with: replacements
    | incoming |
    incoming := Array withAll: replacements.
    incoming size > 1 ifTrue: [ self _sorted: incoming copy by: self sortBlock ].
    ^ super copyReplaceAll: target with: incoming'.

SortedCollection compile: 'copyReplacing: target withObject: replacement
    | matched values |
    matched := false.
    values := self asArray collect: [ :each |
        each = target ifTrue: [ matched := true. replacement ] ifFalse: [ each ] ].
    matched ifFalse: [ self _insertionIndexOf: replacement ].
    ^ self _sequenceFrom: values'.

SortedCollection compile: 'asSortedCollection
    ^ self copy'.

SortedCollection compile: '_sequenceFrom: collection
    | result |
    result := self class sortBlock: self sortBlock.
    result class == SortedCollection ifTrue: [ ^ result _sortElementsFrom: collection ].
    ^ result addAll: collection; yourself'.

SortedCollection compile: ', other
    ^ self copy addAll: other; yourself'.
