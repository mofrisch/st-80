Object subclass: #ToolServices instanceVariableNames: ''.

Model subclass: #TranscriptModel instanceVariableNames: 'contents'.

TranscriptModel compile: 'initialize super initialize. contents := '''''.

TranscriptModel compile: 'text
    contents size = 0 ifTrue: [ ^ ''Transcript show: ''''Hallo''''; cr.'' ].
    ^ contents'.

TranscriptModel compile: 'append: aString
    | addition |
    addition := aString suffixFittingUTF8: 65536.
    contents := (contents suffixFittingUTF8: 65536 - addition utf8Size) , addition.
    self changed: #text'.

TranscriptModel compile: 'clear contents := ''''. self changed: #text'.

UIWindow subclass: #DevelopmentWindow instanceVariableNames: 'resultLabel resultCaption'.

DevelopmentWindow compile: 'heading: aString
    ^ UILabel new text: aString; role: #heading; yourself'.

DevelopmentWindow compile: 'caption: aString
    ^ UILabel new text: aString; role: #caption; yourself'.

DevelopmentWindow compile: 'resultPane
    | scroll |
    resultCaption := self caption: ''ERGEBNIS''.
    resultLabel := UILabel new role: #code; identifier: ''evaluationResult''; yourself.
    scroll := UIScroll new padding: 12; spacing: 5; heightFrom: 72 to: 110; yourself.
    scroll add: resultCaption; add: resultLabel.
    ^ scroll'.

