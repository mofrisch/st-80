"The window owns the history view. The journal remains the source of truth."

UIWindow subclass: #ChangesBrowser instanceVariableNames: 'headingLabel entries source pathLabel restore resultLabel selected className selector side revision'.

ChangesBrowser compile: 'initialize
    super initialize.
    self kind: #changes; title: ''Code Changes''.
    self buildContent'.

ChangesBrowser compile: 'buildContent
    | heading toolbar split all |
    headingLabel := UILabel new role: #heading; yourself.
    heading := UIColumn new spacing: 3; add: headingLabel;
        add: (UILabel new role: #caption; text: ''Accepted code is logged immediately. The image stores the object graph.''; yourself);
        yourself.
    all := UIButton new title: ''All Changes''; identifier: ''allChangesButton''; onClickSend: #allChanges to: self; yourself.
    restore := UIButton new title: ''Restore Version''; identifier: ''restoreChangeButton''; enabled: false;
        onClickSend: #restoreSelected to: self; yourself.
    toolbar := UIRow new role: #compactBar; add: heading; add: UISpacer new; add: all; add: restore; yourself.
    entries := UIHistoryList new identifier: ''changesList''; widthFrom: 250 to: nil; onSelectSend: #select: to: self; yourself.
    source := UILabel new role: #document; yourself.
    split := UISplit new add: entries;
        add: (UIScroll new identifier: ''changeSource''; padding: 14; add: source; yourself); yourself.
    pathLabel := UILabel new role: #caption; visible: false; yourself.
    resultLabel := UILabel new role: #code; identifier: ''evaluationResult''; visible: false; yourself.
    self content: (UIColumn new spacing: 0; add: toolbar; add: UIDivider new; add: split; add: UIDivider new;
        add: (UIColumn new padding: 8; add: pathLabel; add: resultLabel; yourself); yourself)'.

ChangesBrowser compile: 'showClass: aName selector: aSelector side: aSide
    className := aName.
    selector := aSelector.
    side := aSide.
    selected := nil.
    resultLabel visible: false.
    self reload'.

ChangesBrowser compile: 'allChanges
    self showClass: nil selector: nil side: nil.
    ^ nil'.

ChangesBrowser compile: 'synchronizeHistory
    revision ~= ToolVM changesBrowserRevision ifTrue: [ self reload ]'.

ChangesBrowser compile: 'reload
    | owner path |
    owner := className isNil ifTrue: [ nil ] ifFalse: [
        className , (side = #class ifTrue: [ '' class'' ] ifFalse: [ '''' ]) ].
    headingLabel text: (owner isNil ifTrue: [ ''Code Changes'' ] ifFalse: [
        ''Versions: '' , owner , (selector isNil ifTrue: [ '''' ] ifFalse: [ '' » '' , selector ]) ]).
    entries entries: (ToolVM historyFor: className selector: selector side: side).
    (entries includes: selected) ifFalse: [ selected := nil ].
    self select: selected.
    path := ToolVM changeJournalPath.
    pathLabel visible: path notNil.
    path notNil ifTrue: [ pathLabel text: path ].
    revision := ToolVM changesBrowserRevision'.

ChangesBrowser compile: 'select: key
    selected := key.
    entries selection: key.
    restore enabled: key notNil.
    source text: (key isNil
        ifTrue: [ ''Select a change. You can restore later entries individually after restarting.'' ]
        ifFalse: [ ToolVM changeSourceAt: key ]).
    ^ nil'.

ChangesBrowser compile: 'restoreSelected
    | outcome |
    selected isNil ifTrue: [ ^ nil ].
    outcome := ToolVM restoreVersion: selected.
    resultLabel role: ((outcome at: 1) ifTrue: [ #code ] ifFalse: [ #error ]);
        text: (outcome at: 2); visible: true.
    ^ nil'.
