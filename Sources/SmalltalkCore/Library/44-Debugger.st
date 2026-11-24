"The native debugger transports immutable data to this presentation in a separate interpreter."

Object subclass: #DebuggerPresentation instanceVariableNames: ''.

DebuggerPresentation compileClass: 'contentFor: stack frame: frame error: error phase: phase
    | root split pane |
    root := UIColumn new spacing: 0; yourself.
    root add: (self commandsFor: stack size error: error phase: phase); add: UIDivider new.
    error notNil ifTrue: [
        root add: (UIColumn new padding: 12;
            add: (UILabel new role: #error; identifier: ''debuggerError''; text: error; yourself); yourself);
            add: UIDivider new ].
    pane := frame isNil
        ifTrue: [ UILabel new role: #caption; text: ''No active frame''; yourself ]
        ifFalse: [ self framePane: frame ].
    split := UISplit new enabled: phase = #paused;
        add: (self stackPane: stack selection: (frame isNil ifTrue: [ nil ] ifFalse: [ frame at: 1 ]));
        add: pane; yourself.
    root add: split.
    ^ root'.

DebuggerPresentation compileClass: 'command: aTitle id: identifier send: aCommand enabled: available
    ^ UIButton new title: aTitle; identifier: identifier; command: aCommand; enabled: available; yourself'.

DebuggerPresentation compileClass: 'commandsFor: frameCount error: error phase: phase
    | controls canStep resume stop |
    canStep := phase = #paused and: [ error isNil ].
    resume := (self command: ''Continue'' id: ''debuggerContinue'' send: #resume enabled: canStep)
        role: #primary; yourself.
    stop := self command: (error isNil ifTrue: [ ''Stop'' ] ifFalse: [ ''Close'' ])
        id: ''debuggerStop'' send: #stop enabled: phase ~= #stopping.
    error isNil ifTrue: [ stop role: #destructive ].
    controls := UIRow new role: #compactBar; add: resume; yourself.
    controls add: (self command: ''Step Into'' id: ''debuggerStepInto'' send: #stepInto enabled: canStep).
    controls add: (self command: ''Step Over'' id: ''debuggerStepOver'' send: #stepOver enabled: canStep).
    controls add: (self command: ''Step Out'' id: ''debuggerStepOut'' send: #stepOut
        enabled: (canStep and: [ frameCount > 1 ])).
    controls add: UISpacer new.
    phase ~= #paused ifTrue: [
        controls add: (UILabel new role: #caption;
            text: (phase = #stopping ifTrue: [ ''Stopping…'' ] ifFalse: [ ''Running…'' ]); yourself) ].
    controls add: stop.
    ^ controls'.

DebuggerPresentation compileClass: 'stackPane: stack selection: key
    | list header |
    header := UIRow new role: #compactBar; add: (UILabel new role: #heading; text: ''Call Stack''; yourself); yourself.
    list := UIHistoryList new identifier: ''debuggerStack''; role: #compactEntries; rowIdentifierPrefix: ''debuggerFrame'';
        command: #selectFrame; entries: stack; selection: key; yourself.
    ^ UIColumn new spacing: 0; widthFrom: 160 to: 320; add: header; add: UIDivider new; add: list; yourself'.

DebuggerPresentation compileClass: 'framePane: frame
    | details editor variables text split |
    details := UIRow new role: #compactBar;
        add: (UILabel new role: #heading; identifier: ''debuggerFrameTitle''; text: (frame at: 2); yourself);
        add: UISpacer new;
        add: (UILabel new role: #pageNumber; identifier: ''debuggerLocation'';
            text: (''Line '' , (frame at: 4) printString , '', column '' , (frame at: 5) printString); yourself);
        yourself.
    editor := UIColumn new spacing: 0; heightFrom: 114 to: nil; add: details; add: UIDivider new; yourself.
    text := frame at: 3.
    text size = 0
        ifTrue: [ editor add: (UILabel new role: #caption; text: ''Source unavailable''; yourself) ]
        ifFalse: [ editor add: (UISourceView new identifier: ''debuggerSource''; text: text;
            line: (frame at: 4) column: (frame at: 5); yourself) ].
    (frame at: 6) size > 0 ifTrue: [
        editor add: UIDivider new;
            add: (UIColumn new padding: 8;
                add: (UILabel new role: #codePreview; identifier: ''debuggerInstruction''; text: (frame at: 6); yourself);
                yourself) ].
    variables := UIValueTable new identifier: ''debuggerVariables''; rowIdentifierPrefix: ''debuggerVariable'';
        rows: (frame at: 7); readOnly: true; heightFrom: 95 to: nil; yourself.
    split := UISplit new role: #vertical; add: editor; add: variables; yourself.
    ^ split'.
