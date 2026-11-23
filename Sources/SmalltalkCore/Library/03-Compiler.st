"Kompiliert Methoden und Workspace-Ausdrücke in Syntaxbäume für die VM."

Object subclass: #STCompiler instanceVariableNames: 'scanner current lookahead expressionDepth'.

STCompiler compile: 'initialize ^ self'.

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
    kind = #binary ifTrue: [
        selector := self tokenValue.
        self advance.
        parameters add: self identifier ].
    kind = #keyword ifTrue: [
        selector := ''''.
        [ self kind = #keyword ] whileTrue: [
            selector := selector , self tokenValue.
            self advance.
            parameters add: self identifier ] ].
    selector isNil ifTrue: [ self fail: ''Methodenkopf erwartet, zum Beispiel increment oder add: amount.'' ].
    parameters := parameters elements.
    self validateNames: parameters.
    body := self workspaceBody.
    self validate: parameters separateFrom: (body at: 1) error: ''Argument und lokale Variable haben denselben Namen.''.
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
    self kind = kind ifFalse: [ self fail: (self tokenLabel: kind) , '' erwartet, gefunden: '' , (self tokenLabel: self kind) , ''.'' ].
    self advance'.

STCompiler compile: 'tokenLabel: kind
    kind = #end ifTrue: [ ^ ''Ende des Quelltexts'' ].
    kind = #rightBracket ifTrue: [ ^ '']'' ].
    kind = #rightParen ifTrue: [ ^ '')'' ].
    kind = #bar ifTrue: [ ^ ''|'' ].
    kind = #period ifTrue: [ ^ ''.'' ].
    ^ kind asString'.

STCompiler compile: 'identifier
    | name |
    self kind = #identifier ifFalse: [ self fail: ''Variablenname erwartet.'' ].
    name := self tokenValue.
    self advance.
    ^ name'.

STCompiler compile: 'validateNames: names
    names do: [ :name |
        ((name at: 1) isLowercase and: [
            (#(''self'' ''super'' ''true'' ''false'' ''nil'' ''thisContext'') includes: name) not ]) ifFalse: [
                self fail: ''Variablennamen müssen klein beginnen und dürfen keine Pseudovariablen sein.'' ] ].
    1 to: names size do: [ :index |
        1 to: index - 1 do: [ :earlier |
            (names at: index) = (names at: earlier) ifTrue: [
                self fail: ''Variablenname ist doppelt deklariert.'' ] ] ]'.

STCompiler compile: 'validate: names separateFrom: locals error: message
    names do: [ :name | (locals includes: name) ifTrue: [ self fail: message ] ]'.

STCompiler compile: 'bodyUntil: terminator
    | temporaries expressions |
    temporaries := STCompilerList new.
    self kind = #bar ifTrue: [
        self advance.
        [ self kind = #identifier ] whileTrue: [ temporaries add: self identifier ].
        self expect: #bar ].
    temporaries := temporaries elements.
    self validateNames: temporaries.
    expressions := STCompilerList new.
    [ self kind ~= terminator and: [ self kind ~= #end ] ] whileTrue: [
        expressions add: self expression.
        self kind = #period ifTrue: [ self advance ] ifFalse: [
            self kind = terminator ifFalse: [ self fail: ''Zwischen Ausdrücken wird ein Punkt erwartet.'' ] ] ].
    ^ self pair: temporaries with: expressions elements'.

STCompiler compile: 'expression
    | result |
    expressionDepth := expressionDepth + 1.
    expressionDepth > 128 ifTrue: [ self fail: ''Ausdruck ist zu tief verschachtelt.'' ].
    result := self expressionNode.
    expressionDepth := expressionDepth - 1.
    ^ result'.

STCompiler compile: 'expressionNode
    | position name first messages |
    position := current.
    self kind = #caret ifTrue: [
        self advance.
        ^ self node: #returnValue at: position with: self expression with: nil ].
    (self kind = #identifier and: [ (lookahead at: 1) = #assign ]) ifTrue: [
        name := self identifier.
        self advance.
        ^ self node: #assignment at: position with: name with: self expression ].
    first := self keywordExpression.
    self kind = #semicolon ifFalse: [ ^ first ].
    (first at: 1) = #send ifFalse: [ self fail: ''Vor einer Kaskade muss eine Nachricht stehen.'' ].
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
    [ self kind = #binary ] whileTrue: [
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
    self kind = #binary ifTrue: [ ^ self binaryMessage ].
    self kind = #keyword ifTrue: [ ^ self keywordMessage ].
    self fail: ''Nach ; wird eine Nachricht erwartet.'''.

STCompiler compile: 'primary
    | position kind payload node |
    position := current.
    kind := self kind.
    (#(integer string symbol identifier) includes: kind) ifTrue: [
        payload := self tokenValue.
        self advance.
        kind = #identifier ifTrue: [ ^ self node: #variable at: position with: payload with: nil ].
        kind = #symbol ifTrue: [ payload := payload asSymbol ].
        ^ self node: #literal at: position with: payload with: nil ].
    (kind = #binary and: [ self tokenValue = ''-'' ]) ifTrue: [
        ^ self node: #literal at: position with: self negativeNumber with: nil ].
    kind = #minimumMagnitude ifTrue: [ self fail: ''Ganzzahl ist zu groß (64-Bit-Grenze).'' ].
    kind = #leftParen ifTrue: [
        self advance.
        node := self expression.
        self expect: #rightParen.
        ^ node ].
    kind = #leftBracket ifTrue: [ ^ self blockAt: position ].
    kind = #arrayStart ifTrue: [
        self advance.
        ^ self node: #literal at: position with: self arrayElements with: nil ].
    self fail: ''Ausdruck erwartet.'''.

STCompiler compile: 'blockAt: position
    | parameters body |
    self advance.
    parameters := STCompilerList new.
    [ self kind = #colon ] whileTrue: [
        self advance.
        parameters add: self identifier ].
    parameters := parameters elements.
    parameters isEmpty ifFalse: [ self expect: #bar ].
    self validateNames: parameters.
    body := self bodyUntil: #rightBracket.
    self validate: parameters separateFrom: (body at: 1) error: ''Blockargument ist auch als lokale Variable deklariert.''.
    self expect: #rightBracket.
    ^ self node: #block at: position with: parameters with: body'.

STCompiler compile: 'negativeNumber
    | number |
    self advance.
    self kind = #minimumMagnitude ifTrue: [
        self advance.
        ^ ''-9223372036854775808'' asIntegerOrNil ].
    self kind = #integer ifFalse: [ self fail: ''Nach - wird eine Ganzzahl erwartet.'' ].
    number := self tokenValue.
    self advance.
    ^ number negated'.

STCompiler compile: 'arrayElements
    | elements |
    elements := STCompilerList new.
    [ self kind ~= #rightParen ] whileTrue: [ elements add: self arrayElement ].
    self advance.
    ^ elements elements'.

STCompiler compile: 'arrayElement
    | kind payload |
    kind := self kind.
    (#(integer string symbol identifier keyword) includes: kind) ifTrue: [
        payload := self tokenValue.
        self advance.
        (#(symbol identifier keyword) includes: kind) ifTrue: [ ^ payload asSymbol ].
        ^ payload ].
    (kind = #binary and: [ self tokenValue = ''-'' ]) ifTrue: [ ^ self negativeNumber ].
    (#(leftParen arrayStart) includes: kind) ifTrue: [ self advance. ^ self arrayElements ].
    self fail: ''Literal oder ) im Array erwartet.'''.

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
