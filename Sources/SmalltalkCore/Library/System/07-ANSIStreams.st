"ANSI collection streams (J20 5.9). Writers keep private contents and never write back."

Object subclass: #CollectionStream instanceVariableNames: 'backing buffer cursor byteCount'.
CollectionStream subclass: #ReadStream instanceVariableNames: ''.
CollectionStream subclass: #WriteStream instanceVariableNames: ''.
ReadStream subclass: #ReadWriteStream instanceVariableNames: ''.

ReadStream compileClass: 'on: collection
    ^ self new _openOn: collection writing: false'.

WriteStream compileClass: 'with: collection
    ^ self new _openOn: collection writing: true'.

ReadWriteStream compileClass: 'with: collection
    ^ self new _openOn: collection writing: true'.

ReadWriteStream compileClass: 'on: collection
    ^ (self with: collection) reset; yourself'.

CollectionStream compile: '_openOn: collection writing: writable
    ((collection respondsTo: #at:) and: [
        (collection respondsTo: #size) and: [ collection respondsTo: #copyFrom:to: ] ])
        ifFalse: [ self error: ''Expected an indexed collection.'' ].
    writable ifTrue: [
        (collection respondsTo: #at:put:) ifFalse: [ self error: ''Expected a collection with at:put:.'' ].
        buffer := OrderedCollection withAll: collection.
        collection class == String ifTrue: [ byteCount := collection utf8Size ] ].
    backing := collection.
    cursor := writable ifTrue: [ buffer size ] ifFalse: [ 0 ].
    ^ self'.

CollectionStream compile: '_sequence
    backing isNil ifTrue: [ self error: ''The stream is closed.'' ].
    ^ buffer ifNil: [ backing ]'.

CollectionStream compile: '_size
    ^ self _sequence size'.

CollectionStream compile: '_sliceFrom: start to: stop
    | slice |
    slice := self _sequence copyFrom: start to: stop.
    buffer isNil ifTrue: [ ^ slice ].
    ^ backing copyReplaceFrom: 1 to: backing size with: slice'.

CollectionStream compile: 'contents
    ^ self _sliceFrom: 1 to: self _size'.

CollectionStream compile: 'isEmpty
    ^ self _size = 0'.

CollectionStream compile: 'position
    self _sequence.
    ^ cursor'.

CollectionStream compile: 'position: newPosition
    | size |
    size := self _size.
    ((newPosition isKindOf: Integer) and: [
        newPosition >= 0 and: [ newPosition < size or: [ size = 0 and: [ newPosition = 0 ] ] ] ])
        ifFalse: [ self error: ''Position outside the stream.'' ].
    cursor := newPosition'.

CollectionStream compile: 'reset
    self _sequence.
    cursor := 0'.

CollectionStream compile: 'setToEnd
    cursor := self _size'.

CollectionStream compile: 'close
    backing := nil.
    buffer := nil.
    byteCount := nil.
    cursor := 0'.

ReadStream compile: 'atEnd
    ^ cursor >= self _size'.

ReadStream compile: 'peek
    self atEnd ifTrue: [ ^ nil ].
    ^ self _sequence at: cursor + 1'.

ReadStream compile: 'peekFor: element
    self atEnd ifTrue: [ ^ false ].
    ^ self peek = element'.

ReadStream compile: 'next
    | element |
    self atEnd ifTrue: [ ^ nil ].
    element := self _sequence at: cursor + 1.
    cursor := cursor + 1.
    ^ element'.

ReadStream compile: 'nextMatchFor: element
    self atEnd ifTrue: [ ^ false ].
    ^ self next = element'.

ReadStream compile: '_endAfter: count
    ((count isKindOf: Integer) and: [ count >= 0 ])
        ifFalse: [ self error: ''The count must be a nonnegative integer.'' ].
    ^ (cursor + count) min: self _size'.

ReadStream compile: 'next: count
    | stop result |
    stop := self _endAfter: count.
    result := self _sliceFrom: cursor + 1 to: stop.
    cursor := stop.
    ^ result'.

ReadStream compile: 'skip: count
    cursor := self _endAfter: count'.

ReadStream compile: 'do: operation
    [ self atEnd ] whileFalse: [ operation value: self next ]'.

ReadStream compile: '_findNext: predicate
    | sequence |
    sequence := self _sequence.
    cursor + 1 to: sequence size do: [ :index |
        (predicate value: (sequence at: index)) ifTrue: [ ^ index ] ].
    ^ nil'.

ReadStream compile: 'skipTo: element
    | match |
    match := self _findNext: [ :each | each = element ].
    cursor := match ifNil: [ self _size ].
    ^ match notNil'.

ReadStream compile: 'upTo: element
    | match result |
    match := self _findNext: [ :each | each = element ].
    result := self _sliceFrom: cursor + 1 to: (match isNil ifTrue: [ self _size ] ifFalse: [ match - 1 ]).
    cursor := match ifNil: [ self _size ].
    ^ result'.

ReadStream compile: 'nextLine
    | sequence terminator stop result |
    sequence := self _sequence.
    terminator := self _findNext: [ :each | each = Character lf or: [ each = Character cr ] ].
    stop := terminator isNil ifTrue: [ sequence size ] ifFalse: [ terminator - 1 ].
    result := String withAll: (sequence copyFrom: cursor + 1 to: stop).
    cursor := terminator ifNil: [ sequence size ].
    terminator notNil ifTrue: [
        ((sequence at: terminator) = Character cr and: [
            cursor < sequence size and: [ (sequence at: cursor + 1) = Character lf ] ])
                ifTrue: [ cursor := cursor + 1 ] ].
    ^ result'.

CollectionStream compile: '_checkWrite: elements
    | species |
    species := backing class.
    (species == Array or: [ species == OrderedCollection ]) ifTrue: [ ^ self ].
    species == String ifTrue: [
        (elements allSatisfy: [ :each | each isKindOf: Character ])
            ifFalse: [ self error: ''A text stream expects characters.'' ].
        ^ self ].
    species == ByteArray ifTrue: [
        (elements allSatisfy: [ :each | (each isKindOf: Integer) and: [ each between: 0 and: 255 ] ])
            ifFalse: [ self error: ''A byte stream expects integers from 0 to 255.'' ].
        ^ self ].
    backing copyReplaceFrom: 1 to: backing size with: elements'.

CollectionStream compile: '_write: elements
    self _sequence.
    buffer isNil ifTrue: [ self error: ''The stream is read-only.'' ].
    elements isEmpty ifTrue: [ ^ self ].
    self _checkWrite: elements.
    buffer _makeRoomFor: ((cursor + elements size - buffer size) max: 0).
    self _commitWrite: elements'.

WriteStream compile: 'nextPut: element
    self _write: (Array with: element).
    ^ element'.

WriteStream compile: 'nextPutAll: elements
    | batch |
    batch := self _nextPutAllBatch: elements.
    batch isNil
        ifTrue: [ elements do: [ :each | self nextPut: each ] ]
        ifFalse: [ self _write: batch ]'.

WriteStream compile: 'cr
    self nextPut: Character lf'.

WriteStream compile: 'space
    self nextPut: Character space'.

WriteStream compile: 'tab
    self nextPut: Character tab'.

WriteStream compile: 'flush
    self _sequence'.

ReadWriteStream compile: 'nextPut: element
    self _write: (Array with: element).
    ^ element'.

ReadWriteStream compile: 'nextPutAll: elements
    | batch |
    batch := self _nextPutAllBatch: elements.
    batch isNil
        ifTrue: [ elements do: [ :each | self nextPut: each ] ]
        ifFalse: [ self _write: batch ]'.

ReadWriteStream compile: 'cr
    self nextPut: Character lf'.

ReadWriteStream compile: 'space
    self nextPut: Character space'.

ReadWriteStream compile: 'tab
    self nextPut: Character tab'.

ReadWriteStream compile: 'flush
    self _sequence'.
