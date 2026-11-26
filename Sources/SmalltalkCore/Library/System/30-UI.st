"Native view descriptions and MVC bindings."

Object subclass: #UIElement instanceVariableNames: 'enabled mvcBindings identifier role visible minWidth maxWidth minHeight maxHeight'.

UIElement compile: 'initialize
    enabled := true.
    visible := true.
    mvcBindings := nil'.

UIElement compile: 'enabled
    ^ enabled'.

UIElement compile: 'enabled: aBoolean
    enabled := aBoolean'.

UIElement compile: 'identifier: aString
    identifier := aString'.

UIElement compile: 'role: aSymbol
    role := aSymbol'.

UIElement compile: 'visible
    ^ visible'.

UIElement compile: 'visible: aBoolean
    visible := aBoolean'.

UIElement compile: 'widthFrom: minimum to: maximum
    minWidth := minimum.
    maxWidth := maximum'.

UIElement compile: 'heightFrom: minimum to: maximum
    minHeight := minimum.
    maxHeight := maximum'.

UIElement compile: 'bindings
    mvcBindings isNil ifTrue: [ mvcBindings := Array new: 0 ].
    ^ mvcBindings'.

UIElement compile: 'bind: aProperty to: aModel aspect: anAspect
    | binding replacement |
    self unbind: aProperty.
    binding := UIBinding new.
    binding source: aModel aspect: anAspect view: self property: aProperty.
    replacement := Array new: self bindings size + 1.
    1 to: mvcBindings size do: [ :index | replacement at: index put: (mvcBindings at: index) ].
    replacement at: replacement size put: binding.
    mvcBindings := replacement.
    binding connect'.

UIElement compile: 'unbind: aProperty
    self bindings do: [ :each | each property = aProperty ifTrue: [ each disconnect ] ].
    mvcBindings := mvcBindings select: [ :each | (each property = aProperty) not ]'.

UIElement compile: 'unbindAll
    self bindings do: [ :each | each disconnect ].
    mvcBindings := nil'.

UIElement subclass: #UILabel instanceVariableNames: 'text'.

UILabel compile: 'initialize
    super initialize.
    text := '''''.

UILabel compile: 'text
    ^ text'.

UILabel compile: 'text: aString
    text := aString'.

UIElement subclass: #UIButton instanceVariableNames: 'title action command selectionAction selectionSource shortcutHint icon'.

UIButton compile: 'initialize
    super initialize.
    title := ''Button''.
    action := nil'.

UIButton compile: 'title
    ^ title'.

UIButton compile: 'shortcutHint: aString
    shortcutHint := aString'.

UIButton compile: 'title: aString
    title := aString'.

UIButton compile: 'icon: aString
    icon := aString'.

UIButton compile: 'action: aBlock
    action := aBlock'.

UIButton compile: 'click
    enabled ifFalse: [ ^ self ].
    action notNil ifTrue: [ ^ action value ]'.

UIButton compile: 'command: aSymbol
    command := aSymbol'.

UIButton compile: 'selectionFrom: anEditor action: aBlock
    selectionSource := anEditor.
    selectionAction := aBlock'.

UIButton compile: 'clickWithSelection: aString
    enabled ifFalse: [ ^ self ].
    selectionAction isNil ifTrue: [ ^ self click ].
    ^ selectionAction value: aString'.

UIButton compile: 'onClickSend: aSelector to: aController
    self action: [ aController perform: aSelector ]'.

UIElement subclass: #UITextField instanceVariableNames: 'label text placeholder mvcInputTarget mvcInputSelector'.

UITextField compile: 'initialize
    super initialize.
    label := ''''.
    text := ''''.
    placeholder := '''''.

UITextField compile: 'label
    ^ label'.

UITextField compile: 'label: aString
    label := aString'.

UITextField compile: 'text
    ^ text'.

UITextField compile: 'text: aString
    text := aString'.

UITextField compile: 'placeholder
    ^ placeholder'.

UITextField compile: 'placeholder: aString
    placeholder := aString'.

UITextField compile: 'onChangeSend: aSelector to: aController
    mvcInputTarget := aController.
    mvcInputSelector := aSelector'.

UITextField compile: 'editText: aString
    self text: aString.
    mvcInputTarget notNil ifTrue: [ ^ mvcInputTarget perform: mvcInputSelector with: aString ]'.

UIElement subclass: #UIContainer instanceVariableNames: 'children spacing padding'.

UIContainer compile: 'initialize
    super initialize.
    children := Array new: 0.
    spacing := 8.
    padding := 0'.

UIContainer compile: 'children
    ^ children'.

UIContainer compile: 'children: anArray
    children := anArray'.

UIContainer compile: 'spacing
    ^ spacing'.

UIContainer compile: 'spacing: aNumber
    spacing := aNumber'.

UIContainer compile: 'padding
    ^ padding'.

UIContainer compile: 'padding: aNumber
    padding := aNumber'.

UIContainer compile: 'add: anElement
    | replacement |
    replacement := Array new: children size + 1.
    1 to: children size do: [ :index | replacement at: index put: (children at: index) ].
    replacement at: replacement size put: anElement.
    children := replacement.
    ^ anElement'.

UIContainer compile: 'remove: anElement
    children := children select: [ :each | (each == anElement) not ]'.

UIContainer compile: 'removeAll
    children := Array new: 0'.

UIContainer subclass: #UIColumn instanceVariableNames: ''.

UIContainer subclass: #UIRow instanceVariableNames: ''.

UIElement subclass: #UISpacer instanceVariableNames: ''.

SystemWindow subclass: #UIWindow instanceVariableNames: 'content'.

UIWindow compile: 'initialize
    super initialize.
    self kind: #custom.
    title := ''Window''.
    width := 480.
    height := 320.
    content := nil'.

UIWindow compile: 'content
    ^ content'.

UIWindow compile: 'content: anElement
    content := anElement'.
