"ANSI file streams (J20 5.9–5.10). Text uses UTF-8 and writes LF.
An open file belongs to the running VM. Its stream is closed on image load."

Object subclass: #FileStream instanceVariableNames: 'externalType'.
FileStream subclass: #ReadFileStream instanceVariableNames: ''.
FileStream subclass: #WriteFileStream instanceVariableNames: ''.

FileStream compileClass: 'read: path
    ^ self read: path type: #text'.

FileStream compileClass: 'read: path type: type
    ^ ReadFileStream new _openFile: path mode: #read check: false type: type'.

FileStream compileClass: 'write: path
    ^ self write: path mode: #create'.

FileStream compileClass: 'write: path mode: mode
    ^ self write: path mode: mode check: false type: #text'.

FileStream compileClass: 'write: path mode: mode check: check type: type
    (#(#create #append #truncate) includes: mode)
        ifFalse: [ self error: ''Expected #create, #append or #truncate.'' ].
    ^ WriteFileStream new _openFile: path mode: mode check: check type: type'.

FileStream compile: 'externalType
    ^ externalType'.

FileStream compile: 'isBinary
    ^ self externalType == #binary'.

FileStream compile: 'isText
    ^ self externalType == #text'.

FileStream compile: 'contents
    ^ self _fileContents'.

FileStream compile: 'isEmpty
    ^ self _fileIsEmpty'.

FileStream compile: 'position
    ^ self _filePosition'.

FileStream compile: 'position: amount
    self _seekFile: amount'.

FileStream compile: 'reset
    self _seekFile: 0'.

FileStream compile: 'setToEnd
    self _seekFileToEnd'.

FileStream compile: 'close
    self _closeFile'.

ReadFileStream compile: 'atEnd
    ^ self _fileAtEnd'.

ReadFileStream compile: 'next
    ^ self _readFileElement'.

ReadFileStream compile: 'next: amount
    ^ self _readFileElements: amount'.

ReadFileStream compile: 'peek
    ^ self _peekFileElement'.

ReadFileStream compile: 'peekFor: element
    | next |
    next := self peek.
    ^ next notNil and: [ next = element ]'.

ReadFileStream compile: 'nextMatchFor: element
    | next |
    next := self next.
    ^ next notNil and: [ next = element ]'.

ReadFileStream compile: 'do: operation
    | element |
    [ (element := self next) notNil ] whileTrue: [ operation value: element ]'.

ReadFileStream compile: 'skip: count
    self _skipFileElements: count'.

ReadFileStream compile: 'skipTo: element
    ^ ((self _scanFileUntil: (Array with: element) collecting: false) at: 2) notNil'.

ReadFileStream compile: 'upTo: element
    ^ (self _scanFileUntil: (Array with: element) collecting: true) at: 1'.

ReadFileStream compile: 'nextLine
    | result |
    self isText ifFalse: [ self error: ''A binary file stream has no text lines.'' ].
    result := self _scanFileUntil: (Array with: Character cr with: Character lf) collecting: true.
    ((result at: 2) = Character cr and: [ self peekFor: Character lf ])
        ifTrue: [ self next ].
    ^ result at: 1'.

WriteFileStream compile: 'nextPut: element
    self _writeFileElements: (Array with: element).
    ^ element'.

WriteFileStream compile: 'nextPutAll: elements
    self _writeFileElements: elements'.

WriteFileStream compile: 'cr
    self nextPut: Character lf'.

WriteFileStream compile: 'space
    self nextPut: Character space'.

WriteFileStream compile: 'tab
    self nextPut: Character tab'.

WriteFileStream compile: 'flush
    self _flushFile'.
