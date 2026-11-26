"Application commands and shortcuts. Roles identify insertion points in the native menu bar."

Object subclass: #ApplicationMenu instanceVariableNames: ''.

ApplicationMenu compileClass: 'menuBar
    ^ UIColumn new
        add: (UIMenu new role: #appSettings;
            add: (self command: #settings title: ''Settings…'' shortcut: ''⌘,''); yourself);
        add: self fileMenu;
        add: (UIMenu new role: #fileClose;
            add: (self command: #close title: ''Close'' shortcut: ''⇧⌘W''); yourself);
        add: self smalltalkMenu;
        add: self toolsMenu;
        add: self workspaceShortcuts;
        yourself'.

ApplicationMenu compileClass: 'fileMenu
    ^ UIMenu new role: #fileActions;
        add: (UIMenu new role: #browserCommands;
            add: (self command: #acceptMethod title: ''Accept'' shortcut: ''⌘S'');
            add: UIDivider new; yourself);
        add: (self command: #openImage title: ''Open Image …'' shortcut: ''⇧⌘O'');
        add: ((self command: #saveImage title: ''Save Image …'' shortcut: ''⇧⌘S'') role: #unnamedImage; yourself);
        add: ((self command: #saveImage title: ''Save Image'' shortcut: ''⇧⌘S'') role: #namedImage; yourself);
        add: (self command: #saveImageAs title: ''Save Image As …'' shortcut: ''⇧⌥⌘S'');
        yourself'.

ApplicationMenu compileClass: 'smalltalkMenu
    ^ UIMenu new title: ''Smalltalk'';
        add: (UIMenu new role: #focusedCommands; add: UIDivider new; yourself);
        add: (UIMenu new role: #workspaceMenus; yourself);
        add: (self command: #clearTranscript title: ''Clear Transcript'' shortcut: nil);
        add: (self command: #arrangeTools title: ''Arrange Tools'' shortcut: nil);
        add: (self command: #codeChanges title: ''Code Changes …'' shortcut: nil);
        add: (self command: #openChanges title: ''Open Changes File …'' shortcut: nil);
        add: UIDivider new;
        add: (self command: #reset title: ''Reset Session'' shortcut: nil);
        yourself'.

ApplicationMenu compileClass: 'toolsMenu
    ^ UIMenu new title: ''Tools'';
        add: (self command: #browser title: ''Browser'' shortcut: ''⌘B'');
        add: (self command: #workspace title: ''Workspace'' shortcut: ''⌘W'');
        add: (self command: #transcript title: ''Transcript'' shortcut: ''⌘T'');
        yourself'.

ApplicationMenu compileClass: 'workspaceShortcuts
    ^ self recoveryCommands role: #workspaceShortcuts;
        add: (self command: #debugIt title: ''Debug it'' shortcut: ''⇧⌘D'');
        yourself'.

ApplicationMenu compileClass: 'recoveryCommands
    ^ UIMenu new title: ''Recovery'';
        add: (self command: #doIt title: ''Do it'' shortcut: ''⌘D'');
        add: (self command: #printIt title: ''Print it'' shortcut: ''⌘P'');
        add: (self command: #inspectIt title: ''Inspect it'' shortcut: ''⌘I'');
        yourself'.

ApplicationMenu compileClass: 'command: aCommand title: aTitle shortcut: aShortcut
    ^ UIButton new command: aCommand; title: aTitle; shortcutHint: aShortcut; yourself'.

"Trusted recovery policy, executed in the image that needs repair."

Object subclass: #WorkspaceRecoveryCommands instanceVariableNames: ''.

WorkspaceRecoveryCommands compileClass: 'doIt: source services: services transcript: output
    ^ services evaluateSource: source'.

WorkspaceRecoveryCommands compileClass: 'printIt: source services: services transcript: output
    | result |
    result := self doIt: source services: services transcript: output.
    (result at: 1) ifTrue: [
        output isNil ifTrue: [ result at: 1 put: false; at: 2 put: ''Transcript is missing.''. ^ result ].
        output show: ''→ '' , (result at: 2); cr ].
    ^ result'.

WorkspaceRecoveryCommands compileClass: 'inspectIt: source services: services transcript: output
    ^ services inspectSource: source'.
