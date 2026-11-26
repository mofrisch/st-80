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
