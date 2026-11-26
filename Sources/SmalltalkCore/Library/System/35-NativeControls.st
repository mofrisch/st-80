UITextField subclass: #UICodeEditor instanceVariableNames: 'readOnly contextMenu lineNumbers syntaxHighlighting undoEnabled editingMenu'.

UICodeEditor compile: 'initialize
    super initialize.
    readOnly := false.
    lineNumbers := false.
    syntaxHighlighting := false.
    undoEnabled := true.
    editingMenu := #((#cut ''Cut'') (#copy ''Copy'') (#paste ''Paste'') (#selectAll ''Select All''))'.

UICodeEditor compile: 'readOnly: aBoolean
    readOnly := aBoolean'.

UICodeEditor compile: 'role: aSymbol
    super role: aSymbol.
    lineNumbers := aSymbol = #source.
    syntaxHighlighting := lineNumbers'.

UICodeEditor compile: 'lineNumbers: aBoolean
    lineNumbers := aBoolean'.

UICodeEditor compile: 'syntaxHighlighting: aBoolean
    syntaxHighlighting := aBoolean'.

UICodeEditor compile: 'undoEnabled: aBoolean
    undoEnabled := aBoolean'.

UICodeEditor compile: 'editingMenu: entries
    editingMenu := entries'.

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

UIList subclass: #UIHistoryList instanceVariableNames: 'entries rowIdentifierPrefix command'.

UIHistoryList compile: 'initialize
    super initialize.
    entries := #()'.

UIHistoryList compile: 'entries: rows
    entries := rows.
    self items: (rows collect: [ :each | each at: 1 ])'.

UIHistoryList compile: 'includes: key
    ^ items includes: key'.

UIHistoryList compile: 'rowIdentifierPrefix: aString
    rowIdentifierPrefix := aString'.

UIHistoryList compile: 'command: aSymbol
    command := aSymbol'.

UIElement subclass: #UISourceView instanceVariableNames: 'text line column'.

UISourceView compile: 'initialize
    super initialize.
    text := ''''.
    line := 1.
    column := 1'.

UISourceView compile: 'text: aString
    text := aString'.

UISourceView compile: 'line: aLine column: aColumn
    line := aLine.
    column := aColumn'.

UIList subclass: #UIValueTable instanceVariableNames: 'rows headings rowIdentifierPrefix command readOnly nameWidth classWidth columnSpacing horizontalPadding valueLines'.

UIValueTable compile: 'initialize
    super initialize.
    rows := #().
    headings := #(''Name'' ''Value'' ''Class'').
    rowIdentifierPrefix := ''row''.
    self nameWidth: 96 classWidth: 108;
        columnSpacing: 12 padding: 12;
        valueLines: 3'.

UIValueTable compile: 'rows: entries
    rows := entries.
    self items: (entries collect: [ :each | each at: 1 ])'.

UIValueTable compile: 'headings: labels
    headings := labels'.

UIValueTable compile: 'rowIdentifierPrefix: aString
    rowIdentifierPrefix := aString'.

UIValueTable compile: 'command: aSymbol
    command := aSymbol'.

UIValueTable compile: 'readOnly: aBoolean
    readOnly := aBoolean'.

UIValueTable compile: 'nameWidth: nameColumn classWidth: classColumn
    nameWidth := nameColumn.
    classWidth := classColumn'.

UIValueTable compile: 'columnSpacing: spacing padding: padding
    columnSpacing := spacing.
    horizontalPadding := padding'.

UIValueTable compile: 'valueLines: count
    valueLines := count'.

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
