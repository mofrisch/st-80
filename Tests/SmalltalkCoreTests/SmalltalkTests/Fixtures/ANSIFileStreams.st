"Uses a fresh directory supplied by the host test runner."

TestCase subclass: #ANSIFileStreamTest instanceVariableNames: 'streams'.

ANSIFileStreamTest compile: 'setUp
    streams := OrderedCollection new'.

ANSIFileStreamTest compile: 'tearDown
    streams do: [ :stream | stream close ]'.

ANSIFileStreamTest compile: 'path: name
    ^ ansiFileStreamDirectory , ''/'' , name'.

ANSIFileStreamTest compile: 'keep: stream
    streams add: stream.
    ^ stream'.

ANSIFileStreamTest compile: 'assertError: operation
    | raised |
    raised := [ operation value. false ] on: Error do: [ :error | true ].
    self assert: raised'.

ANSIFileStreamTest compile: 'testTextWritingAndFlush
    | file writer reader |
    file := self path: ''text.txt''.
    writer := self keep: (FileStream write: file).
    self assert: writer isText.
    self deny: writer isBinary.
    self assert: writer externalType equals: #text.
    self assert: writer isEmpty.
    self deny: (writer respondsTo: #next).
    writer nextPutAll: ''Grüße''; space; nextPut: $猫; tab; nextPut: $!; cr; flush.
    self assert: writer position equals: 10.
    reader := self keep: (FileStream read: file).
    self deny: (reader respondsTo: #nextPut:).
    self assert: reader nextLine equals: (''Grüße 猫'' , Character tab asString , ''!'').
    self assert: reader atEnd.
    self assert: writer contents equals: reader contents'.

ANSIFileStreamTest compile: 'testTextPositionAndLines
    | file reader text |
    file := self path: ''lines.txt''.
    text := ''é🐱'' , Character cr asString , Character lf asString ,
        ''ein'' , Character cr asString , ''zwei'' , Character lf asString , ''Ende''.
    (self keep: (FileStream write: file)) nextPutAll: text; close.
    reader := self keep: (FileStream read: file asSymbol type: #text).
    self assert: (reader peekFor: $é).
    self assert: reader position equals: 0.
    self assert: reader next equals: $é.
    self assert: (reader nextMatchFor: $🐱).
    self assert: reader position equals: 2.
    self assert: reader contents equals: text.
    self assert: reader position equals: 2.
    reader reset.
    self assert: reader nextLine equals: ''é🐱''.
    self assert: reader position equals: 4.
    self assert: reader nextLine equals: ''ein''.
    self assert: reader nextLine equals: ''zwei''.
    self assert: reader nextLine equals: ''Ende''.
    self assert: reader peek isNil.
    reader position: 1.
    self assert: reader peek equals: $🐱.
    self assertError: [ reader position: text size ].
    self assertError: [ reader position: -1 ].
    self assertError: [ reader position: #end ].
    self assert: reader position equals: 1.
    reader setToEnd.
    self assert: reader position equals: text size'.

ANSIFileStreamTest compile: 'testBinaryReadingAndWriting
    | file writer reader bytes result |
    file := self path: ''bytes.bin''.
    writer := self keep: (FileStream write: file mode: #create check: true type: #binary).
    self assert: writer isBinary.
    self deny: writer isText.
    self assert: writer externalType equals: #binary.
    bytes := ByteArray withAll: #(0 255 128 255 42).
    writer nextPutAll: bytes; close.
    reader := self keep: (FileStream read: file type: #binary).
    self assert: reader contents class equals: ByteArray.
    self assert: reader contents asArray equals: bytes asArray.
    result := reader next: 0.
    self assert: result class equals: ByteArray.
    self assert: result isEmpty.
    self assert: (reader next: 2) asArray equals: #(0 255).
    self assert: (reader upTo: 255) asArray equals: #(128).
    self assert: reader position equals: 4.
    self assert: (reader upTo: 17) asArray equals: #(42).
    self assert: (reader upTo: 17) isEmpty.
    self assertError: [ reader nextLine ].
    self assertError: [ reader next: -1 ].
    reader reset.
    self assert: (reader skipTo: 128).
    self assert: reader next equals: 255.
    self deny: (reader skipTo: 1).
    reader reset; skip: 3.
    result := OrderedCollection new.
    reader do: [ :each | result add: each ].
    self assert: result asArray equals: #(255 42)'.

ANSIFileStreamTest compile: 'testCreationModesAndExistenceChecks
    | file writer |
    file := self path: ''modes.txt''.
    self assertError: [ FileStream read: file ].
    self assertError: [ FileStream write: file mode: #append check: true type: #text ].
    self assertError: [ FileStream write: file mode: #truncate check: true type: #text ].
    writer := self keep: (FileStream write: file mode: #append).
    writer nextPutAll: ''é''; close.
    self assertError: [ FileStream write: file mode: #create check: true type: #text ].
    writer := self keep: (FileStream write: file mode: #append check: true type: #text).
    self assert: writer contents equals: ''é''.
    self assert: writer position equals: 1.
    writer nextPutAll: ''🐱''; close.
    self assert: (self keep: (FileStream read: file)) contents equals: ''é🐱''.
    writer := self keep: (FileStream write: file mode: #truncate check: true type: #text).
    self assert: writer isEmpty.
    self assert: writer position equals: 0.
    writer nextPutAll: ''old''; close.
    writer := self keep: (FileStream write: file).
    self assert: writer isEmpty.
    self assert: writer position equals: 0.
    writer nextPutAll: ''new''; close.
    self assert: (self keep: (FileStream read: file)) contents equals: ''new''.
    writer := self keep: (FileStream write: (self path: ''truncated-new.txt'') mode: #truncate).
    self assert: writer isEmpty'.

ANSIFileStreamTest compile: 'testWritingOverExistingElements
    | file writer |
    file := self path: ''overwrite.txt''.
    writer := self keep: (FileStream write: file).
    writer nextPutAll: ''a🐱bc''.
    writer position: 1.
    writer nextPut: $é.
    self assert: writer contents equals: ''aébc''.
    self assert: writer position equals: 2.
    writer reset; nextPutAll: ''猫🙂''.
    self assert: writer contents equals: ''猫🙂bc''.
    writer setToEnd; nextPut: $!.
    self assert: writer contents equals: ''猫🙂bc!''.
    writer close.
    self assert: (self keep: (FileStream read: file)) contents equals: ''猫🙂bc!'''.

ANSIFileStreamTest compile: 'testTypeErrorsAndClosedStreams
    | file writer reader |
    file := self path: ''errors.bin''.
    self assertError: [ FileStream write: file mode: #unknown ].
    self assertError: [ FileStream write: file mode: #truncate check: nil type: #binary ].
    self assertError: [ FileStream write: file mode: #truncate check: false type: #unknown ].
    self assertError: [ FileStream read: file ].
    writer := self keep: (FileStream write: file mode: #truncate check: false type: #binary).
    writer nextPut: 20.
    self assertError: [ writer nextPut: 256 ].
    self assertError: [ writer nextPutAll: #(1 -1) ].
    self assertError: [ writer cr ].
    self assert: writer position equals: 1.
    self assert: writer contents asArray equals: #(20).
    writer close.
    self assertError: [ writer nextPut: 0 ].
    reader := self keep: (FileStream read: file type: #binary).
    reader close.
    self assertError: [ reader next ]'.
