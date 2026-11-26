"A small suite available in every fresh image."

TestCase subclass: #CounterTest instanceVariableNames: 'counter'.

CounterTest compile: 'setUp
    counter := Counter new'.

CounterTest compile: 'testIncrement
    counter increment.
    self assert: counter value equals: 1'.

CounterTest compile: 'testCountersStartIndependently
    counter add: 42.
    self assert: Counter new value equals: 0.
    self assert: counter value equals: 42'.

TestCase subclass: #CollectionsTest instanceVariableNames: ''.

CollectionsTest compile: 'testArrayCollectAndSelect
    | values |
    values := #(1 2 3 4) collect: [ :each | each * 2 ].
    self assert: (values select: [ :each | each > 4 ]) equals: #(6 8)'.

CollectionsTest compile: 'testFalseAndDoesNotEvaluateItsBlock
    | ran |
    ran := false.
    self deny: (false and: [ ran := true ]).
    self deny: ran'.

Model subclass: #BindingTestModel instanceVariableNames: 'caption'.

BindingTestModel compile: 'caption
    ^ caption'.

BindingTestModel compile: 'caption: aString
    caption := aString.
    self changed: #caption'.

TestCase subclass: #UIBindingTest instanceVariableNames: 'model label'.

UIBindingTest compile: 'setUp
    model := BindingTestModel new.
    model caption: ''Initial''.
    label := UILabel new.
    label bind: #text to: model aspect: #caption'.

UIBindingTest compile: 'tearDown
    label unbindAll'.

UIBindingTest compile: 'testBindingReadsAndUpdatesTheLabel
    self assert: label text equals: ''Initial''.
    model caption: ''Changed''.
    self assert: label text equals: ''Changed'''.

UIBindingTest compile: 'testUnbindingStopsUpdates
    label unbind: #text.
    model caption: ''Changed''.
    self assert: label text equals: ''Initial''.
    self assert: model dependents isEmpty'.
