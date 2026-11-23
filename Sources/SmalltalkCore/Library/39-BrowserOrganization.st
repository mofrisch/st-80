"Class categories and per-class method protocols live in the image."

Array compile: 'copyWith: element
    | result |
    result := Array new: self size + 1.
    1 to: self size do: [ :index | result at: index put: (self at: index) ].
    result at: result size put: element.
    ^ result'.

Object subclass: #BrowserGroup instanceVariableNames: 'name defaultName items'.

BrowserGroup compile: 'initialize items := #()'.

BrowserGroup compile: 'name ^ name'.

BrowserGroup compile: 'name: aString name := aString'.

BrowserGroup compile: 'defaultName ^ defaultName'.

BrowserGroup compile: 'defaultName: aString defaultName := aString'.

BrowserGroup compile: 'isDeclared ^ name ~= defaultName'.

BrowserGroup compile: 'includes: item ^ items includes: item'.

BrowserGroup compile: 'items ^ items'.

BrowserGroup compile: 'items: values items := values'.

Object subclass: #BrowserGrouping instanceVariableNames: 'groups'.

BrowserGrouping compile: 'initialize groups := #()'.

BrowserGrouping compile: 'defineDefaults: names
    names do: [ :name |
        groups := groups copyWith: (BrowserGroup new name: name; defaultName: name; yourself) ]'.

BrowserGrouping compile: 'names ^ groups collect: [ :group | group name ]'.

BrowserGrouping compile: 'namesWith: populated
    ^ (groups select: [ :group | group isDeclared or: [ populated includes: group name ] ])
        collect: [ :group | group name ]'.

BrowserGrouping compile: 'groupNamed: name
    groups do: [ :group | group name = name ifTrue: [ ^ group ] ].
    ^ nil'.

BrowserGrouping compile: 'explicitGroupOf: item
    groups do: [ :group | (group includes: item) ifTrue: [ ^ group ] ].
    ^ nil'.

BrowserGrouping compile: 'groupOf: item default: defaultName
    | assigned |
    assigned := self explicitGroupOf: item.
    assigned notNil ifTrue: [ ^ assigned name ].
    groups do: [ :group | group defaultName = defaultName ifTrue: [ ^ group name ] ].
    ^ nil'.

BrowserGrouping compile: 'nameError: name
    (name class == String and: [ name utf8Size <= 4096 ]) ifFalse: [ ^ ''Enter a name of at most 4,096 bytes.'' ].
    (name characters select: [ :character | character isWhitespace not ]) isEmpty
        ifTrue: [ ^ ''Enter a name.'' ].
    (name = ''All'' or: [ (self groupNamed: name) notNil ]) ifTrue: [ ^ ''That name is already in use.'' ].
    ^ nil'.

BrowserGrouping compile: 'addGroup: name
    | failure |
    failure := self nameError: name.
    failure notNil ifTrue: [ ^ failure ].
    groups size >= 1023 ifTrue: [ ^ ''The list already contains the maximum number of groups.'' ].
    groups := groups copyWith: (BrowserGroup new name: name; yourself).
    ^ nil'.

BrowserGrouping compile: 'renameGroup: oldName to: newName
    | group failure |
    group := self groupNamed: oldName.
    group isNil ifTrue: [ ^ ''Select a group to rename.'' ].
    oldName = newName ifTrue: [ ^ nil ].
    failure := self nameError: newName.
    failure notNil ifTrue: [ ^ failure ].
    group name: newName.
    ^ nil'.

BrowserGrouping compile: 'move: item to: name
    | target previous additions remaining |
    target := self groupNamed: name.
    target isNil ifTrue: [ ^ ''Select an existing destination.'' ].
    previous := self explicitGroupOf: item.
    previous == target ifTrue: [ ^ nil ].
    additions := target items copyWith: item.
    previous notNil ifTrue: [ remaining := previous items select: [ :each | each ~= item ] ].
    target items: additions.
    previous notNil ifTrue: [ previous items: remaining ].
    ^ nil'.

Object subclass: #BrowserOrganization instanceVariableNames: 'classCategories catalogs'.

BrowserOrganization compile: 'initialize
    classCategories := BrowserGrouping new.
    classCategories defineDefaults: #(''Kernel'' ''Compiler'' ''Interface'' ''Tools'' ''Examples'' ''User Classes'').
    catalogs := #()'.

BrowserOrganization compile: 'classCategories ^ classCategories'.

