"Class categories and per-class method protocols live in the image."

Array compile: 'copyWith: element
    | result |
    result := Array new: self size + 1.
    1 to: self size do: [ :index | result at: index put: (self at: index) ].
    result at: result size put: element.
    ^ result'.

Object subclass: #BrowserGroup instanceVariableNames: 'name defaultName items'.

BrowserGroup compile: 'initialize
    items := #()'.

BrowserGroup compile: 'name
    ^ name'.

BrowserGroup compile: 'name: aString
    name := aString'.

BrowserGroup compile: 'defaultName
    ^ defaultName'.

BrowserGroup compile: 'defaultName: aString
    defaultName := aString'.

BrowserGroup compile: 'isDeclared
    ^ name ~= defaultName'.

BrowserGroup compile: 'includes: item
    ^ items includes: item'.

BrowserGroup compile: 'items
    ^ items'.

BrowserGroup compile: 'items: values
    items := values'.

Object subclass: #BrowserGrouping instanceVariableNames: 'groups'.

BrowserGrouping compile: 'initialize
    groups := #()'.

BrowserGrouping compile: 'defineDefaults: names
    names do: [ :name |
        (groups anySatisfy: [ :group | group defaultName = name or: [ group name = name ] ])
            ifFalse: [ groups := groups copyWith: (BrowserGroup new name: name; defaultName: name; yourself) ] ]'.

BrowserGrouping compile: 'defineGroup: name items: selectors
    groups := groups copyWith: (BrowserGroup new name: name; items: selectors; yourself)'.

BrowserGrouping compile: 'names
    ^ groups collect: [ :group | group name ]'.

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

Object subclass: #BrowserOrganization instanceVariableNames: 'classCategories catalogs systemProtocols'.

BrowserOrganization compile: 'initialize
    | defaults |
    defaults := self class shippedClassCategories collect: [ :entry | entry at: 1 ].
    classCategories := BrowserGrouping new.
    classCategories defineDefaults: (defaults copyWith: ''User Classes'').
    systemProtocols := self shippedProtocols.
    catalogs := #()'.

BrowserOrganization compileClass: 'shippedClassCategories
    ^ #(
        (''Kernel'' (''Object'' ''Class'' ''Metaclass'' ''UndefinedObject'' ''Boolean'' ''True'' ''False''
            ''Number'' ''BlockClosure'' ''FailedMessage''))
        (''Numbers'' (''Integer'' ''SmallInteger'' ''LargeInteger'' ''Fraction'' ''ScaledDecimal'' ''Float''))
        (''Exceptions'' (''Exception'' ''Error'' ''ExceptionSet'' ''MessageNotUnderstood'' ''ZeroDivide''))
        (''Collections & Text'' (''Collection'' ''SequenceableCollection'' ''Array'' ''ByteArray'' ''Interval''
            ''OrderedCollection'' ''SortedCollection'' ''UnorderedCollection'' ''Bag'' ''Set''
            ''Dictionary'' ''IdentityDictionary'' ''String'' ''Character'' ''Symbol''
            ''CollectionStream'' ''ReadStream'' ''WriteStream'' ''ReadWriteStream''))
        (''Compiler'' (''STCompilerList'' ''STScanner'' ''STCompiler''))
        (''MVC'' (''Model'' ''Controller'' ''UIBinding''))
        (''Desktop'' (''SystemWindow'' ''DesktopModel'' ''DisplayScreen'' ''DesktopManager'' ''UIWindow''))
        (''Interface'' (''UIElement'' ''UILabel'' ''UIButton'' ''UITextField'' ''UIContainer''
            ''UIColumn'' ''UIRow'' ''UISpacer'' ''UIList'' ''UIHistoryList'' ''UIValueTable''
            ''UISplit'' ''UIVerticalSplit'' ''UIScroll'' ''UIMenu'' ''UIDivider''))
        (''Source Editing'' (''STSourceScanner'' ''UICodeEditor'' ''UISourceView''))
        (''Browser'' (''BrowserGroup'' ''BrowserGrouping'' ''BrowserOrganization''
            ''BrowserOrganizationForm'' ''BrowserNavigationPane'' ''BrowserWindow''))
        (''Tools'' (''ToolServices'' ''DevelopmentWindow'' ''WorkspaceWindow'' ''Transcript''
            ''TranscriptModel'' ''TranscriptWindow'' ''ChangesBrowser''))
        (''Debugging'' (''DebuggerWindow'' ''DebuggerPresentation'' ''InspectorModel''
            ''ObjectInspectorWindow'' ''InspectorPresentation''))
        (''Application'' (''ApplicationMenu'' ''SettingsWindow''))
        (''Recovery'' (''ToolWindowFeedback'' ''WorkspaceRecoveryCommands''))
        (''Examples'' (''Counter'' ''WorkspaceExamples''))
        (''Tests'' (''TestCase'' ''TestOutcome'' ''TestResult'' ''TestRunner''
            ''CounterTest'' ''CollectionsTest'' ''BindingTestModel'' ''UIBindingTest''
            ''ANSIDispatchProbe'' ''ANSIProbeError'' ''ANSIProbeException''
            ''ANSIClassStateProbe'' ''ANSIClassStateChild'' ''ANSISmalltalkTest'')))'.

