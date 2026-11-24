Object subclass: #ToolServices instanceVariableNames: ''.

Model subclass: #TranscriptModel instanceVariableNames: 'contents'.

TranscriptModel compile: 'initialize
    super initialize.
    contents := '''''.

TranscriptModel compile: 'text
    contents size = 0 ifTrue: [ ^ ''Transcript show: ''''Hello''''; cr.'' ].
    ^ contents'.

TranscriptModel compile: 'append: aString
    | addition |
    addition := aString suffixFittingUTF8: 65536.
    contents := (contents suffixFittingUTF8: 65536 - addition utf8Size) , addition.
    self changed: #text'.

TranscriptModel compile: 'clear
    contents := ''''.
    self changed: #text'.

UIWindow subclass: #DevelopmentWindow instanceVariableNames: 'resultLabel resultPreview resultToggle resultScroll resultPanel'.

DevelopmentWindow compile: 'heading: aString
    ^ UILabel new text: aString; role: #heading; yourself'.

DevelopmentWindow compile: 'caption: aString
    ^ UILabel new text: aString; role: #caption; yourself'.

DevelopmentWindow compile: 'resultPane
    | bar |
    resultToggle := UIButton new identifier: ''toolResultToggle''; onClickSend: #toggleResult to: self; yourself.
    resultPreview := UILabel new yourself.
    resultLabel := UILabel new identifier: ''evaluationResult''; yourself.
    resultScroll := UIScroll new padding: 8; heightFrom: 68 to: 112; add: resultLabel; yourself.
    bar := UIRow new role: #compactBar; add: resultToggle; add: resultPreview; yourself.
    resultPanel := UIColumn new spacing: 0; visible: false;
        add: UIDivider new; add: bar; add: resultScroll; yourself.
    self resultExpanded: false.
    ^ resultPanel'.

DevelopmentWindow compile: 'toggleResult
    self resultExpanded: resultScroll visible not'.