DevelopmentWindow compile: 'result: outcome
    | success |
    success := outcome at: 1.
    resultCaption text: (success ifTrue: [ ''ERGEBNIS'' ] ifFalse: [ ''FEHLER'' ]).
    resultLabel role: (success ifTrue: [ #code ] ifFalse: [ #error ]).
    resultLabel text: ((outcome at: 2) suffixFittingUTF8: 65536)'.

DevelopmentWindow compile: 'imageBar
    | bar status save |
    status := UIColumn new spacing: 3; yourself.
    status add: (UILabel new role: #imageName; identifier: ''imageName''; yourself).
    status add: (UILabel new role: #imageStatus; identifier: ''imageStatus''; yourself).
    save := UIButton new title: ''Image speichern''; identifier: ''saveImageButton''; action: [ ToolVM requestSaveImage ]; yourself.
    bar := UIRow new padding: 12; yourself.
    bar add: status; add: UISpacer new; add: save.
    ^ bar'.

DevelopmentWindow subclass: #WorkspaceWindow instanceVariableNames: 'editor'.

WorkspaceWindow compile: 'initialize
    | root bar doIt printIt |
    super initialize.
    self kind: #workspace.
    self title: ''Workspace''.
    self resizeWidth: 720 height: 600.
    editor := UICodeEditor new identifier: ''workspaceEditor''; label: ''Smalltalk Workspace''; yourself.
    editor onChangeSend: #text: to: self.
    doIt := UIButton new title: ''Do it''; identifier: ''executeButton''; role: #primary; command: #doIt; yourself.
    doIt selectionFrom: editor action: [ :selected | self execute: selected printing: false ].
    printIt := UIButton new title: ''Print it''; command: #printIt; yourself.
    printIt selectionFrom: editor action: [ :selected | self execute: selected printing: true ].
    bar := UIRow new padding: 12; yourself.
    bar add: (self heading: ''Workspace''); add: UISpacer new; add: self examplesMenu; add: printIt; add: doIt.
    root := UIColumn new spacing: 0; yourself.
    root add: bar; add: UIDivider new; add: editor; add: UIDivider new; add: self resultPane; add: UIDivider new; add: self imageBar.
    self content: root.
    self result: (ToolVM success: ''Bereit. Auswahl oder gesamten Workspace mit ⌘D ausführen.'')'.

WorkspaceWindow compile: 'text: aString
    super text: aString.
    editor notNil ifTrue: [ editor text: aString ]'.

WorkspaceWindow compile: 'execute: selected printing: aBoolean
    | source outcome |
    source := selected size = 0 ifTrue: [ self text ] ifFalse: [ selected ].
    outcome := ToolVM evaluateSource: source.
    self result: outcome.
    (aBoolean and: [ outcome at: 1 ]) ifTrue: [ Transcript show: ''→ '' , (outcome at: 2); cr ].
    ^ outcome at: 2'.

WorkspaceWindow compile: 'examplesMenu
    | menu |
    menu := UIMenu new title: ''Beispiele''; yourself.
    menu add: (self exampleButton: ''Zähler'' key: #workspace).
    menu add: (self exampleButton: ''Arrays und Blöcke'' key: #collections).
    menu add: (self exampleButton: ''Eine eigene Klasse'' key: #classes).
    menu add: (self exampleButton: ''Fenster öffnen'' key: #windows).
    menu add: (self exampleButton: ''Eigene Oberfläche'' key: #userInterface).
    ^ menu'.

WorkspaceWindow compile: 'exampleButton: aTitle key: exampleKey
    ^ UIButton new title: aTitle; action: [
        | workspace |
        workspace := Desktop openWorkspace.
        workspace notNil ifTrue: [ workspace text: (ToolVM exampleAt: exampleKey) ] ]; yourself'.

DevelopmentWindow subclass: #BrowserWindow instanceVariableNames: 'categoryList classList protocolList methodList queryField editor category className protocolName selector originalSource header hint accept versions inspector inspectorPane creation nameField fieldsField'.

BrowserWindow compile: 'initialize
    | root navigation split source actions toolbar |
    super initialize.
    self kind: #browser.
    self title: ''System Browser''.
    category := ''Alle''.
    className := ''Counter''.
    protocolName := ''Alle''.
    categoryList := self list: ''categoryList'' selecting: #chooseCategory:.
    classList := self list: ''classList'' selecting: #chooseClass:.
    protocolList := self list: ''protocolList'' selecting: #chooseProtocol:.
    methodList := self list: ''methodList'' selecting: #chooseMethod:.
    queryField := UITextField new identifier: ''classFilter''; placeholder: ''Klassen filtern''; widthFrom: 135 to: 220; onChangeSend: #filter: to: self; yourself.
    editor := UICodeEditor new identifier: ''methodEditor''; label: ''Methodenquelltext''; onChangeSend: #draftChanged: to: self; yourself.
    header := self heading: ''''.
    hint := self caption: ''''.
    accept := UIButton new title: ''Akzeptieren''; identifier: ''executeButton''; role: #primary; command: #acceptMethod; onClickSend: #acceptMethod to: self; yourself.
    versions := UIButton new title: ''Versionen …''; identifier: ''methodVersionsButton''; onClickSend: #showVersions to: self; yourself.

    actions := UIRow new padding: 8; yourself.
    actions add: queryField; add: UISpacer new.
    actions add: (UIButton new title: ''Klasse anlegen …''; onClickSend: #showCreation to: self; yourself).
    actions add: (UIButton new title: ''Neue Methode''; onClickSend: #newMethod to: self; yourself).
    actions add: (UIButton new title: ''Details''; action: [ inspectorPane visible: inspectorPane visible not ]; yourself).

    navigation := UISplit new identifier: ''browserNavigation''; heightFrom: 135 to: 220; yourself.
    navigation add: (self pane: ''Klassenkategorien'' list: categoryList).
    navigation add: (self pane: ''Klassen'' list: classList).
    navigation add: (self pane: ''Protokolle'' list: protocolList).
    navigation add: (self pane: ''Methoden'' list: methodList).

    toolbar := UIRow new padding: 8; yourself.
    toolbar add: (UIColumn new spacing: 2; add: header; add: hint; yourself); add: UISpacer new; add: versions; add: accept.
    creation := self classForm.
    inspector := UILabel new role: #code; yourself.
    inspectorPane := UIScroll new widthFrom: 150 to: 245; padding: 12; visible: false; add: inspector; yourself.
    source := UIColumn new spacing: 0; heightFrom: 135 to: nil; yourself.
    source add: toolbar; add: UIDivider new; add: creation; add: (UISplit new add: editor; add: inspectorPane; yourself).
    split := UISplit new role: #vertical; add: navigation; add: source; yourself.
    root := UIColumn new spacing: 0; yourself.
    root add: actions; add: UIDivider new; add: split; add: UIDivider new.
    root add: (self resultPane heightFrom: 52 to: 78; yourself); add: UIDivider new; add: self imageBar.
    self content: root.
    self result: (ToolVM success: ''Bereit.'').
    self refreshTools.
    self refreshEditor'.

BrowserWindow compile: 'list: identifier selecting: message
    ^ UIList new identifier: identifier; role: #pane; onSelectSend: message to: self; yourself'.

BrowserWindow compile: 'pane: aTitle list: aList
    | labelBar |
    labelBar := UIRow new padding: 8; add: (self caption: aTitle); add: UISpacer new; yourself.
    ^ UIColumn new spacing: 0; widthFrom: 116 to: nil; add: labelBar; add: aList; yourself'.

BrowserWindow compile: 'selectedClass
    className isNil ifTrue: [ ^ nil ].
    ^ ToolVM classNamed: className'.

BrowserWindow compile: 'primitiveSelected
    selector isNil ifTrue: [ ^ false ].
    ^ self selectedClass isPrimitiveAt: selector'.

BrowserWindow compile: 'filter: aString queryField text: aString. self refreshClasses'.

BrowserWindow compile: 'classCategoryFor: name
    (#(''Object'' ''Class'' ''UndefinedObject'' ''Boolean'' ''True'' ''False'' ''Number'' ''Integer'' ''SmallInteger'' ''String'' ''Symbol'' ''Array'' ''BlockClosure'') includes: name) ifTrue: [ ^ ''Kernel'' ].
    (#(''STCompilerList'' ''STScanner'' ''STCompiler'') includes: name) ifTrue: [ ^ ''Compiler'' ].
    (#(''Transcript'' ''TranscriptModel'' ''ToolServices'' ''DevelopmentWindow'' ''WorkspaceWindow'' ''BrowserWindow'' ''TranscriptWindow'') includes: name) ifTrue: [ ^ ''Werkzeuge'' ].
    (#(''Model'' ''Controller'' ''UIBinding'' ''SystemWindow'' ''DesktopModel'' ''DisplayScreen'' ''DesktopManager''
       ''UIElement'' ''UILabel'' ''UIButton'' ''UITextField'' ''UIContainer'' ''UIColumn'' ''UIRow'' ''UISpacer''
       ''UIWindow'' ''UICodeEditor'' ''UIList'' ''UISplit'' ''UIScroll'' ''UIMenu'' ''UIDivider'') includes: name)
        ifTrue: [ ^ ''Oberfläche'' ].
    name = ''Counter'' ifTrue: [ ^ ''Beispiele'' ].
    ^ ''Benutzerklassen'''.

BrowserWindow compile: 'matchesCategory: name
    ^ category = ''Alle'' or: [ (self classCategoryFor: name) = category ]'.

BrowserWindow compile: 'refreshClasses
    | query |
    query := queryField text.
    categoryList items: #(''Alle'' ''Kernel'' ''Compiler'' ''Oberfläche'' ''Werkzeuge'' ''Beispiele'' ''Benutzerklassen''); selection: category.
    classList items: (ToolVM classNames select: [ :each |
        (self matchesCategory: each) and: [ query size = 0 or: [ each includesIgnoringCase: query ] ] ]).
    classList selection: className'.

BrowserWindow compile: 'protocolOf: name in: target
    (target isPrimitiveAt: name) ifTrue: [ ^ ''VM-Primitiven'' ].
    name = ''initialize'' ifTrue: [ ^ ''Initialisierung'' ].
    (name includes: '':'') ifTrue: [ ^ ''Schlüsselwort'' ].
    (name at: 1) isLetter ifTrue: [ ^ ''Unär'' ].
    ^ ''Binär'''.

BrowserWindow compile: 'refreshMethods
    | target methods protocols |
    target := self selectedClass.
    methods := target isNil ifTrue: [ #() ] ifFalse: [ target methodNames ].
    protocols := methods collect: [ :each | self protocolOf: each in: target ].
    (protocolName notNil and: [ protocols includes: protocolName ]) ifFalse: [ protocolName := ''Alle'' ].
    protocolList items: (#(''Alle'' ''Initialisierung'' ''Unär'' ''Schlüsselwort'' ''Binär'' ''VM-Primitiven'') select: [ :each |
        each = ''Alle'' or: [ protocols includes: each ] ]); selection: protocolName.
    methodList items: (protocolName = ''Alle'' ifTrue: [ methods ] ifFalse: [
        methods select: [ :each | (self protocolOf: each in: target) = protocolName ] ]).
    methodList selection: selector'.

BrowserWindow compile: 'refreshTools
    | target textValue |
    self refreshClasses.
    self refreshMethods.
    target := self selectedClass.
    (selector notNil and: [ target notNil ]) ifTrue: [
        textValue := target methodSourceAt: selector.
        (textValue notNil and: [ textValue ~= originalSource and: [ editor text = originalSource ] ]) ifTrue: [
            editor text: textValue. originalSource := textValue. self refreshEditor ] ].
    self refreshInspector'.

BrowserWindow compile: 'refreshInspector
    | target description |
    target := self selectedClass.
    description := target isNil ifTrue: [ '''' ] ifFalse: [
        ''KLASSE IM BROWSER'' , ToolVM lineBreak , className , ToolVM lineBreak ,
        (target superclass isNil ifTrue: [ '''' ] ifFalse: [ target superclass name asString ]) , ToolVM lineBreak ,
        ''Instanzvariablen: '' , target instanceVariableNamesText , ToolVM lineBreak , ToolVM lineBreak ].
    inspector text: (description , ''GEMEINSAME VARIABLEN'' , ToolVM lineBreak , ToolVM bindingSummary)'.

BrowserWindow compile: 'refreshEditor
    | primitive name |
    primitive := self primitiveSelected.
    name := className isNil ifTrue: [ ''Keine Klasse ausgewählt'' ] ifFalse: [ className ].
    header text: (selector isNil ifTrue: [ name ] ifFalse: [ name , '' » '' , selector ]).
    hint text: (primitive ifTrue: [ ''VM-Primitive'' ] ifFalse: [ ''Instanzseite'' ]).
    editor readOnly: (primitive or: [ className isNil ]).
    versions enabled: (selector notNil and: [ primitive not ]).
    self draftChanged: editor text'.

BrowserWindow compile: 'draftChanged: aString
    accept enabled: (className notNil and: [ self primitiveSelected not and: [ aString size > 0 ] ])'.

BrowserWindow compile: 'chooseCategory: name
    category := name isNil ifTrue: [ ''Alle'' ] ifFalse: [ name ].
    (className notNil and: [ (self matchesCategory: className) not ]) ifTrue: [ ^ self chooseClass: nil ].
    self refreshClasses'.

BrowserWindow compile: 'chooseClass: name
    className := name.
    protocolName := ''Alle''.
    self chooseMethod: nil.
    self refreshTools'.

BrowserWindow compile: 'chooseProtocol: name
    protocolName := name.
    (selector notNil and: [ name notNil and: [ name ~= ''Alle'' and: [ (self protocolOf: selector in: self selectedClass) ~= name ] ] ])
        ifTrue: [ self chooseMethod: nil ].
    self refreshMethods'.

BrowserWindow compile: 'chooseMethod: name
    selector := name.
    originalSource := selector isNil ifTrue: [ '''' ] ifFalse: [ self selectedClass methodSourceAt: selector ].
    originalSource isNil ifTrue: [ originalSource := '''' ].
    editor text: originalSource.
    methodList selection: selector.
    self refreshEditor'.

BrowserWindow compile: 'newMethod
    className isNil ifTrue: [ ^ self ].
    self chooseMethod: nil.
    editor text: ''newMethod'' , ToolVM lineBreak , ''    ^ self''.
    self refreshEditor'.

BrowserWindow compile: 'acceptMethod
    | outcome target |
    target := self selectedClass.
    (target isNil or: [ self primitiveSelected or: [ editor text size = 0 ] ]) ifTrue: [ ^ self ].
    outcome := ToolVM compileSource: editor text in: target.
    (outcome at: 1) ifTrue: [
        selector := outcome at: 2.
        originalSource := editor text.
        (protocolName ~= ''Alle'' and: [ (self protocolOf: selector in: target) ~= protocolName ]) ifTrue: [ protocolName := ''Alle'' ].
        self refreshTools.
        self refreshEditor.
        self result: (ToolVM success: className , '' » '' , selector)
    ] ifFalse: [ self result: outcome ]'.

BrowserWindow compile: 'showVersions
    (selector notNil and: [ self primitiveSelected not ]) ifTrue: [ ToolVM requestVersionsFor: className selector: selector ]'.

BrowserWindow compile: 'classForm
    | form buttons |
    nameField := UITextField new label: ''Klassenname''; placeholder: ''Greeter''; yourself.
    fieldsField := UITextField new label: ''Instanzvariablen''; placeholder: ''name age''; yourself.
    buttons := UIRow new yourself.
    buttons add: (UIButton new title: ''Abbrechen''; onClickSend: #hideCreation to: self; yourself).
    buttons add: (UIButton new title: ''Anlegen''; role: #primary; onClickSend: #createClass to: self; yourself).
    form := UIColumn new padding: 12; visible: false; yourself.
    form add: (self heading: ''Eine neue Klasse''); add: nameField; add: fieldsField; add: buttons.
    ^ form'.

BrowserWindow compile: 'showCreation
    nameField text: ''''. fieldsField text: ''''. creation visible: true'.

BrowserWindow compile: 'hideCreation creation visible: false'.

BrowserWindow compile: 'createClass
    | outcome |
    outcome := ToolVM createSubclass: nameField text fields: fieldsField text.
    (outcome at: 1) ifTrue: [
        self hideCreation.
        category := ''Benutzerklassen''.
        queryField text: ''''.
        self chooseClass: (outcome at: 2).
        self newMethod ].
    self result: outcome'.

DevelopmentWindow subclass: #TranscriptWindow instanceVariableNames: ''.

TranscriptWindow compile: 'initialize
    | root toolbar output scroll |
    super initialize.
    self kind: #transcript.
    self title: ''Transcript''.
    toolbar := UIRow new padding: 12; yourself.
    toolbar add: (self heading: ''Transcript''); add: UISpacer new.
    toolbar add: (UIButton new title: ''Leeren''; onClickSend: #clear to: TranscriptBuffer; yourself).
    output := UILabel new identifier: ''transcriptOutput''; role: #code; yourself.
    output bind: #text to: TranscriptBuffer aspect: #text.
    scroll := UIScroll new role: #followEnd; padding: 12; yourself.
    scroll add: output.
    root := UIColumn new spacing: 0; yourself.
    root add: toolbar; add: UIDivider new; add: scroll.
    self content: root'.

Transcript compile: 'show: value
    | text |
    text := value class == String ifTrue: [ value ] ifFalse: [ value printString ].
    self record: text.
    TranscriptBuffer append: text'.

Transcript compile: 'cr self show: ToolVM lineBreak'.

Transcript compile: 'clear TranscriptBuffer clear'.
