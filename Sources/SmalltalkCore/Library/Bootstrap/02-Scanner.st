"Unicode scanner that tracks source positions and returns one token per call."

Object subclass: #STScanner instanceVariableNames: 'characters offset line column nesting tokenLine tokenColumn'.

STScanner compile: 'initialize
    offset := 1.
    line := 1.
    column := 1.
    nesting := 0'.

STScanner compile: 'source: aString
    characters := aString characters'.

STScanner compile: 'peek
    ^ self peekAhead: 0'.

STScanner compile: 'peekAhead: delta
    | index |
    index := offset + delta.
    index > characters size ifTrue: [ ^ nil ].
    ^ characters at: index'.

STScanner compile: 'advance
    (self peek isLineBreak) ifTrue: [
        line := line + 1. column := 1
    ] ifFalse: [ column := column + 1 ].
    offset := offset + 1'.

STScanner compile: 'token: kind value: payload
    | token |
    (#(leftParen leftBracket arrayStart) includes: kind) ifTrue: [
        nesting := nesting + 1.
        nesting > 32 ifTrue: [ self fail: ''Source code exceeds the nesting limit of 32 levels.'' ] ].
    (#(rightParen rightBracket) includes: kind) ifTrue: [ nesting := nesting - 1 ].
    token := Array new: 4.
    token at: 1 put: kind; at: 2 put: tokenLine; at: 3 put: tokenColumn; at: 4 put: payload.
    ^ token'.

STScanner compile: 'fail: message
    self error: message line: tokenLine column: tokenColumn'.

STScanner compile: 'isIdentifierStart: character
    ^ character notNil and: [ character isLetter or: [ character = ''_'' ] ]'.

STScanner compile: 'isIdentifierPart: character
    ^ (self isIdentifierStart: character) or: [ character notNil and: [ character isNumber ] ]'.

STScanner compile: 'isBinary: character
    ^ character notNil and: [ ''+-*/\~<>=@%,&?!'' includes: character ]'.

STScanner compile: 'skipTrivia
    | character |
    [ character := self peek.
      character notNil and: [ character isWhitespace or: [ character = ''"'' ] ] ] whileTrue: [
        character = ''"'' ifTrue: [
            tokenLine := line. tokenColumn := column.
            self readComment
        ] ifFalse: [ self advance ] ]'.

STScanner compile: 'readComment
    self advance.
    [ self peek notNil and: [ self peek ~= ''"'' ] ] whileTrue: [ self advance ].
    self peek isNil ifTrue: [ ^ self fail: ''Unterminated comment.'' ].
    self advance'.

STScanner compile: 'readIdentifier
    | start |
    start := offset.
    [ self isIdentifierPart: self peek ] whileTrue: [ self advance ].
    ^ characters joinedStringFrom: start to: offset - 1'.

STScanner compile: 'readString
    | pieces start |
    start := offset.
    pieces := nil.
    [ self peek notNil ] whileTrue: [
        self peek = '''''''' ifTrue: [
            self advance.
            self peek = '''''''' ifFalse: [
                pieces isNil ifTrue: [ ^ characters joinedStringFrom: start to: offset - 2 ].
                pieces add: (characters joinedStringFrom: start to: offset - 2).
                ^ pieces joinedString ].
            pieces isNil ifTrue: [ pieces := STCompilerList new ].
            pieces add: (characters joinedStringFrom: start to: offset - 1).
            self advance.
            start := offset
        ] ifFalse: [ self advance ] ].
    ^ self fail: ''Unterminated string.'''.

STScanner compile: 'readNumber
    | start digits number |
    start := offset.
    [ self peek notNil and: [ self peek isASCIIDigit ] ] whileTrue: [ self advance ].
    digits := characters joinedStringFrom: start to: offset - 1.
    digits = ''9223372036854775808'' ifTrue: [ ^ self token: #minimumMagnitude value: nil ].
    number := digits asIntegerOrNil.
    number isNil ifTrue: [ self fail: ''Integer exceeds the 64-bit range.'' ].
    ^ self token: #integer value: number'.

STScanner compile: 'readWord
    | name |
    name := self readIdentifier.
    (self peek = '':'' and: [ (self peekAhead: 1) ~= ''='' ]) ifTrue: [
        self advance.
        ^ self token: #keyword value: (name , '':'') ].
    ^ self token: #identifier value: name'.

STScanner compile: 'readSymbol
    | start more |
    self peek = ''('' ifTrue: [ self advance. ^ self token: #arrayStart value: nil ].
    self peek = '''''''' ifTrue: [ self advance. ^ self token: #symbol value: self readString ].
    start := offset.
    (self isIdentifierStart: self peek) ifTrue: [
        [ self isIdentifierPart: self peek ] whileTrue: [ self advance ].
        more := true.
        [ more and: [ self peek = '':'' ] ] whileTrue: [
            self advance.
            more := self isIdentifierStart: self peek.
            more ifTrue: [
                [ self isIdentifierPart: self peek ] whileTrue: [ self advance ] ] ].
        ^ self token: #symbol value: (characters joinedStringFrom: start to: offset - 1) ].
    (self isBinary: self peek) ifTrue: [
        [ self isBinary: self peek ] whileTrue: [ self advance ].
        ^ self token: #symbol value: (characters joinedStringFrom: start to: offset - 1) ].
    ^ self fail: ''Expected a symbol or ( after #.'''.

STScanner compile: 'nextToken
    self skipTrivia.
    ^ self readToken'.

STScanner compile: 'readToken
    | character start |
    tokenLine := line. tokenColumn := column.
    character := self peek.
    character isNil ifTrue: [ ^ self token: #end value: nil ].
    character isASCIIDigit ifTrue: [ ^ self readNumber ].
    (self isIdentifierStart: character) ifTrue: [ ^ self readWord ].
    start := offset.
    self advance.
    character = '''''''' ifTrue: [ ^ self token: #string value: self readString ].
    character = ''#'' ifTrue: [ ^ self readSymbol ].
    character = '':'' ifTrue: [
        self peek = ''='' ifTrue: [ self advance. ^ self token: #assign value: nil ].
        ^ self token: #colon value: nil ].
    character = ''.'' ifTrue: [ ^ self token: #period value: nil ].
    character = '';'' ifTrue: [ ^ self token: #semicolon value: nil ].
    character = ''^'' ifTrue: [ ^ self token: #caret value: nil ].
    character = ''|'' ifTrue: [ ^ self token: #bar value: nil ].
    character = ''('' ifTrue: [ ^ self token: #leftParen value: nil ].
    character = '')'' ifTrue: [ ^ self token: #rightParen value: nil ].
    character = ''['' ifTrue: [ ^ self token: #leftBracket value: nil ].
    character = '']'' ifTrue: [ ^ self token: #rightBracket value: nil ].
    (self isBinary: character) ifTrue: [
        [ self isBinary: self peek ] whileTrue: [ self advance ].
        ^ self token: #binary value: (characters joinedStringFrom: start to: offset - 1) ].
    ^ self fail: ''Unknown character: '' , character'.

"Editor tokenization shares the compiler's lexical rules and tolerates partial input."
