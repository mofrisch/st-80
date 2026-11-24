"An inspector is session state. The VM keeps its model reachable while the window is open."

Object subclass: #InspectorModel instanceVariableNames: 'levels depth'.

InspectorModel compile: 'openOn: anObject
    levels := Array new: 64.
    depth := 1.
    levels at: depth put: (self levelFor: anObject named: (ToolVM inspectionClassOf: anObject)).
    ^ self refresh'.

InspectorModel compile: 'levelFor: anObject named: aString
    | level |
    level := Array new: 3.
    level at: 1 put: anObject; at: 2 put: aString; at: 3 put: 0.
    ^ level'.

InspectorModel compile: 'currentLevel
    ^ levels at: depth'.

InspectorModel compile: 'dropTo: index
    [ depth > index ] whileTrue: [
        levels at: depth put: nil.
        depth := depth - 1 ]'.

InspectorModel compile: 'back
    depth > 1 ifTrue: [ self dropTo: depth - 1 ].
    ^ self refresh'.

InspectorModel compile: 'page: page
    self currentLevel at: 3 put: page.
    ^ self refresh'.

InspectorModel compile: 'changePageBy: offset
    ^ self page: (self currentLevel at: 3) + offset'.

InspectorModel compile: 'follow: key
    | member value index nextLevel |
    member := ToolVM inspectionMember: key in: (self currentLevel at: 1).
    member isNil ifTrue: [ ^ self refresh ].
    value := member at: 1.
    index := depth.
    [ index > 0 ] whileTrue: [
        (ToolVM inspectionReference: value sameAs: ((levels at: index) at: 1))
            ifTrue: [ self dropTo: index. ^ self refresh ].
        index := index - 1 ].
    depth < levels size ifTrue: [
        nextLevel := self levelFor: value named: (member at: 2).
        levels at: depth + 1 put: nextLevel.
        depth := depth + 1 ].
    ^ self refresh'.

InspectorModel compile: 'pageSize
    ^ 100'.

InspectorModel compile: 'refresh
    | level object count pageSize pageCount page start path result |
    level := self currentLevel.
    object := level at: 1.
    count := ToolVM inspectionSizeOf: object.
    pageSize := self pageSize.
    pageCount := (((count + pageSize - 1) // pageSize) max: 1).
    page := (level at: 3) clampFrom: 0 to: pageCount - 1.
    level at: 3 put: page.
    start := page * pageSize + 1.
    path := Array new: depth.
    1 to: depth do: [ :index | path at: index put: ((levels at: index) at: 2) ].
    result := Array new: 7.
    result at: 1 put: (ToolVM inspectionClassOf: object);
        at: 2 put: (ToolVM inspectionSummaryOf: object);
        at: 3 put: (ToolVM inspectionRowsOf: object from: start to: ((start + pageSize - 1) min: count));
        at: 4 put: path;
        at: 5 put: page;
        at: 6 put: pageCount;
        at: 7 put: count.
    ^ result'.

"The inspector describes its controls from an immutable snapshot of VM data."

UIWindow subclass: #ObjectInspectorWindow instanceVariableNames: 'identifier'.

ObjectInspectorWindow compile: 'initialize
    super initialize.
    identifier := ''objectInspector''.
    self title: ''Object Inspector'';
        minimumWidth: 380 height: 250;
        resizeWidth: 540 height: 440'.

ObjectInspectorWindow compileClass: 'action: command row: row on: model members: members
    | index |
    command = #inspectBack ifTrue: [ ^ model back ].
    command = #inspectRefresh ifTrue: [ ^ model refresh ].
    command = #inspectPreviousPage ifTrue: [ ^ model changePageBy: -1 ].
    command = #inspectNextPage ifTrue: [ ^ model changePageBy: 1 ].
    (command = #inspectMember and: [ row notNil ]) ifFalse: [ ^ nil ].
    index := row asIntegerOrNil.
    (index isNil or: [ index < 0 or: [ index >= members size ] ]) ifTrue: [ ^ nil ].
    ^ model follow: (members at: index + 1)'.

ObjectInspectorWindow compileClass: 'fallbackFor: message
    ^ UIColumn new padding: 12;
        add: (UILabel new role: #error; text: message; yourself);
        yourself'.

Object subclass: #InspectorPresentation instanceVariableNames: ''.

InspectorPresentation compileClass: 'contentFor: className summary: preview path: path rows: rows page: page pageCount: pageCount
    | root classLabel title summary table |
    root := UIColumn new spacing: 0; yourself.
    classLabel := UILabel new role: #heading; identifier: ''inspectorClass''; text: className; yourself.
    title := UIColumn new spacing: 2; add: classLabel; yourself.
    path size > 1 ifTrue: [
        title add: (UILabel new role: #breadcrumb; text: (self breadcrumbFor: path); yourself) ].
    root add: (self navigation: title canGoBack: path size > 1).
    summary := UILabel new role: #code; identifier: ''inspectorSummary''; text: preview; yourself.
    rows isEmpty
        ifTrue: [ root add: (UIScroll new padding: 12; add: summary; yourself) ]
        ifFalse: [
            table := UIValueTable new identifier: ''inspectorMembers''; rowIdentifierPrefix: ''inspectorRow'';
                command: #inspectMember; headings: #(''Name'' ''Value'' ''Class''); rows: rows; yourself.
            root add: (UIColumn new padding: 12; add: summary; yourself); add: UIDivider new; add: table ].
    pageCount > 1 ifTrue: [
        root add: UIDivider new; add: (self pagination: page count: pageCount) ].
    ^ root'.

InspectorPresentation compileClass: 'navigation: title canGoBack: canGoBack
    | back refresh |
    back := UIButton new title: ''Back''; icon: ''chevron.left''; identifier: ''inspectorBack'';
        command: #inspectBack; enabled: canGoBack; yourself.
    refresh := UIButton new title: ''Refresh''; icon: ''arrow.clockwise''; identifier: ''inspectorRefresh'';
        command: #inspectRefresh; yourself.
    ^ UIRow new role: #compactBar; add: back; add: title; add: UISpacer new; add: refresh; yourself'.

InspectorPresentation compileClass: 'pagination: page count: pageCount
    | previous next label |
    previous := UIButton new title: ''Previous''; identifier: ''inspectorPreviousPage'';
        command: #inspectPreviousPage; enabled: page > 0; yourself.
    next := UIButton new title: ''Next''; identifier: ''inspectorNextPage'';
        command: #inspectNextPage; enabled: page + 1 < pageCount; yourself.
    label := UILabel new role: #pageNumber; identifier: ''inspectorPage'';
        text: (page + 1) printString , '' of '' , pageCount printString; yourself.
    ^ UIRow new role: #compactBar; add: previous; add: UISpacer new; add: label; add: UISpacer new; add: next; yourself'.

InspectorPresentation compileClass: 'breadcrumbFor: path
    | title |
    title := path at: 1.
    2 to: path size do: [ :index | title := title , '' › '' , (path at: index) ].
    ^ title'.
