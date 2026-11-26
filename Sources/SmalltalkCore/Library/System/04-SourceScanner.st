"Token classification for syntax highlighting."

STScanner subclass: #STSourceScanner instanceVariableNames: 'tokenStart'.

STSourceScanner compile: 'nextHighlight
    | span |
    [ self peek notNil ] whileTrue: [
        tokenStart := offset.
        self peek isWhitespace
            ifTrue: [ self advance ]
            ifFalse: [
                span := self peek = ''"''
                    ifTrue: [ self readComment. self highlight: #comment ]
                    ifFalse: [ self readToken ].
                span notNil ifTrue: [ ^ span ] ] ].
    ^ nil'.

STSourceScanner compile: 'token: kind value: value
    (#(string symbol arrayStart character) includes: kind) ifTrue: [ ^ self highlight: #literal ].
    (#(assign caret integer minimumMagnitude float unsupportedNumber) includes: kind) ifTrue: [ ^ self highlight: #language ].
    (kind = #identifier and: [ #(''self'' ''super'' ''nil'' ''true'' ''false'' ''thisContext'') includes: value ])
        ifTrue: [ ^ self highlight: #language ].
    ^ nil'.

STSourceScanner compile: 'highlight: kind
    | span |
    span := Array new: 3.
    span at: 1 put: kind; at: 2 put: tokenStart; at: 3 put: offset.
    ^ span'.

STSourceScanner compile: 'fail: message
    ^ nil'.
