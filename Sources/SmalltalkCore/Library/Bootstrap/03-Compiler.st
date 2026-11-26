"Compiles methods and workspace expressions into syntax trees for the VM."

Object subclass: #STCompiler instanceVariableNames: 'scanner current lookahead expressionDepth'.

STCompiler compile: 'initialize
    ^ self'.

STCompiler compile: 'start: input
    expressionDepth := 0.
    scanner := STScanner new.
    scanner source: input.
    current := scanner nextToken.
    lookahead := scanner nextToken'.

STCompiler compile: 'workspace: input
    self start: input.
    ^ self workspaceBody'.

STCompiler compile: 'method: input
    | selector parameters body kind |
    self start: input.
    parameters := STCompilerList new.
    kind := self kind.
    kind = #identifier ifTrue: [ selector := self identifier ].
    (#(binary bar) includes: kind) ifTrue: [
        selector := self tokenValue.
        self advance.
        parameters add: self identifier ].
    kind = #keyword ifTrue: [
        selector := ''''.
        [ self kind = #keyword ] whileTrue: [
            selector := selector , self tokenValue.
            self advance.
            parameters add: self identifier ] ].
    selector isNil ifTrue: [ self fail: ''Expected a method header such as increment or add: amount.'' ].
    parameters := parameters elements.
    self validateNames: parameters.
    body := self workspaceBody.
    self validate: parameters separateFrom: (body at: 1) error: ''An argument and a local variable have the same name.''.
    ^ self triple: selector with: parameters with: body'.

STCompiler compile: 'workspaceBody
    | body |
    body := self bodyUntil: #end.
    self expect: #end.
    ^ body'.

STCompiler compile: 'kind
    ^ current at: 1'.

STCompiler compile: 'tokenValue
    ^ current at: 4'.

STCompiler compile: 'advance
    current := lookahead.
    lookahead := scanner nextToken'.

STCompiler compile: 'fail: message
    self error: message line: (current at: 2) column: (current at: 3)'.

STCompiler compile: 'expect: kind
    self kind = kind ifFalse: [ self fail: (self tokenLabel: kind) , '' expected, found: '' , (self tokenLabel: self kind) , ''.'' ].
    self advance'.

STCompiler compile: 'tokenLabel: kind
    kind = #end ifTrue: [ ^ ''end of source'' ].
    kind = #rightBracket ifTrue: [ ^ '']'' ].
    kind = #rightParen ifTrue: [ ^ '')'' ].
    kind = #bar ifTrue: [ ^ ''|'' ].
    kind = #period ifTrue: [ ^ ''.'' ].
    ^ kind asString'.

STCompiler compile: 'identifier
    | name |
    self kind = #identifier ifFalse: [ self fail: ''Expected a variable name.'' ].
    name := self tokenValue.
    self advance.
    ^ name'.

STCompiler compile: 'validateNames: names
    names do: [ :name |
        (#(''self'' ''super'' ''true'' ''false'' ''nil'' ''thisContext'') includes: name) ifTrue: [
            self fail: ''A pseudo-variable cannot be declared.'' ] ].
    1 to: names size do: [ :index |
        1 to: index - 1 do: [ :earlier |
            (names at: index) = (names at: earlier) ifTrue: [
                self fail: ''Duplicate variable declaration.'' ] ] ]'.

STCompiler compile: 'validate: names separateFrom: locals error: message
    names do: [ :name | (locals includes: name) ifTrue: [ self fail: message ] ]'.

STCompiler compile: 'bodyUntil: terminator
    | temporaries expressions returning |
    temporaries := STCompilerList new.
    (self kind = #binary and: [ self tokenValue = ''||'' ]) ifTrue: [ self advance ] ifFalse: [
        self kind = #bar ifTrue: [
            self advance.
            [ self kind = #identifier ] whileTrue: [ temporaries add: self identifier ].
            self expect: #bar ] ].
    temporaries := temporaries elements.
    self validateNames: temporaries.
    expressions := STCompilerList new.
    [ self kind ~= terminator and: [ self kind ~= #end ] ] whileTrue: [
        returning := self kind = #caret.
        expressions add: (returning ifTrue: [ self returnStatement ] ifFalse: [ self expression ]).
        self kind = #period ifTrue: [ self advance ] ifFalse: [
            self kind = terminator ifFalse: [ self fail: ''Expected a period between expressions.'' ] ].
        (returning and: [ self kind ~= terminator and: [ self kind ~= #end ] ]) ifTrue: [
            self fail: ''A return must be the last statement.'' ] ].
    ^ self pair: temporaries with: expressions elements'.

STCompiler compile: 'returnStatement
    | position |
    position := current.
    self advance.
    ^ self node: #returnValue at: position with: self expression with: nil'.

STCompiler compile: 'expression
    | result |
    expressionDepth := expressionDepth + 1.
    expressionDepth > 128 ifTrue: [ self fail: ''Expression is nested too deeply.'' ].
    result := self expressionNode.
    expressionDepth := expressionDepth - 1.
    ^ result'.

STCompiler compile: 'expressionNode
    | position name first messages |
    position := current.
    (self kind = #identifier and: [ (lookahead at: 1) = #assign ]) ifTrue: [
        name := self identifier.
        self advance.
        ^ self node: #assignment at: position with: name with: self expression ].
    first := self keywordExpression.
    self kind = #semicolon ifFalse: [ ^ first ].
    (first at: 1) = #send ifFalse: [ self fail: ''A cascade must follow a message.'' ].
    messages := STCompilerList new.
    messages add: (first at: 5).
    [ self kind = #semicolon ] whileTrue: [
        self advance.
        messages add: self cascadeMessage ].
    ^ self node: #cascade at: position with: (first at: 4) with: messages elements'.

STCompiler compile: 'keywordExpression
    | receiver |
    receiver := self binaryExpression.
    self kind = #keyword ifFalse: [ ^ receiver ].
    ^ self sendTo: receiver message: self keywordMessage'.

STCompiler compile: 'keywordMessage
    | selector arguments |
    selector := ''''.
    arguments := STCompilerList new.
    [ self kind = #keyword ] whileTrue: [
        selector := selector , self tokenValue.
        self advance.
        arguments add: self binaryExpression ].
    ^ self pair: selector with: arguments elements'.

