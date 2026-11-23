Object subclass: #ToolServices instanceVariableNames: ''.

Model subclass: #TranscriptModel instanceVariableNames: 'contents'.

TranscriptModel compile: 'initialize super initialize. contents := '''''.

TranscriptModel compile: 'text
    contents size = 0 ifTrue: [ ^ ''Transcript show: ''''Hello''''; cr.'' ].
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
    resultCaption := self caption: ''RESULT''.
    resultLabel := UILabel new role: #code; identifier: ''evaluationResult''; yourself.
    scroll := UIScroll new padding: 12; spacing: 5; heightFrom: 72 to: 110; yourself.
    scroll add: resultCaption; add: resultLabel.
    ^ scroll'.

DevelopmentWindow compile: 'result: outcome
    | success |
    success := outcome at: 1.
    resultCaption text: (success ifTrue: [ ''RESULT'' ] ifFalse: [ ''ERROR'' ]).
    resultLabel role: (success ifTrue: [ #code ] ifFalse: [ #error ]).
    resultLabel text: ((outcome at: 2) suffixFittingUTF8: 65536)'.

DevelopmentWindow compile: 'imageBar
    | bar status save |
    status := UIColumn new spacing: 3; yourself.
    status add: (UILabel new role: #imageName; identifier: ''imageName''; yourself).
    status add: (UILabel new role: #imageStatus; identifier: ''imageStatus''; yourself).
    save := UIButton new title: ''Save Image''; identifier: ''saveImageButton''; action: [ ToolVM requestSaveImage ]; yourself.
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
    self result: (ToolVM success: ''Ready. Press ⌘D to run the selection or the entire workspace.'')'.

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
    menu := UIMenu new title: ''Examples''; yourself.
    menu add: (self exampleButton: ''Counter'' key: #workspace).
    menu add: (self exampleButton: ''Arrays and Blocks'' key: #collections).
    menu add: (self exampleButton: ''Create a Class'' key: #classes).
    menu add: (self exampleButton: ''Open Windows'' key: #windows).
    menu add: (self exampleButton: ''Custom Interface'' key: #userInterface).
    ^ menu'.

WorkspaceWindow compile: 'exampleButton: aTitle key: exampleKey
    ^ UIButton new title: aTitle; action: [
        | workspace |
        workspace := Desktop openWorkspace.
        workspace notNil ifTrue: [ workspace text: (ToolVM exampleAt: exampleKey) ] ]; yourself'.

DevelopmentWindow subclass: #BrowserWindow instanceVariableNames: 'categoryList classList protocolList methodList queryField editor category className protocolName selector originalSource header hint accept versions inspector inspectorPane creation nameField fieldsField organizationForm renameCategoryItem moveClassItem newProtocolItem renameProtocolItem moveMethodItem'.

BrowserWindow compile: 'initialize
    | root navigation split source actions toolbar categoryMenu protocolMenu |
    super initialize.
    self kind: #browser.
    self title: ''System Browser''.
    category := ''All''.
    className := ''Counter''.
    protocolName := ''All''.
    categoryList := self list: ''categoryList'' selecting: #chooseCategory:.
    classList := self list: ''classList'' selecting: #chooseClass:.
    protocolList := self list: ''protocolList'' selecting: #chooseProtocol:.
    methodList := self list: ''methodList'' selecting: #chooseMethod:.
    queryField := UITextField new identifier: ''classFilter''; placeholder: ''Filter Classes''; widthFrom: 135 to: 220; onChangeSend: #filter: to: self; yourself.
    editor := UICodeEditor new identifier: ''methodEditor''; label: ''Method Source''; onChangeSend: #draftChanged: to: self; yourself.
    header := self heading: ''''.
    hint := self caption: ''''.
    accept := UIButton new title: ''Accept''; identifier: ''executeButton''; role: #primary; command: #acceptMethod; onClickSend: #acceptMethod to: self; yourself.
    versions := UIButton new title: ''Versions …''; identifier: ''methodVersionsButton''; onClickSend: #showVersions to: self; yourself.

    actions := UIRow new padding: 8; yourself.
    actions add: queryField; add: UISpacer new.
    actions add: (UIButton new title: ''Create Class …''; onClickSend: #showCreation to: self; yourself).
    actions add: (UIButton new title: ''New Method''; onClickSend: #newMethod to: self; yourself).
    actions add: (UIButton new title: ''Details''; action: [ inspectorPane visible: inspectorPane visible not ]; yourself).

    renameCategoryItem := self organizationItem: ''Rename Category …'' id: ''renameCategory'' send: #renameCategory.
    moveClassItem := self organizationItem: ''Move Class …'' id: ''moveClass'' send: #moveClass.
    categoryMenu := UIMenu new title: ''Class Category Actions''; identifier: ''categoryActions''; role: #paneMenu; yourself.
    categoryMenu add: (self organizationItem: ''New Category …'' id: ''newCategory'' send: #newCategory).
    categoryMenu add: renameCategoryItem; add: moveClassItem.

    newProtocolItem := self organizationItem: ''New Protocol …'' id: ''newProtocol'' send: #newProtocol.
    renameProtocolItem := self organizationItem: ''Rename Protocol …'' id: ''renameProtocol'' send: #renameProtocol.
    moveMethodItem := self organizationItem: ''Move Method …'' id: ''moveMethod'' send: #moveMethod.
    protocolMenu := UIMenu new title: ''Method Protocol Actions''; identifier: ''protocolActions''; role: #paneMenu; yourself.
    protocolMenu add: newProtocolItem; add: renameProtocolItem; add: moveMethodItem.

    navigation := UISplit new identifier: ''browserNavigation''; heightFrom: 135 to: 220; yourself.
    navigation add: (self pane: ''Class Categories'' list: categoryList menu: categoryMenu).
    navigation add: (self pane: ''Classes'' list: classList menu: nil).
    navigation add: (self pane: ''Protocols'' list: protocolList menu: protocolMenu).
    navigation add: (self pane: ''Methods'' list: methodList menu: nil).

    toolbar := UIRow new padding: 8; yourself.
    toolbar add: (UIColumn new spacing: 2; add: header; add: hint; yourself); add: UISpacer new; add: versions; add: accept.
    creation := self classForm.
    organizationForm := BrowserOrganizationForm new.
    inspector := UILabel new role: #code; yourself.
    inspectorPane := UIScroll new widthFrom: 150 to: 245; padding: 12; visible: false; add: inspector; yourself.
    source := UIColumn new spacing: 0; heightFrom: 135 to: nil; yourself.
    source add: toolbar; add: UIDivider new; add: creation; add: organizationForm; add: (UISplit new add: editor; add: inspectorPane; yourself).
    split := UISplit new role: #vertical; add: navigation; add: source; yourself.
    root := UIColumn new spacing: 0; yourself.
    root add: actions; add: UIDivider new; add: split; add: UIDivider new.
    root add: (self resultPane heightFrom: 52 to: 78; yourself); add: UIDivider new; add: self imageBar.
    self content: root.
    self result: (ToolVM success: ''Ready.'').
    self refreshTools.
    self refreshEditor'.

BrowserWindow compile: 'list: identifier selecting: message
    ^ UIList new identifier: identifier; role: #pane; onSelectSend: message to: self; yourself'.

BrowserWindow compile: 'pane: aTitle list: aList menu: aMenu
    | labelBar |
    labelBar := UIRow new padding: 8; add: (self caption: aTitle); add: UISpacer new; yourself.
    aMenu notNil ifTrue: [ labelBar add: aMenu ].
    ^ UIColumn new spacing: 0; widthFrom: 145 to: nil; add: labelBar; add: aList; yourself'.

BrowserWindow compile: 'organizationItem: aTitle id: identifier send: message
    ^ UIButton new title: aTitle; identifier: identifier; onClickSend: message to: self; yourself'.

BrowserWindow compile: 'selectedClass
    className isNil ifTrue: [ ^ nil ].
    ^ ToolVM classNamed: className'.

BrowserWindow compile: 'primitiveSelected
    selector isNil ifTrue: [ ^ false ].
    ^ self selectedClass isPrimitiveAt: selector'.

BrowserWindow compile: 'filter: aString queryField text: aString. self refreshClasses'.

BrowserWindow compile: 'matchesCategory: name
    ^ category = ''All'' or: [ (SystemOrganization categoryOf: name) = category ]'.

BrowserWindow compile: 'withAll: entries
    | result |
    result := Array new: entries size + 1.
    result at: 1 put: ''All''.
    1 to: entries size do: [ :index | result at: index + 1 put: (entries at: index) ].
    ^ result'.

BrowserWindow compile: 'refreshClasses
    | query names |
    query := queryField text.
    names := SystemOrganization classCategories names.
    (category ~= ''All'' and: [ (names includes: category) not ]) ifTrue: [ category := ''All'' ].
    categoryList items: (self withAll: names); selection: category.
    classList items: (ToolVM classNames select: [ :each |
        (self matchesCategory: each) and: [ query size = 0 or: [ each includesIgnoringCase: query ] ] ]).
    classList selection: className'.

BrowserWindow compile: 'protocolOf: name in: target
    ^ (SystemOrganization protocolsOf: target) groupOf: name default: (SystemOrganization defaultProtocolFor: name in: target)'.

BrowserWindow compile: 'refreshMethods
    | target methods protocols names |
    target := self selectedClass.
    target isNil ifTrue: [
        protocolName := ''All''.
        protocolList items: #(''All''); selection: protocolName.
        methodList items: #(); selection: nil.
        ^ self ].
    methods := target methodNames.
    protocols := methods collect: [ :each | self protocolOf: each in: target ].
    names := (SystemOrganization protocolsOf: target) namesWith: protocols.
    (names includes: protocolName) ifFalse: [ protocolName := ''All'' ].
    protocolList items: (self withAll: names); selection: protocolName.
    protocolName ~= ''All'' ifTrue: [
        methods := methods select: [ :each | (self protocolOf: each in: target) = protocolName ] ].
    methodList items: methods.
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
    self refreshOrganizationActions.
    self refreshInspector'.

BrowserWindow compile: 'refreshInspector
    | target description |
    target := self selectedClass.
    description := target isNil ifTrue: [ '''' ] ifFalse: [
        ''BROWSER CLASS'' , ToolVM lineBreak , className , ToolVM lineBreak ,
        (target superclass isNil ifTrue: [ '''' ] ifFalse: [ target superclass name asString ]) , ToolVM lineBreak ,
        ''Instance Variables: '' , target instanceVariableNamesText , ToolVM lineBreak , ToolVM lineBreak ].
    inspector text: (description , ''SHARED VARIABLES'' , ToolVM lineBreak , ToolVM bindingSummary)'.

BrowserWindow compile: 'refreshEditor
    | primitive name |
    primitive := self primitiveSelected.
    name := className isNil ifTrue: [ ''No Class Selected'' ] ifFalse: [ className ].
    header text: (selector isNil ifTrue: [ name ] ifFalse: [ name , '' » '' , selector ]).
    hint text: (primitive ifTrue: [ ''VM Primitive'' ] ifFalse: [ ''Instance Side'' ]).
    editor readOnly: (primitive or: [ className isNil ]).
    versions enabled: (selector notNil and: [ primitive not ]).
    self refreshOrganizationActions.
    self draftChanged: editor text'.

BrowserWindow compile: 'draftChanged: aString
    accept enabled: (className notNil and: [ self primitiveSelected not and: [ aString size > 0 ] ])'.

BrowserWindow compile: 'chooseCategory: name
    category := name isNil ifTrue: [ ''All'' ] ifFalse: [ name ].
    (className notNil and: [ (self matchesCategory: className) not ]) ifTrue: [ ^ self chooseClass: nil ].
    self refreshClasses.
    self refreshOrganizationActions'.

BrowserWindow compile: 'chooseClass: name
    className := name.
    protocolName := ''All''.
    self chooseMethod: nil.
    self refreshTools'.

BrowserWindow compile: 'chooseProtocol: name
    protocolName := name.
    (selector notNil and: [ name notNil and: [ name ~= ''All'' and: [ (self protocolOf: selector in: self selectedClass) ~= name ] ] ])
        ifTrue: [ self chooseMethod: nil ].
    self refreshMethods.
    self refreshOrganizationActions'.

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
        protocolName ~= ''All'' ifTrue: [ (SystemOrganization protocolsOf: target) move: selector to: protocolName ].
        self refreshTools.
        self refreshEditor.
        self result: (ToolVM success: className , '' » '' , selector)
    ] ifFalse: [ self result: outcome ]'.

BrowserWindow compile: 'showVersions
    (selector notNil and: [ self primitiveSelected not ]) ifTrue: [ ToolVM requestVersionsFor: className selector: selector ]'.

BrowserWindow compile: 'classForm
    | form buttons |
    nameField := UITextField new label: ''Class Name''; placeholder: ''Greeter''; yourself.
    fieldsField := UITextField new label: ''Instance Variables''; placeholder: ''name age''; yourself.
    buttons := UIRow new yourself.
    buttons add: (UIButton new title: ''Cancel''; onClickSend: #hideCreation to: self; yourself).
    buttons add: (UIButton new title: ''Create''; role: #primary; onClickSend: #createClass to: self; yourself).
    form := UIColumn new padding: 12; visible: false; yourself.
    form add: (self heading: ''Create a Class''); add: nameField; add: fieldsField; add: buttons.
    ^ form'.

BrowserWindow compile: 'showCreation
    organizationForm cancel.
    nameField text: ''''. fieldsField text: ''''. creation visible: true'.

BrowserWindow compile: 'hideCreation creation visible: false'.

BrowserWindow compile: 'createClass
    | outcome created |
    outcome := ToolVM createSubclass: nameField text fields: fieldsField text.
    (outcome at: 1) ifTrue: [
        created := outcome at: 2.
        self hideCreation.
        category = ''All''
            ifTrue: [ category := SystemOrganization categoryOf: created ]
            ifFalse: [ SystemOrganization classCategories move: created to: category ].
        queryField text: ''''.
        self chooseClass: created.
        self newMethod ].
    self result: outcome'.

BrowserWindow compile: 'refreshOrganizationActions
    renameCategoryItem enabled: category ~= ''All''.
    moveClassItem enabled: className notNil.
    newProtocolItem enabled: className notNil.
    renameProtocolItem enabled: (className notNil and: [ protocolName ~= ''All'' ]).
    moveMethodItem enabled: (className notNil and: [ selector notNil ])'.

BrowserWindow compile: 'editGroupIn: grouping named: oldName prompt: prompt selecting: onSuccess
    self hideCreation.
    organizationForm edit: prompt name: (oldName isNil ifTrue: [ '''' ] ifFalse: [ oldName ]) do: [ :value |
        | failure |
        failure := oldName isNil
            ifTrue: [ grouping addGroup: value ]
            ifFalse: [ grouping renameGroup: oldName to: value ].
        failure isNil ifTrue: [ onSuccess value: value ].
        self organizationEdited: failure ]'.

BrowserWindow compile: 'moveItem: item in: grouping from: current prompt: prompt selecting: onSuccess
    self hideCreation.
    organizationForm move: prompt choices: grouping names selected: current do: [ :value |
        | failure |
        failure := grouping move: item to: value.
        failure isNil ifTrue: [ onSuccess value: value ].
        self organizationEdited: failure ]'.

BrowserWindow compile: 'organizationEdited: failure
    | outcome |
    failure notNil ifTrue: [
        outcome := Array new: 2.
        outcome at: 1 put: false; at: 2 put: failure.
        ^ self result: outcome ].
    organizationForm cancel.
    self refreshTools.
    Desktop windows do: [ :window |
        ((window == self) not and: [ window respondsTo: #refreshTools ]) ifTrue: [ window refreshTools ] ].
    self result: (ToolVM success: ''Organization updated.'')'.

BrowserWindow compile: 'newCategory
    self editGroupIn: SystemOrganization classCategories named: nil prompt: ''New Class Category'' selecting: [ :value |
        self chooseCategory: value ]'.

BrowserWindow compile: 'renameCategory
    category = ''All'' ifTrue: [ ^ self ].
    self editGroupIn: SystemOrganization classCategories named: category prompt: ''Rename Class Category'' selecting: [ :value |
        self chooseCategory: value ]'.

BrowserWindow compile: 'moveClass
    | selected |
    className isNil ifTrue: [ ^ self ].
    selected := className.
    self moveItem: selected in: SystemOrganization classCategories from: (SystemOrganization categoryOf: selected)
        prompt: ''Move Class '' , selected selecting: [ :value |
            className = selected ifTrue: [ self chooseCategory: value ] ]'.

BrowserWindow compile: 'newProtocol
    | target |
    target := self selectedClass.
    target isNil ifTrue: [ ^ self ].
    self editGroupIn: (SystemOrganization protocolsOf: target) named: nil prompt: ''New Protocol in '' , className selecting: [ :value |
        target == self selectedClass ifTrue: [ self chooseProtocol: value ] ]'.

BrowserWindow compile: 'renameProtocol
    | target |
    target := self selectedClass.
    (target isNil or: [ protocolName = ''All'' ]) ifTrue: [ ^ self ].
    self editGroupIn: (SystemOrganization protocolsOf: target) named: protocolName prompt: ''Rename Method Protocol'' selecting: [ :value |
        target == self selectedClass ifTrue: [ self chooseProtocol: value ] ]'.

BrowserWindow compile: 'moveMethod
    | target selected |
    target := self selectedClass.
    (target isNil or: [ selector isNil ]) ifTrue: [ ^ self ].
    selected := selector.
    self moveItem: selected in: (SystemOrganization protocolsOf: target) from: (self protocolOf: selected in: target)
        prompt: ''Move Method '' , selected selecting: [ :value |
            (target == self selectedClass and: [ selector = selected ]) ifTrue: [ self chooseProtocol: value ] ]'.

DevelopmentWindow subclass: #TranscriptWindow instanceVariableNames: ''.

TranscriptWindow compile: 'initialize
    | root toolbar output scroll |
    super initialize.
    self kind: #transcript.
    self title: ''Transcript''.
    toolbar := UIRow new padding: 12; yourself.
    toolbar add: (self heading: ''Transcript''); add: UISpacer new.
    toolbar add: (UIButton new title: ''Clear''; onClickSend: #clear to: TranscriptBuffer; yourself).
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
