"Test discovery, fixtures, assertions, and results are ordinary Smalltalk."

Object subclass: #TestCase instanceVariableNames: ''.

TestCase compileClass: 'run
    ^ TestRunner runClass: self'.

TestCase compileClass: 'run: selector
    ^ TestRunner runClass: self selector: selector'.

TestCase compile: 'setUp
    ^ self'.

TestCase compile: 'tearDown
    ^ self'.

TestCase compile: 'assert: condition
    condition ifFalse: [ self fail: ''Expected true.'' ]'.

TestCase compile: 'deny: condition
    condition ifTrue: [ self fail: ''Expected false.'' ]'.

TestCase compile: 'assert: actual equals: expected
    (actual = expected) ifFalse: [
        self fail: ''Expected '' , expected printString , '', got '' , actual printString , ''.'' ]'.

TestCase compile: 'fail: aString
    ToolVM failTest: aString'.

Object subclass: #TestOutcome instanceVariableNames: 'testClass selector diagnostics'.

TestOutcome compile: 'initialize
    diagnostics := #()'.

TestOutcome compile: 'testClass: aClass selector: aSelector
    testClass := aClass.
    selector := aSelector'.

TestOutcome compile: 'testClass
    ^ testClass'.

TestOutcome compile: 'selector
    ^ selector'.

TestOutcome compile: 'diagnostics
    ^ diagnostics'.

TestOutcome compile: 'record: diagnostic during: phase
    | entry |
    diagnostic isNil ifTrue: [ ^ self ].
    entry := Array new: 5.
    entry at: 1 put: phase;
        at: 2 put: (diagnostic at: 1);
        at: 3 put: (diagnostic at: 2);
        at: 4 put: (diagnostic at: 3);
        at: 5 put: (diagnostic at: 4).
    diagnostics := diagnostics copyWith: entry'.

TestOutcome compile: 'status
    diagnostics do: [ :each | (each at: 2) = #error ifTrue: [ ^ #error ] ].
    ^ diagnostics isEmpty ifTrue: [ #passed ] ifFalse: [ #failure ]'.

Object subclass: #TestResult instanceVariableNames: 'outcomes failures errors'.

TestResult compile: 'initialize
    self outcomes: #()'.

TestResult compile: 'outcomes: results
    outcomes := results.
    failures := 0.
    errors := 0.
    outcomes do: [ :each |
        | status |
        status := each status.
        status = #failure ifTrue: [ failures := failures + 1 ].
        status = #error ifTrue: [ errors := errors + 1 ] ]'.

TestResult compile: 'outcomes
    ^ outcomes'.

TestResult compile: 'testCount
    ^ outcomes size'.

TestResult compile: 'passedCount
    ^ self testCount - failures - errors'.

TestResult compile: 'failureCount
    ^ failures'.

TestResult compile: 'errorCount
    ^ errors'.

TestResult compile: 'isSuccess
    ^ self testCount > 0 and: [ failures + errors = 0 ]'.

TestResult compile: 'summary
    ^ self testCount printString , '' total, '' , self passedCount printString , '' passed, '' ,
        failures printString , '' failed, '' , errors printString , '' with errors'''.

Object subclass: #TestRunner instanceVariableNames: ''.

TestRunner compileClass: 'isTestClass: aClass
    | parent |
    parent := aClass superclass.
    [ parent notNil ] whileTrue: [
        parent == TestCase ifTrue: [ ^ true ].
        parent := parent superclass ].
    ^ false'.

TestRunner compileClass: 'testSelectorsFor: aClass
    ^ aClass methodNames select: [ :name |
        (name size > 4 and: [ (name includes: '':'') not ]) and: [
            ((name at: 1) , (name at: 2) , (name at: 3) , (name at: 4)) = ''test'' ] ]'.

TestRunner compileClass: 'runAll
    | classes selectors count outcomes index |
    classes := (ToolVM classNames collect: [ :name | ToolVM classNamed: name ])
        select: [ :each | self isTestClass: each ].
    selectors := classes collect: [ :each | self testSelectorsFor: each ].
    count := 0.
    selectors do: [ :each | count := count + each size ].
    outcomes := Array new: count.
    index := 0.
    1 to: classes size do: [ :suite |
        (selectors at: suite) do: [ :selector |
            index := index + 1.
            outcomes at: index put: (self runTest: selector in: (classes at: suite)) ] ].
    ^ TestResult new outcomes: outcomes; yourself'.

TestRunner compileClass: 'runClass: aClass
    | outcomes |
    aClass == TestCase ifTrue: [ ^ TestResult new ].
    (self isTestClass: aClass) ifFalse: [ self error: ''Expected a TestCase subclass.'' line: 1 column: 1 ].
    outcomes := (self testSelectorsFor: aClass) collect: [ :selector | self runTest: selector in: aClass ].
    ^ TestResult new outcomes: outcomes; yourself'.

TestRunner compileClass: 'runClass: aClass selector: selector
    | name outcomes |
    name := selector asString.
    ((self isTestClass: aClass) and: [ (self testSelectorsFor: aClass) includes: name ])
        ifFalse: [ self error: ''No test named '' , name , '' in '' , aClass name asString , ''.'' line: 1 column: 1 ].
    outcomes := Array new: 1.
    outcomes at: 1 put: (self runTest: name in: aClass).
    ^ TestResult new outcomes: outcomes; yourself'.

TestRunner compileClass: 'runTest: name in: aClass
    | instance outcome setup |
    outcome := TestOutcome new testClass: aClass selector: name asSymbol; yourself.
    setup := ToolVM captureTestPhase: [ instance := aClass new. instance setUp ].
    outcome record: setup during: #setUp.
    setup isNil ifTrue: [
        outcome record: (ToolVM captureTestPhase: [ instance perform: name asSymbol ]) during: #test ].
    instance notNil ifTrue: [
        outcome record: (ToolVM captureTestPhase: [ instance tearDown ]) during: #tearDown ].
    ^ outcome'.