STCompiler compile: 'binaryExpression
    | receiver |
    receiver := self unaryExpression.
    [ #(binary bar) includes: self kind ] whileTrue: [
        receiver := self sendTo: receiver message: self binaryMessage ].
    ^ receiver'.

STCompiler compile: 'binaryMessage
    | selector |
    selector := self tokenValue.
    self advance.
    ^ self pair: selector with: (self single: self unaryExpression)'.

STCompiler compile: 'unaryExpression
    | receiver |
    receiver := self primary.
    [ self kind = #identifier ] whileTrue: [
        receiver := self sendTo: receiver message: self unaryMessage ].
    ^ receiver'.

STCompiler compile: 'unaryMessage
    ^ self pair: self identifier with: #()'.

STCompiler compile: 'cascadeMessage
    self kind = #identifier ifTrue: [ ^ self unaryMessage ].
    (#(binary bar) includes: self kind) ifTrue: [ ^ self binaryMessage ].
    self kind = #keyword ifTrue: [ ^ self keywordMessage ].
    self fail: ''Expected a message after ;.'''.

STCompiler compile: 'primary
    | position kind payload node |
    position := current.
    kind := self kind.
    kind = #unsupportedNumber ifTrue: [ ^ self fail: self tokenValue ].
    kind = #float ifTrue: [
        payload := self floatFrom: self tokenValue.
        self advance.
        ^ self node: #literal at: position with: payload with: nil ].
    (#(integer string symbol identifier character) includes: kind) ifTrue: [
        payload := self tokenValue.
        self advance.
        kind = #identifier ifTrue: [ ^ self node: #variable at: position with: payload with: nil ].
        kind = #symbol ifTrue: [ payload := payload asSymbol ].
        kind = #character ifTrue: [ payload := payload asCharacter ].
        ^ self node: #literal at: position with: payload with: nil ].
    (kind = #binary and: [ self tokenValue = ''-'' ]) ifTrue: [
        ^ self node: #literal at: position with: self negativeNumber with: nil ].
    kind = #leftParen ifTrue: [
        self advance.
        node := self expression.
        self expect: #rightParen.
        ^ node ].
    kind = #leftBracket ifTrue: [ ^ self blockAt: position ].
    kind = #arrayStart ifTrue: [
        self advance.
        ^ self node: #literal at: position with: self arrayElements with: nil ].
    self fail: ''Expected an expression.'''.

STCompiler compile: 'blockAt: position
    | parameters body |
    self advance.
    parameters := STCompilerList new.
    [ self kind = #colon ] whileTrue: [
        self advance.
        parameters add: self identifier ].
    parameters := parameters elements.
    parameters isEmpty ifFalse: [
        (self kind = #binary and: [ self tokenValue = ''||'' ])
            ifTrue: [ current at: 1 put: #bar; at: 3 put: (current at: 3) + 1; at: 4 put: ''|'' ]
            ifFalse: [ self expect: #bar ] ].
    self validateNames: parameters.
    body := self bodyUntil: #rightBracket.
    self validate: parameters separateFrom: (body at: 1) error: ''A block argument is also declared as a local variable.''.
    self expect: #rightBracket.
    ^ self node: #block at: position with: parameters with: body'.

STCompiler compile: 'negativeNumber
    | number |
    self advance.
    self kind = #unsupportedNumber ifTrue: [ ^ self fail: self tokenValue ].
    self kind = #float ifTrue: [
        number := self floatFrom: self tokenValue.
        self advance.
        ^ number negated ].
    self kind = #integer ifFalse: [ self fail: ''Expected an integer after -.'' ].
    number := self tokenValue.
    self advance.
    ^ number negated'.

STCompiler compile: 'floatFrom: spelling
    | result |
    result := spelling parseFloatOrNil.
    result isNil ifTrue: [ ^ self fail: ''Floating-point literal is outside the supported range.'' ].
    ^ result'.

STCompiler compile: 'arrayElements
    | elements |
    elements := STCompilerList new.
    [ self kind ~= #rightParen ] whileTrue: [ elements add: self arrayElement ].
    self advance.
    ^ elements elements'.

STCompiler compile: 'arrayElement
    | kind payload |
    kind := self kind.
    kind = #unsupportedNumber ifTrue: [ ^ self fail: self tokenValue ].
    kind = #float ifTrue: [
        payload := self floatFrom: self tokenValue.
        self advance.
        ^ payload ].
    (#(integer string symbol identifier keyword character) includes: kind) ifTrue: [
        payload := self tokenValue.
        self advance.
        kind = #identifier ifTrue: [
            payload = ''nil'' ifTrue: [ ^ nil ].
            payload = ''true'' ifTrue: [ ^ true ].
            payload = ''false'' ifTrue: [ ^ false ] ].
        (#(symbol identifier keyword) includes: kind) ifTrue: [ ^ payload asSymbol ].
        kind = #character ifTrue: [ ^ payload asCharacter ].
        ^ payload ].
    (kind = #binary and: [ self tokenValue = ''-'' ]) ifTrue: [ ^ self negativeNumber ].
    (#(leftParen arrayStart) includes: kind) ifTrue: [ self advance. ^ self arrayElements ].
    self fail: ''Expected a literal or ) in the array.'''.

STCompiler compile: 'sendTo: receiver message: message
    ^ self node: #send at: receiver with: receiver with: message'.

STCompiler compile: 'node: tag at: position with: first with: second
    | node |
    node := Array new: 5.
    node at: 1 put: tag; at: 2 put: (position at: 2); at: 3 put: (position at: 3).
    node at: 4 put: first; at: 5 put: second.
    ^ node'.

STCompiler compile: 'single: first
    | result |
    result := Array new: 1.
    result at: 1 put: first.
    ^ result'.

STCompiler compile: 'pair: first with: second
    | result |
    result := Array new: 2.
    result at: 1 put: first; at: 2 put: second.
    ^ result'.

STCompiler compile: 'triple: first with: second with: third
    | result |
    result := Array new: 3.
    result at: 1 put: first; at: 2 put: second; at: 3 put: third.
    ^ result'.
