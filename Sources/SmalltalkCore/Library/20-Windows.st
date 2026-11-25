"Window models and all window-management policy. Coordinates are macOS screen points."

Model subclass: #SystemWindow instanceVariableNames: 'id kind title text x y width height minimized minimumWidth minimumHeight maximumWidth maximumHeight frameRevision stateRevision nativeMinimumWidth nativeMinimumHeight nativeMaximumWidth nativeMaximumHeight'.
SystemWindow compile: 'initialize
    super initialize.
    id := 0. kind := #workspace. title := ''Workspace''. text := ''''.
    x := 100. y := 200. width := 720. height := 600. minimized := false.
    minimumWidth := 480. minimumHeight := 320.
    maximumWidth := 8192. maximumHeight := 8192.
    frameRevision := 1. stateRevision := 1.
    nativeMinimumWidth := 480. nativeMinimumHeight := 320. nativeMaximumWidth := 8192. nativeMaximumHeight := 8192'.
SystemWindow compile: 'id
    ^ id'.
SystemWindow compile: 'id: anID
    id := anID'.
SystemWindow compile: 'kind
    ^ kind'.
SystemWindow compile: 'kind: aKind
    kind := aKind.
    minimumWidth := 320. minimumHeight := 160.
    kind = #workspace ifTrue: [ minimumWidth := 480. minimumHeight := 320 ].
    (kind = #browser or: [ kind = #changes ]) ifTrue: [ minimumWidth := 750. minimumHeight := 500 ].
    kind = #transcript ifTrue: [ minimumWidth := 400. minimumHeight := 200 ].
    frameRevision := frameRevision + 1. self changed: #kind. Desktop constrain: self'.
SystemWindow compile: 'title
    ^ title'.
SystemWindow compile: 'title: aTitle
    title := aTitle.
    self changed: #title'.
SystemWindow compile: 'text
    ^ text'.
SystemWindow compile: 'text: aString
    text := aString.
    self changed: #text'.
SystemWindow compile: 'x
    ^ x'.
SystemWindow compile: 'y
    ^ y'.
SystemWindow compile: 'width
    ^ width'.
SystemWindow compile: 'height
    ^ height'.
SystemWindow compile: 'minimumWidth
    ^ minimumWidth'.
SystemWindow compile: 'minimumHeight
    ^ minimumHeight'.
SystemWindow compile: 'maximumWidth
    ^ maximumWidth'.
SystemWindow compile: 'maximumHeight
    ^ maximumHeight'.
SystemWindow compile: 'minimumWidth: newWidth height: newHeight
    minimumWidth := newWidth clampFrom: 1 to: 8192.
    minimumHeight := newHeight clampFrom: 1 to: 8192.
    maximumWidth := maximumWidth max: minimumWidth.
    maximumHeight := maximumHeight max: minimumHeight.
    frameRevision := frameRevision + 1.
    Desktop constrain: self'.
SystemWindow compile: 'maximumWidth: newWidth height: newHeight
    maximumWidth := newWidth clampFrom: minimumWidth to: 8192.
    maximumHeight := newHeight clampFrom: minimumHeight to: 8192.
    frameRevision := frameRevision + 1.
    Desktop constrain: self'.
SystemWindow compile: 'moveToX: newX y: newY
    x := newX. y := newY. frameRevision := frameRevision + 1.
    Desktop constrain: self'.
SystemWindow compile: 'resizeWidth: newWidth height: newHeight
    width := newWidth. height := newHeight. frameRevision := frameRevision + 1.
    Desktop constrain: self'.
SystemWindow compile: 'placeX: newX y: newY width: newWidth height: newHeight
    (x = newX and: [ y = newY and: [ width = newWidth and: [ height = newHeight ] ] ]) ifFalse: [
        frameRevision := frameRevision + 1 ].
    x := newX. y := newY. width := newWidth. height := newHeight.
    self changed: #frame'.
SystemWindow compile: 'observeX: newX y: newY width: newWidth height: newHeight
    x := newX. y := newY. width := newWidth. height := newHeight.
    self changed: #frame'.
SystemWindow compile: 'frameApplied: aRevision x: newX y: newY width: newWidth height: newHeight
    frameRevision = aRevision ifTrue: [ self observeX: newX y: newY width: newWidth height: newHeight ]'.
SystemWindow compile: 'frameRevision
    ^ frameRevision'.
SystemWindow compile: 'stateRevision
    ^ stateRevision'.
SystemWindow compile: 'minimized
    ^ minimized'.
SystemWindow compile: 'minimized: aBoolean
    minimized := aBoolean.
    stateRevision := stateRevision + 1.
    self changed: #minimized'.
SystemWindow compile: 'observeMinimized: aBoolean
    minimized := aBoolean.
    self changed: #minimized'.
SystemWindow compile: 'nativeMinimumWidth: minWidth height: minHeight maximumWidth: maxWidth height: maxHeight
    nativeMinimumWidth := minWidth. nativeMinimumHeight := minHeight.
    nativeMaximumWidth := maxWidth. nativeMaximumHeight := maxHeight'.
SystemWindow compile: 'canClose
    ^ true'.
SystemWindow compile: 'open
    ^ Desktop open: self'.
SystemWindow compile: 'close
    ^ Desktop requestClose: self'.
SystemWindow compile: 'activate
    ^ Desktop activate: self'.

Model subclass: #DesktopModel instanceVariableNames: 'windows activeWindow nextID screens focusRevision'.
DesktopModel compile: 'initialize
    super initialize. windows := Array new: 0. activeWindow := nil.
    nextID := 1. screens := Array new: 0. focusRevision := 1'.
DesktopModel compile: 'windows
    ^ windows'.
DesktopModel compile: 'windows: aList
    windows := aList.
    self changed: #windows'.
DesktopModel compile: 'activeWindow
    ^ activeWindow'.
DesktopModel compile: 'activeWindow: aWindow
    activeWindow := aWindow.
    self changed: #activeWindow'.
DesktopModel compile: 'nextID
    ^ nextID'.
DesktopModel compile: 'nextID: anID
    nextID := anID'.
DesktopModel compile: 'screens
    ^ screens'.
DesktopModel compile: 'screens: aList
    screens := aList.
    self changed: #screens'.
DesktopModel compile: 'focusRevision
    ^ focusRevision'.
DesktopModel compile: 'requestFocus
    focusRevision := focusRevision + 1'.

Object subclass: #DisplayScreen instanceVariableNames: 'id x y width height'.
DisplayScreen compile: 'id
    ^ id'.
DisplayScreen compile: 'x
    ^ x'.
DisplayScreen compile: 'y
    ^ y'.
DisplayScreen compile: 'width
    ^ width'.
DisplayScreen compile: 'height
    ^ height'.
DisplayScreen compile: 'overlapWith: aWindow
    | overlapWidth overlapHeight |
    overlapWidth := (((x + width) min: (aWindow x + aWindow width)) - (x max: aWindow x)) max: 0.
    overlapHeight := (((y + height) min: (aWindow y + aWindow height)) - (y max: aWindow y)) max: 0.
    ^ overlapWidth * overlapHeight'.
DisplayScreen compile: 'distanceTo: aWindow
    | dx dy |
    dx := (x * 2 + width) - (aWindow x * 2 + aWindow width).
    dy := (y * 2 + height) - (aWindow y * 2 + aWindow height).
    ^ dx squared + dy squared'.

Controller subclass: #DesktopManager instanceVariableNames: 'changesWindow'.
DesktopManager compile: 'initialize
    super initialize.
    model := DesktopModel new'.
DesktopManager compile: 'windows
    ^ model windows'.
DesktopManager compile: 'activeWindow
    ^ model activeWindow'.
DesktopManager compile: 'nextID
    ^ model nextID'.
DesktopManager compile: 'screens
    ^ model screens'.
DesktopManager compile: 'windowAt: anID
    self windows do: [ :each | each id = anID ifTrue: [ ^ each ] ]. ^ nil'.
DesktopManager compile: 'windowOfKind: aKind
    self windows do: [ :each | each kind = aKind ifTrue: [ ^ each ] ]. ^ nil'.
DesktopManager compile: 'append: aWindow
    | replacement |
    replacement := Array new: self windows size + 1.
    1 to: self windows size do: [ :index | replacement at: index put: (self windows at: index) ].
    replacement at: replacement size put: aWindow.
    model windows: replacement. ^ aWindow'.
DesktopManager compile: 'createKind: aKind title: aTitle
    | window |
    self windows size >= 128 ifTrue: [ ^ nil ].
    window := self windowClassFor: aKind.
    window := window new.
    window kind: aKind; title: aTitle.
    (aKind = #browser or: [ aKind = #changes ]) ifTrue: [ window moveToX: 850 y: 200; resizeWidth: 850 height: 650 ].
    aKind = #transcript ifTrue: [ window moveToX: 100 y: 40; resizeWidth: 720 height: 200 ].
    self cascadeTool: window.
    ^ self open: window'.
DesktopManager compile: 'cascadeTool: aWindow
    | previous |
    previous := nil.
    self windows do: [ :each |
        (each kind = aWindow kind and: [ each minimized not ]) ifTrue: [ previous := each ] ].
    previous isNil ifTrue: [ ^ self ].
    aWindow moveToX: previous x + 24 y: previous y - 24.
    (aWindow x = previous x and: [ aWindow y = previous y ]) ifTrue: [
        aWindow moveToX: previous x - 24 y: previous y + 24 ]'.
DesktopManager compile: 'windowClassFor: aKind
    aKind = #workspace ifTrue: [ ^ WorkspaceWindow ].
    aKind = #browser ifTrue: [ ^ BrowserWindow ].
    aKind = #transcript ifTrue: [ ^ TranscriptWindow ].
    aKind = #changes ifTrue: [ ^ ChangesBrowser ].
    ^ SystemWindow'.

DesktopManager compile: 'open: aWindow
    self windows do: [ :each | each == aWindow ifTrue: [ ^ self activate: aWindow ] ].
    self windows size >= 128 ifTrue: [ ^ nil ].
    aWindow id: model nextID. model nextID: model nextID + 1.
    self constrain: aWindow.
    self append: aWindow.
    ^ self activate: aWindow'.
DesktopManager compile: 'openWorkspace
    ^ self createKind: #workspace title: ''Workspace'''.
DesktopManager compile: 'openWindow
    ^ self open: UIWindow new'.
DesktopManager compile: 'showWorkspace
    | existing | existing := nil.
    self windows do: [ :each | each kind = #workspace ifTrue: [ existing := each ] ].
    existing isNil ifTrue: [ ^ self openWorkspace ].
    ^ self activate: existing'.
DesktopManager compile: 'openBrowser
    ^ self createKind: #browser title: ''System Browser'''.
DesktopManager compile: 'openTranscript
    ^ self createKind: #transcript title: ''Transcript'''.
DesktopManager compile: 'openChanges
    | existing | existing := self windowOfKind: #changes.
    existing notNil ifTrue: [ ^ self activate: existing ].
    changesWindow notNil ifTrue: [ ^ self open: changesWindow ].
    changesWindow := self createKind: #changes title: ''Code Changes''.
    ^ changesWindow'.
DesktopManager compile: 'showChangesFor: aClass selector: aSelector side: aSide
    | window |
    window := self openChanges.
    (window respondsTo: #showClass:selector:side:) ifTrue: [
        window showClass: aClass selector: aSelector side: aSide ].
    ^ window'.
DesktopManager compile: 'catalogChanged
    self windows do: [ :window |
        (window respondsTo: #refreshTools) ifTrue: [ window refreshTools ] ]'.
DesktopManager compile: 'synchronizeChanges
    self windows do: [ :window |
        (window respondsTo: #synchronizeHistory) ifTrue: [ window synchronizeHistory ] ]'.
DesktopManager compile: 'arrangeTools
    | browser workspace output screen left bottom availableWidth availableHeight gap browserWidth rightWidth outputHeight workspaceHeight |
    browser := self windowOfKind: #browser.
    workspace := self windowOfKind: #workspace.
    output := self windowOfKind: #transcript.
    (browser isNil or: [ workspace isNil or: [ output isNil ] ]) ifTrue: [ ^ self ].
    left := 12. bottom := 12. availableWidth := 1576. availableHeight := 876. gap := 12.
    screen := self screenFor: workspace.
    screen notNil ifTrue: [
        availableWidth := ((screen width - 24) max: 1) min: 1800.
        availableHeight := ((screen height - 24) max: 1) min: 1000.
        left := screen x + ((screen width - availableWidth) // 2).
        bottom := screen y + ((screen height - availableHeight) // 2) ].
    browserWidth := (availableWidth - gap) // 2 max: browser minimumWidth.
    browserWidth := browserWidth min: ((availableWidth - gap - workspace minimumWidth) max: 1).
    rightWidth := (availableWidth - gap - browserWidth) max: 1.
    outputHeight := ((availableHeight - gap) // 3) max: output minimumHeight.
    outputHeight := outputHeight min: ((availableHeight - gap - workspace minimumHeight) max: 1).
    workspaceHeight := (availableHeight - gap - outputHeight) max: 1.
    browser placeX: left y: bottom width: browserWidth height: availableHeight.
    output placeX: left + browserWidth + gap y: bottom width: rightWidth height: outputHeight.
    workspace placeX: left + browserWidth + gap y: bottom + outputHeight + gap width: rightWidth height: workspaceHeight.
    #(#browser #workspace #transcript) do: [ :kind |
        | window | window := self windowOfKind: kind.
        window minimized: false. self constrain: window ]'.
DesktopManager compile: 'bringToFront: aWindow
    model windows: (self windows select: [ :each | (each == aWindow) not ]).
    self append: aWindow. model activeWindow: aWindow. ^ aWindow'.
DesktopManager compile: 'activate: aWindow
    aWindow minimized: false. model requestFocus. ^ self bringToFront: aWindow'.
DesktopManager compile: 'observeActivation: aWindow
    aWindow observeMinimized: false. ^ self bringToFront: aWindow'.
DesktopManager compile: 'chooseActive
    model activeWindow: nil.
    self windows do: [ :each | each minimized ifFalse: [ model activeWindow: each ] ].
    model requestFocus. ^ model activeWindow'.
DesktopManager compile: 'requestClose: aWindow
    ^ self close: aWindow'.
DesktopManager compile: 'close: aWindow
    aWindow canClose ifFalse: [ ^ false ].
    model windows: (self windows select: [ :each | (each == aWindow) not ]).
    model activeWindow == aWindow ifTrue: [ self chooseActive ]. ^ aWindow'.
DesktopManager compile: 'minimize: aWindow
    aWindow minimized: true.
    model activeWindow == aWindow ifTrue: [ self chooseActive ]. ^ aWindow'.
DesktopManager compile: 'observeMinimized: aWindow value: aBoolean
    aWindow observeMinimized: aBoolean.
    (aBoolean and: [ model activeWindow == aWindow ]) ifTrue: [ self chooseActive ]. ^ aWindow'.
DesktopManager compile: 'screenFor: aWindow
    | best bestArea bestDistance area distance |
    best := nil. bestArea := -1. bestDistance := 0.
    model screens do: [ :screen |
        area := screen overlapWith: aWindow. distance := screen distanceTo: aWindow.
        (area > bestArea or: [ area = bestArea and: [ distance < bestDistance ] ]) ifTrue: [
            best := screen. bestArea := area. bestDistance := distance ] ].
    ^ best'.
DesktopManager compile: 'constrain: aWindow
    | screen newX newY newWidth newHeight minWidth minHeight maxWidth maxHeight |
    newX := aWindow x clampFrom: -100000 to: 100000.
    newY := aWindow y clampFrom: -100000 to: 100000.
    newWidth := aWindow width clampFrom: aWindow minimumWidth to: aWindow maximumWidth.
    newHeight := aWindow height clampFrom: aWindow minimumHeight to: aWindow maximumHeight.
    minWidth := aWindow minimumWidth. minHeight := aWindow minimumHeight.
    maxWidth := aWindow maximumWidth. maxHeight := aWindow maximumHeight.
    screen := self screenFor: aWindow.
    screen notNil ifTrue: [
        minWidth := minWidth min: screen width. minHeight := minHeight min: screen height.
        maxWidth := maxWidth min: screen width. maxHeight := maxHeight min: screen height.
        newWidth := newWidth min: screen width. newHeight := newHeight min: screen height.
        newX := newX clampFrom: screen x to: screen x + screen width - newWidth.
        newY := newY clampFrom: screen y to: screen y + screen height - newHeight ].
    aWindow nativeMinimumWidth: minWidth height: minHeight maximumWidth: maxWidth height: maxHeight.
    aWindow placeX: newX y: newY width: newWidth height: newHeight'.
DesktopManager compile: 'screensChanged: availableScreens
    model screens: availableScreens. self restoreWindows'.
DesktopManager compile: 'restoreWindows
    self windows do: [ :each | self constrain: each ]'.