DevelopmentWindow compile: 'resultExpanded: expanded
    resultScroll visible: expanded.
    resultPreview visible: expanded not.
    resultToggle role: (expanded ifTrue: [ #disclosureOpen ] ifFalse: [ #disclosureClosed ])'.

DevelopmentWindow compile: 'result: outcome
    | success value |
    success := outcome at: 1.
    value := (outcome at: 2) suffixFittingUTF8: 65536.
    (resultLabel text ~= value or: [ resultToggle title ~= (success ifTrue: [ ''Result'' ] ifFalse: [ ''Error'' ]) ])
        ifTrue: [ self resultExpanded: false ].
    resultToggle title: (success ifTrue: [ ''Result'' ] ifFalse: [ ''Error'' ]).
    resultLabel role: (success ifTrue: [ #code ] ifFalse: [ #error ]); text: value.
    resultPreview role: (success ifTrue: [ #codePreview ] ifFalse: [ #errorPreview ]); text: value.
    resultPanel visible: value size > 0'.

DevelopmentWindow subclass: #WorkspaceWindow instanceVariableNames: 'editor'.

WorkspaceWindow compile: 'initialize
    | root bar doIt |
    super initialize.
    self kind: #workspace.
    self title: ''Workspace''.
    self resizeWidth: 720 height: 600.
    editor := UICodeEditor new identifier: ''workspaceEditor''; label: ''Smalltalk Workspace''; role: #source; yourself.
    editor onChangeSend: #text: to: self.
    editor contextMenu: self editorMenu.
    doIt := (self selectionButton: ''Do it'' command: #doIt action: #doIt:)
        identifier: ''executeButton''; role: #primary; shortcutHint: ''⌘D''; yourself.
    bar := UIRow new role: #windowToolbar; spacing: 5; add: doIt; add: self actionsMenu; yourself.
    root := UIColumn new spacing: 0; add: bar; add: self examplesMenu; add: editor; add: self resultPane; yourself.
    self content: root'.

WorkspaceWindow compile: 'text: aString
    super text: aString.
    editor notNil ifTrue: [ editor text: aString ]'.

WorkspaceWindow compile: 'sourceForSelection: selected
    ^ selected size = 0 ifTrue: [ self text ] ifFalse: [ selected ]'.

WorkspaceWindow compile: 'doIt: selected
    ^ self execute: selected printing: false'.

WorkspaceWindow compile: 'printIt: selected
    ^ self execute: selected printing: true'.

WorkspaceWindow compile: 'inspect: selected
    | outcome |
    outcome := ToolVM inspectSource: (self sourceForSelection: selected).
    self result: outcome.
    ^ outcome at: 2'.

WorkspaceWindow compile: 'execute: selected printing: aBoolean
    | outcome |
    outcome := ToolVM evaluateSource: (self sourceForSelection: selected).
    self result: outcome.
    (aBoolean and: [ outcome at: 1 ]) ifTrue: [ Transcript show: ''→ '' , (outcome at: 2); cr ].
    ^ outcome at: 2'.

WorkspaceWindow compile: 'selectionButton: aTitle command: aCommand action: aSelector
    ^ UIButton new
        title: aTitle;
        command: aCommand;
        selectionFrom: editor action: [ :selected | self perform: aSelector with: selected ];
        yourself'.

WorkspaceWindow compile: 'editorMenu
    | menu |
    menu := UIMenu new title: ''Workspace''; yourself.
    menu add: (self selectionButton: ''Do it'' command: #doIt action: #doIt:).
    menu add: (self selectionButton: ''Print it'' command: #printIt action: #printIt:).
    menu add: (self selectionButton: ''Inspect it'' command: #inspectIt action: #inspect:).
    menu add: (self selectionButton: ''Debug it'' command: #debugIt action: #debugIt:).
    ^ menu'.

WorkspaceWindow compile: 'actionsMenu
    | menu |
    menu := UIMenu new title: ''Workspace actions''; identifier: ''workspaceActions''; role: #moreMenu; yourself.
    menu add: ((self selectionButton: ''Print it'' command: #printIt action: #printIt:) identifier: ''workspaceAction-printIt''; yourself).
    menu add: ((self selectionButton: ''Inspect it'' command: #inspectIt action: #inspect:) identifier: ''workspaceAction-inspectIt''; yourself).
    menu add: ((self selectionButton: ''Debug it'' command: #debugIt action: #debugIt:) identifier: ''workspaceAction-debugIt''; yourself).
    ^ menu'.

WorkspaceWindow compile: 'debugIt: selected
    ToolVM requestDebugSource: (self sourceForSelection: selected) for: self'.

WorkspaceWindow compile: 'examplesMenu
    | menu |
    menu := UIMenu new title: ''Examples''; role: #applicationMenu; yourself.
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

DevelopmentWindow subclass: #BrowserWindow instanceVariableNames: 'categoryList classList protocolList methodList queryField editor category className protocolName selector originalSource header hint accept versions versionMenu organizationForm renameCategoryItem moveClassItem newProtocolItem renameProtocolItem moveMethodItem methodSide instanceSideButton classSideButton otherSideState editingDefinition definitionButton bytecodeToggle bytecodeView'.

BrowserWindow compile: 'initialize
    | navigation panes source actions toolbar categoryMenu protocolMenu sideBar newMethod |
    super initialize.
    self kind: #browser.
    self title: ''System Browser''.
    category := ''All''.
    className := ''Counter''.
    protocolName := ''All''.
    methodSide := #instance.
    editingDefinition := true.
    categoryList := self list: ''categoryList'' selecting: #chooseCategory:.
    classList := self list: ''classList'' selecting: #chooseClass:.
    protocolList := self list: ''protocolList'' selecting: #chooseProtocol:.
    methodList := self list: ''methodList'' selecting: #chooseMethod:.
    queryField := UITextField new identifier: ''classFilter''; placeholder: ''Filter Classes''; widthFrom: 135 to: 220; onChangeSend: #filter: to: self; yourself.
    editor := UICodeEditor new identifier: ''methodEditor''; label: ''Method Source''; role: #source; onChangeSend: #draftChanged: to: self; yourself.
    header := self heading: ''''.
    hint := self caption: ''''.
    accept := UIButton new title: ''Accept''; identifier: ''executeButton''; role: #primary; command: #acceptMethod; onClickSend: #acceptMethod to: self; yourself.
    versions := UIButton new title: ''Versions …''; identifier: ''methodVersionsButton''; onClickSend: #showVersions to: self; yourself.
    definitionButton := UIButton new title: ''Definition''; identifier: ''classDefinition''; onClickSend: #showDefinition to: self; yourself.

    newMethod := UIButton new title: ''New Method''; identifier: ''newMethod''; onClickSend: #newMethod to: self; yourself.

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

    panes := UISplit new identifier: ''browserNavigation''; yourself.
    panes add: (self pane: ''Class Categories'' list: categoryList action: categoryMenu).
    panes add: (self pane: ''Classes'' list: classList action: definitionButton).
    panes add: (self pane: ''Protocols'' list: protocolList action: protocolMenu).
    panes add: (self pane: ''Methods'' list: methodList action: newMethod).

    instanceSideButton := UIButton new title: ''Instance''; identifier: ''instanceMethodSide''; onClickSend: #showInstanceMethods to: self; yourself.
    classSideButton := UIButton new title: ''Class''; identifier: ''classMethodSide''; onClickSend: #showClassMethods to: self; yourself.
    sideBar := UIRow new role: #segmented; add: instanceSideButton; add: classSideButton; yourself.
    actions := UIRow new role: #compactBar; add: queryField; add: UISpacer new; add: sideBar; yourself.
    navigation := UIColumn new spacing: 0; heightFrom: 140 to: 255;
        add: actions; add: UIDivider new; add: panes; yourself.

    versionMenu := UIMenu new title: ''Method Actions''; identifier: ''methodActions''; role: #paneMenu; add: versions; yourself.
    toolbar := UIRow new role: #compactBar; add: header; add: hint; add: UISpacer new; add: versionMenu; add: accept; yourself.
    organizationForm := BrowserOrganizationForm new.
    bytecodeToggle := UIButton new title: ''Bytecode''; identifier: ''methodBytecodeToggle'';
        onClickSend: #toggleBytecode to: self; yourself.
    bytecodeView := UICodeEditor new identifier: ''bytecodeEditor''; label: ''Method Bytecode''; readOnly: true;
        heightFrom: 64 to: 184; visible: false; yourself.
    source := UIColumn new spacing: 0; heightFrom: 145 to: nil; add: toolbar; add: UIDivider new;
        add: organizationForm; add: editor; add: bytecodeToggle; add: bytecodeView; add: self resultPane; yourself.
    self content: (UISplit new role: #vertical; add: navigation; add: source; yourself).
    self showDefinition.
    self refreshTools'.

BrowserWindow compile: 'toggleBytecode
    bytecodeView visible: bytecodeView visible not.
    self refreshBytecode'.

BrowserWindow compile: 'refreshBytecode
    bytecodeToggle enabled: selector notNil.
    selector isNil ifTrue: [ bytecodeView visible: false ].
    bytecodeToggle role: (bytecodeView visible ifTrue: [ #disclosureOpen ] ifFalse: [ #disclosureClosed ]).
    bytecodeView visible ifTrue: [
        bytecodeView text: (self primitiveSelected
            ifTrue: [ ''This VM primitive has no bytecode.'' ]
            ifFalse: [ ToolVM bytecodeOf: selector in: self selectedClass side: methodSide ]) ]'.

BrowserWindow compile: 'result: outcome
    super result: outcome.
    ((outcome at: 1) and: [ (outcome at: 2) = header text ]) ifTrue: [ resultPanel visible: false ]'.

BrowserWindow compile: 'list: identifier selecting: message
    ^ UIList new identifier: identifier; role: #pane; onSelectSend: message to: self; yourself'.

BrowserWindow compile: 'pane: aTitle list: aList action: anAction
    | labelBar |
    labelBar := UIRow new role: #paneHeader; add: (self caption: aTitle); add: UISpacer new; add: anAction; yourself.
    ^ UIColumn new spacing: 0; widthFrom: 142 to: nil; add: labelBar; add: aList; yourself'.

BrowserWindow compile: 'organizationItem: aTitle id: identifier send: message
    ^ UIButton new title: aTitle; identifier: identifier; onClickSend: message to: self; yourself'.

BrowserWindow compile: 'selectedClass
    className isNil ifTrue: [ ^ nil ].
    ^ ToolVM classNamed: className'.

BrowserWindow compile: 'primitiveSelected
    selector isNil ifTrue: [ ^ false ].
    ^ ToolVM isPrimitiveAt: selector in: self selectedClass side: methodSide'.

BrowserWindow compile: 'filter: aString
    queryField text: aString.
    self refreshClasses'.

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
    ^ (SystemOrganization protocolsOf: target side: methodSide) groupOf: name default: ''Unclassified'''.

BrowserWindow compile: 'refreshMethods
    | target methods protocols names |
    target := self selectedClass.
    target isNil ifTrue: [
        protocolName := ''All''.
        protocolList items: #(''All''); selection: protocolName.
        methodList items: #(); selection: nil.
        ^ self ].
    methods := ToolVM methodNamesFor: target side: methodSide.
    protocols := methods collect: [ :each | self protocolOf: each in: target ].
    names := (SystemOrganization protocolsOf: target side: methodSide) namesWith: protocols.
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
    target notNil ifTrue: [
        editingDefinition
            ifTrue: [ textValue := ToolVM definitionOf: target ]
            ifFalse: [ selector notNil ifTrue: [ textValue := ToolVM methodSourceAt: selector in: target side: methodSide ] ].
        (textValue notNil and: [ textValue ~= originalSource and: [ editor text = originalSource ] ]) ifTrue: [
            editor text: textValue. originalSource := textValue. self refreshEditor ] ].
    self refreshOrganizationActions.
    self refreshBytecode'.

BrowserWindow compile: 'refreshEditor
    | primitive name target |
    primitive := self primitiveSelected.
    target := self selectedClass.
    name := className isNil ifTrue: [ ''No Class Selected'' ] ifFalse: [ className ].
    (className notNil and: [ editingDefinition not and: [ methodSide = #class ] ]) ifTrue: [ name := name , '' class'' ].
    header text: (selector isNil ifTrue: [ name ] ifFalse: [ name , '' » '' , selector ]).
    hint text: (editingDefinition ifTrue: [ ''Class Definition'' ] ifFalse: [
        primitive ifTrue: [ ''VM Primitive'' ] ifFalse: [ methodSide = #class ifTrue: [ ''Class Side'' ] ifFalse: [ ''Instance Side'' ] ] ]).
    hint visible: (editingDefinition or: [ primitive ]).
    instanceSideButton role: (methodSide = #instance ifTrue: [ #primary ] ifFalse: [ #secondary ]).
    classSideButton role: (methodSide = #class ifTrue: [ #primary ] ifFalse: [ #secondary ]).
    editor label: (editingDefinition ifTrue: [ ''Class Definition'' ] ifFalse: [ ''Method Source'' ]).
    editor readOnly: (target isNil or: [ primitive or: [ editingDefinition and: [ (ToolVM canRedefine: target) not ] ] ]).
    versionMenu visible: (selector notNil and: [ primitive not ]).
    self refreshBytecode.
    self refreshOrganizationActions.
    self draftChanged: editor text'.

BrowserWindow compile: 'draftChanged: aString
    | target |
    target := self selectedClass.
    definitionButton enabled: (target notNil and: [ editingDefinition not or: [ aString ~= originalSource ] ]).
    accept enabled: (target notNil and: [ aString size > 0 and: [ editingDefinition
        ifTrue: [ (ToolVM canRedefine: target) and: [ aString ~= originalSource ] ]
        ifFalse: [ self primitiveSelected not ] ] ])'.

BrowserWindow compile: 'chooseCategory: name
    category := name isNil ifTrue: [ ''All'' ] ifFalse: [ name ].
    (className notNil and: [ (self matchesCategory: className) not ]) ifTrue: [ ^ self chooseClass: nil ].
    self refreshClasses.
    self refreshOrganizationActions'.

BrowserWindow compile: 'chooseClass: name
    className ~= name ifTrue: [ otherSideState := nil. organizationForm cancel ].
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
    name isNil ifTrue: [ ^ self showDefinition ].
    editingDefinition := false.
    selector := name.
    originalSource := ToolVM methodSourceAt: selector in: self selectedClass side: methodSide.
    originalSource isNil ifTrue: [ originalSource := '''' ].
    editor text: originalSource.
    methodList selection: selector.
    self refreshEditor'.

BrowserWindow compile: 'showDefinition
    | target |
    editingDefinition := true.
    selector := nil.
    methodList selection: nil.
    target := self selectedClass.
    originalSource := target isNil ifTrue: [ '''' ] ifFalse: [ ToolVM definitionOf: target ].
    editor text: originalSource.
    self refreshEditor'.

BrowserWindow compile: 'showInstanceMethods
    self chooseMethodSide: #instance'.

BrowserWindow compile: 'showClassMethods
    self chooseMethodSide: #class'.

BrowserWindow compile: 'chooseMethodSide: side
    | saved |
    methodSide = side ifTrue: [ ^ self ].
    organizationForm cancel.
    saved := otherSideState.
    otherSideState := Array new: 5.
    otherSideState at: 1 put: protocolName; at: 2 put: selector; at: 3 put: originalSource;
        at: 4 put: editor text; at: 5 put: editingDefinition.
    methodSide := side.
    saved isNil ifTrue: [ protocolName := ''All''. self chooseMethod: nil ] ifFalse: [
        protocolName := saved at: 1.
        selector := saved at: 2.
        originalSource := saved at: 3.
        editingDefinition := saved at: 5.
        editor text: (saved at: 4) ].
    self refreshTools.
    self refreshEditor'.

BrowserWindow compile: 'newMethod
    className isNil ifTrue: [ ^ self ].
    editingDefinition := false.
    selector := nil.
    methodList selection: nil.
    originalSource := ''''.
    editor text: ''newMethod'' , ToolVM lineBreak , ''    ^ self''.
    self refreshEditor'.

BrowserWindow compile: 'acceptMethod
    | outcome target |
    target := self selectedClass.
    (target isNil or: [ self primitiveSelected or: [ editor text size = 0 ] ]) ifTrue: [ ^ self ].
    editingDefinition ifTrue: [ ^ self acceptDefinition ].
    outcome := ToolVM compileSource: editor text in: target side: methodSide.
    (outcome at: 1) ifTrue: [
        selector := outcome at: 2.
        originalSource := editor text.
        protocolName ~= ''All'' ifTrue: [ (SystemOrganization protocolsOf: target side: methodSide) move: selector to: protocolName ].
        self refreshTools.
        self refreshEditor.
        self result: (ToolVM success: className , (methodSide = #class ifTrue: [ '' class'' ] ifFalse: [ '''' ]) , '' » '' , selector)
    ] ifFalse: [ self result: outcome ]'.

BrowserWindow compile: 'acceptDefinition
    | outcome |
    outcome := ToolVM acceptDefinition: editor text in: self selectedClass basedOn: originalSource.
    (outcome at: 1) ifTrue: [ self showDefinition. self refreshTools ].
    self result: outcome'.

BrowserWindow compile: 'showVersions
    (selector notNil and: [ self primitiveSelected not ]) ifTrue: [ ToolVM requestVersionsFor: className selector: selector side: methodSide ]'.

BrowserWindow compile: 'refreshOrganizationActions
    renameCategoryItem enabled: category ~= ''All''.
    moveClassItem enabled: className notNil.
    newProtocolItem enabled: className notNil.
    renameProtocolItem enabled: (className notNil and: [ protocolName ~= ''All'' ]).
    moveMethodItem enabled: (className notNil and: [ selector notNil ])'.

BrowserWindow compile: 'editGroupIn: grouping named: oldName prompt: prompt selecting: onSuccess
    organizationForm edit: prompt name: (oldName isNil ifTrue: [ '''' ] ifFalse: [ oldName ]) do: [ :value |
        | failure |
        failure := oldName isNil
            ifTrue: [ grouping addGroup: value ]
            ifFalse: [ grouping renameGroup: oldName to: value ].
        failure isNil ifTrue: [ onSuccess value: value ].
        self organizationEdited: failure ]'.

BrowserWindow compile: 'moveItem: item in: grouping from: current prompt: prompt selecting: onSuccess
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
    self editGroupIn: (SystemOrganization protocolsOf: target side: methodSide) named: nil prompt: ''New Protocol in '' , className selecting: [ :value |
        target == self selectedClass ifTrue: [ self chooseProtocol: value ] ]'.

BrowserWindow compile: 'renameProtocol
    | target |
    target := self selectedClass.
    (target isNil or: [ protocolName = ''All'' ]) ifTrue: [ ^ self ].
    self editGroupIn: (SystemOrganization protocolsOf: target side: methodSide) named: protocolName prompt: ''Rename Method Protocol'' selecting: [ :value |
        target == self selectedClass ifTrue: [ self chooseProtocol: value ] ]'.

BrowserWindow compile: 'moveMethod
    | target selected |
    target := self selectedClass.
    (target isNil or: [ selector isNil ]) ifTrue: [ ^ self ].
    selected := selector.
    self moveItem: selected in: (SystemOrganization protocolsOf: target side: methodSide) from: (self protocolOf: selected in: target)
        prompt: ''Move Method '' , selected selecting: [ :value |
            (target == self selectedClass and: [ selector = selected ]) ifTrue: [ self chooseProtocol: value ] ]'.

DevelopmentWindow subclass: #TranscriptWindow instanceVariableNames: ''.

TranscriptWindow compile: 'initialize
    | output scroll menu |
    super initialize.
    self kind: #transcript.
    self title: ''Transcript''.
    output := UILabel new identifier: ''transcriptOutput''; role: #code; yourself.
    output bind: #text to: TranscriptBuffer aspect: #text.
    menu := UIMenu new add: (UIButton new title: ''Clear Transcript''; identifier: ''clearTranscript'';
        command: #clearTranscript; onClickSend: #clear to: TranscriptBuffer; yourself); yourself.
    scroll := UIScroll new role: #followEnd; padding: 12; contextMenu: menu; add: output; yourself.
    self content: scroll'.

Transcript compile: 'show: value
    | text |
    text := value class == String ifTrue: [ value ] ifFalse: [ value printString ].
    self record: text.
    TranscriptBuffer append: text'.

Transcript compile: 'cr
    self show: ToolVM lineBreak'.

Transcript compile: 'clear
    TranscriptBuffer clear'.