BrowserOrganization compile: 'categoryOf: name
    ^ classCategories groupOf: name default: (self defaultCategoryOf: name)'.

BrowserOrganization compile: 'defaultCategoryOf: name
    (#(''Object'' ''Class'' ''UndefinedObject'' ''Boolean'' ''True'' ''False'' ''Number'' ''Integer'' ''SmallInteger'' ''String'' ''Symbol'' ''Array'' ''BlockClosure'') includes: name) ifTrue: [ ^ ''Kernel'' ].
    (#(''STCompilerList'' ''STScanner'' ''STCompiler'') includes: name) ifTrue: [ ^ ''Compiler'' ].
    (#(''Transcript'' ''TranscriptModel'' ''ToolServices'' ''DevelopmentWindow'' ''WorkspaceWindow'' ''BrowserWindow'' ''TranscriptWindow''
       ''BrowserGroup'' ''BrowserGrouping'' ''BrowserOrganization'' ''BrowserOrganizationForm'') includes: name) ifTrue: [ ^ ''Tools'' ].
    (#(''Model'' ''Controller'' ''UIBinding'' ''SystemWindow'' ''DesktopModel'' ''DisplayScreen'' ''DesktopManager''
       ''UIElement'' ''UILabel'' ''UIButton'' ''UITextField'' ''UIContainer'' ''UIColumn'' ''UIRow'' ''UISpacer''
       ''UIWindow'' ''UICodeEditor'' ''UIList'' ''UISplit'' ''UIScroll'' ''UIMenu'' ''UIDivider'') includes: name)
        ifTrue: [ ^ ''Interface'' ].
    name = ''Counter'' ifTrue: [ ^ ''Examples'' ].
    ^ ''User Classes'''.

BrowserOrganization compile: 'protocolsOf: target
    | grouping entry |
    catalogs do: [ :each | (each at: 1) == target ifTrue: [ ^ each at: 2 ] ].
    grouping := BrowserGrouping new.
    grouping defineDefaults: #(''Initialization'' ''Unary'' ''Keyword'' ''Binary'' ''VM Primitives'').
    entry := Array new: 2.
    entry at: 1 put: target; at: 2 put: grouping.
    catalogs := catalogs copyWith: entry.
    ^ grouping'.

BrowserOrganization compile: 'defaultProtocolFor: name in: target
    (target isPrimitiveAt: name) ifTrue: [ ^ ''VM Primitives'' ].
    name = ''initialize'' ifTrue: [ ^ ''Initialization'' ].
    (name includes: '':'') ifTrue: [ ^ ''Keyword'' ].
    (name at: 1) isLetter ifTrue: [ ^ ''Unary'' ].
    ^ ''Binary'''.

UIColumn subclass: #BrowserOrganizationForm instanceVariableNames: 'heading entry destinations destination applyButton operation'.

BrowserOrganizationForm compile: 'initialize
    | buttons |
    super initialize.
    self padding: 8; spacing: 4; visible: false.
    heading := UILabel new role: #heading; yourself.
    entry := UITextField new label: ''Name''; identifier: ''organizationName''; yourself.
    destinations := UIList new identifier: ''organizationDestinations''; role: #pane; heightFrom: 86 to: 110;
        onSelectSend: #chooseDestination: to: self; yourself.
    applyButton := UIButton new title: ''Apply''; identifier: ''applyOrganizationEdit''; role: #primary;
        onClickSend: #apply to: self; yourself.
    buttons := UIRow new add: (UIButton new title: ''Cancel''; identifier: ''cancelOrganizationEdit''; onClickSend: #cancel to: self; yourself);
        add: applyButton; yourself.
    self add: heading; add: entry; add: destinations; add: buttons'.

BrowserOrganizationForm compile: 'edit: prompt name: initialName do: action
    operation := action.
    heading text: prompt.
    entry text: initialName; visible: true.
    destinations visible: false.
    applyButton enabled: true.
    self visible: true'.

BrowserOrganizationForm compile: 'move: prompt choices: names selected: current do: action
    operation := action.
    heading text: prompt.
    entry visible: false.
    destinations items: names; selection: current; visible: true.
    self chooseDestination: current.
    self visible: true'.

BrowserOrganizationForm compile: 'chooseDestination: value
    destination := value.
    applyButton enabled: value notNil'.

BrowserOrganizationForm compile: 'apply
    operation value: (entry visible ifTrue: [ entry text ] ifFalse: [ destination ])'.

BrowserOrganizationForm compile: 'cancel
    self visible: false.
    operation := nil'.
