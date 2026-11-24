UITextField subclass: #UICodeEditor instanceVariableNames: 'readOnly contextMenu'.

UICodeEditor compile: 'initialize
    super initialize.
    readOnly := false'.

UICodeEditor compile: 'readOnly: aBoolean
    readOnly := aBoolean'.

UICodeEditor compile: 'contextMenu
    ^ contextMenu'.

UICodeEditor compile: 'contextMenu: aMenu
    contextMenu := aMenu'.

UIElement subclass: #UIList instanceVariableNames: 'items selection target selector'.

UIList compile: 'initialize
    super initialize.
    items := #().
    selection := nil'.

UIList compile: 'items: values
    items := values'.

UIList compile: 'selection: value
    selection := value'.

UIList compile: 'onSelectSend: message to: receiver
    target := receiver.
    selector := message'.

UIList compile: 'select: value
    (value isNil or: [ items includes: value ]) ifFalse: [ ^ self ].
    selection := value.
    target notNil ifTrue: [ ^ target perform: selector with: value ]'.

UIContainer subclass: #UISplit instanceVariableNames: ''.

UIContainer subclass: #UIScroll instanceVariableNames: 'contextMenu'.

UIScroll compile: 'contextMenu: aMenu
    contextMenu := aMenu'.

UIContainer subclass: #UIMenu instanceVariableNames: 'title'.

UIMenu compile: 'initialize
    super initialize.
    title := ''Menu'''.

UIMenu compile: 'title: aString
    title := aString'.

UIElement subclass: #UIDivider instanceVariableNames: ''.
