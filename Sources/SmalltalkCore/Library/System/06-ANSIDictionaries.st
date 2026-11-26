"ANSI keyed collections (J20 5.7.2–5.7.4 and 5.7.21–5.7.22)."

Collection subclass: #Dictionary instanceVariableNames: 'entries'.
Dictionary subclass: #IdentityDictionary instanceVariableNames: ''.

Dictionary compileClass: 'new: capacity
    ^ self new _reserve: capacity; yourself'.

Dictionary compileClass: 'withAll: source
    ^ (self new: source size) addAll: source; yourself'.

Dictionary compile: 'initialize
    entries := OrderedCollection new'.

Dictionary compile: '_reserve: capacity
    ((capacity isKindOf: Integer) and: [ capacity >= 0 ])
        ifFalse: [ self error: ''Capacity must be a nonnegative integer.'' ].
    entries _reserve: (capacity min: 65535)'.

Dictionary compile: 'size
    ^ entries size'.

Dictionary compile: 'isEmpty
    ^ entries isEmpty'.

Dictionary compile: '_key: stored matches: requested
    ^ stored = requested'.

IdentityDictionary compile: '_key: stored matches: requested
    ^ stored == requested'.

Dictionary compile: '_indexOfKey: key
    key isNil ifTrue: [ self error: ''A dictionary key must be non-nil.'' ].
    ^ entries findFirst: [ :entry | self _key: entry first matches: key ]'.

Dictionary compile: 'includesKey: key
    ^ (self _indexOfKey: key) ~= 0'.

Dictionary compile: 'at: key
    ^ self at: key ifAbsent: [ self error: ''Key not found.'' ]'.

Dictionary compile: 'at: key ifAbsent: alternative
    | index |
    index := self _indexOfKey: key.
    index = 0 ifTrue: [ ^ alternative value ].
    ^ (entries at: index) last'.

Dictionary compile: 'at: key ifAbsentPut: alternative
    ^ self at: key ifAbsent: [ self at: key put: alternative value ]'.

Dictionary compile: 'at: key put: value
    | index |
    index := self _indexOfKey: key.
    index = 0
        ifTrue: [ entries addLast: (Array with: key with: value) ]
        ifFalse: [ entries at: index put: (Array with: (entries at: index) first with: value) ].
    ^ value'.

Dictionary compile: 'addAll: source
    source keysAndValuesDo: [ :key :value | self at: key put: value ].
    ^ source'.

Dictionary compile: 'includes: value
    ^ self anySatisfy: [ :element | element = value ]'.

Dictionary compile: 'keyAtValue: value
    ^ self keyAtValue: value ifAbsent: [ self error: ''Value not found.'' ]'.

Dictionary compile: 'keyAtValue: value ifAbsent: alternative
    self keysAndValuesDo: [ :key :element | element = value ifTrue: [ ^ key ] ].
    ^ alternative value'.

Dictionary compile: 'keys
    ^ entries asArray collect: [ :entry | entry first ]'.

Dictionary compile: 'values
    ^ entries asArray collect: [ :entry | entry last ]'.

Dictionary compile: 'do: operation
    entries do: [ :entry | operation value: entry last ]'.

Dictionary compile: 'keysDo: operation
    entries do: [ :entry | operation value: entry first ]'.

Dictionary compile: 'keysAndValuesDo: operation
    entries do: [ :entry | operation value: entry first value: entry last ]'.

Dictionary compile: 'removeKey: key
    ^ self removeKey: key ifAbsent: [ self error: ''Key not found.'' ]'.

Dictionary compile: 'removeKey: key ifAbsent: alternative
    | index |
    index := self _indexOfKey: key.
    index = 0 ifTrue: [ ^ alternative value ].
    ^ (entries removeAtIndex: index) last'.

Dictionary compile: 'removeAllKeys: keys
    ^ self removeAllKeys: keys ifAbsent: [ :key | self error: ''Key not found.'' ]'.

Dictionary compile: 'removeAllKeys: keys ifAbsent: alternative
    keys do: [ :key | self removeKey: key ifAbsent: [ alternative value: key ] ].
    ^ keys'.

Dictionary compile: 'collect: transformer
    | result |
    result := self class new: self size.
    self keysAndValuesDo: [ :key :value | result at: key put: (transformer value: value) ].
    ^ result'.

Dictionary compile: 'select: predicate
    | result |
    result := self class new.
    self keysAndValuesDo: [ :key :value |
        (predicate value: value) ifTrue: [ result at: key put: value ] ].
    ^ result'.

Dictionary compile: 'copy
    ^ self class withAll: self'.
