runnerSetups := 0.
runnerCleanups := 0.
runnerUnreachable := 0.

TestCase subclass: #RunnerCase instanceVariableNames: 'token'.

RunnerCase compile: 'setUp
    self assert: token isNil.
    token := 42.
    runnerSetups := runnerSetups + 1'.

RunnerCase compile: 'tearDown
    runnerCleanups := runnerCleanups + 1'.

RunnerCase compile: 'testAssertion
    self assert: token equals: 99.
    runnerUnreachable := runnerUnreachable + 1'.

RunnerCase compile: 'testDivision
    1 / 0'.

RunnerCase compile: 'testLimit
    [ true ] whileTrue: [ ]'.

RunnerCase compile: 'testPass
    self assert: token equals: 42'.

RunnerCase compile: 'testWithArgument: aValue
    self fail: ''A keyword method ran.'''.

RunnerCase compileClass: 'testClassSide
    self error: ''A class-side method ran.'' line: 1 column: 1'.

RunnerCase subclass: #RunnerCleanupCase instanceVariableNames: ''.

RunnerCleanupCase compile: 'setUp
    super setUp.
    self fail: ''Setup failed.'''.

RunnerCleanupCase compile: 'tearDown
    super tearDown.
    1 / 0'.

RunnerCleanupCase compile: 'testSkippedAfterSetup
    runnerUnreachable := runnerUnreachable + 1'.

RunnerCase subclass: #RunnerLastCase instanceVariableNames: ''.

RunnerLastCase compile: 'testStillRuns
    self assert: token equals: 42'.
