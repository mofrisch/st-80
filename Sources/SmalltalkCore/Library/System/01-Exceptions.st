"Exception policy and descriptions. The VM maintains the dynamic handler environment."

Object compile: 'error: aString
    ^ Error signal: aString'.

Exception compileClass: 'signal
    ^ self new signal'.

Exception compileClass: 'signal: aString
    ^ self new signal: aString'.

Exception compileClass: 'handles: anException
    | type |
    type := anException class.
    [ type notNil ] whileTrue: [
        type == self ifTrue: [ ^ true ].
        type := type superclass ].
    ^ false'.

Exception compile: 'signal
    ^ self _signalException'.

Exception compile: 'signal: aString
    ^ (self messageText: aString) signal'.

Exception compile: 'messageText
    ^ messageText'.

Exception compile: 'messageText: aString
    messageText := aString.
    ^ self'.

Exception compile: 'tag
    tagAssigned == true ifTrue: [ ^ tagValue ].
    ^ self messageText'.

Exception compile: 'tag: aValue
    tagValue := aValue.
    tagAssigned := true.
    ^ self'.

Exception compile: 'description
    ^ self messageText ifNil: [ self class name asString ]'.

Exception compile: 'isResumable
    ^ false'.

Exception compile: 'defaultAction
    ^ self _failUnhandledException'.

Exception compileClass: ', another
    ^ ExceptionSet new selectors: (Array with: self with: another); yourself'.

ExceptionSet compile: 'selectors: values
    selectors := values'.

ExceptionSet compile: 'handles: exception
    ^ selectors anySatisfy: [ :each | each handles: exception ]'.

ExceptionSet compile: ', another
    ^ self class new selectors: (selectors copyWith: another); yourself'.

MessageNotUnderstood compile: 'receiver: anObject message: failed
    receiver := anObject.
    message := failed'.

MessageNotUnderstood compile: 'receiver
    ^ receiver'.

MessageNotUnderstood compile: 'message
    ^ message'.

MessageNotUnderstood compile: 'description
    ^ receiver class name asString , '' does not understand '' , message selector asString'.

MessageNotUnderstood compile: 'isResumable
    ^ true'.

ZeroDivide compile: 'dividend: aNumber
    dividend := aNumber'.

ZeroDivide compile: 'dividend
    ^ dividend'.

ZeroDivide compile: 'description
    ^ ''Division by zero.'''.

ZeroDivide compile: 'isResumable
    ^ true'.

ZeroDivide compileClass: 'dividend: aNumber
    ^ (self new dividend: aNumber; yourself) signal'.