BrowserOrganization compile: 'classCategories
    systemProtocols isNil ifTrue: [ self refreshShippedProtocols ].
    ^ classCategories'.

BrowserOrganization compile: 'categoryOf: name
    ^ classCategories groupOf: name default: (self defaultCategoryOf: name)'.

BrowserOrganization compile: 'defaultCategoryOf: name
    self class shippedClassCategories do: [ :entry |
        ((entry at: 2) includes: name) ifTrue: [ ^ entry at: 1 ] ].
    ^ ''User Classes'''.

BrowserOrganization compile: 'protocolsOf: target
    ^ self protocolsOf: target side: #instance'.

BrowserOrganization compile: 'protocolsOf: target side: methodSide
    | grouping entry |
    systemProtocols isNil ifTrue: [ self refreshShippedProtocols ].
    catalogs do: [ :each |
        ((each at: 1) == target and: [ (each at: 2) = methodSide ]) ifTrue: [ ^ each at: 3 ] ].
    grouping := BrowserGrouping new.
    self fileShippedProtocolsOf: target side: methodSide into: grouping.
    grouping defineDefaults: #(''Unclassified'').
    entry := Array new: 3.
    entry at: 1 put: target; at: 2 put: methodSide; at: 3 put: grouping.
    catalogs := catalogs copyWith: entry.
    ^ grouping'.

BrowserOrganization compile: 'refreshShippedProtocols
    classCategories defineDefaults: (self class shippedClassCategories collect: [ :entry | entry at: 1 ]).
    systemProtocols := self shippedProtocols.
    catalogs do: [ :entry |
        self fileShippedProtocolsOf: (entry at: 1) side: (entry at: 2) into: (entry at: 3) ]'.

BrowserOrganization compile: 'fileShippedProtocolsOf: target side: methodSide into: grouping
    | className definitions group additional |
    className := ToolVM classNameOf: target.
    definitions := methodSide = #instance
        ifTrue: [ systemProtocols ] ifFalse: [ self shippedClassSideProtocols ].
    definitions do: [ :definition |
        (definition at: 1) = className ifTrue: [
            (definition at: 2) do: [ :entrySpec |
                additional := (entrySpec at: 2) select: [ :selector | (grouping explicitGroupOf: selector) isNil ].
                group := grouping groupNamed: (entrySpec at: 1).
                group isNil
                    ifTrue: [ additional notEmpty ifTrue: [ grouping defineGroup: (entrySpec at: 1) items: additional ] ]
                    ifFalse: [ group items: group items , additional ] ] ] ]'.

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
