"Feedback for the native tool host, including when the image's desktop is damaged."

Object subclass: #ToolWindowFeedback instanceVariableNames: ''.

ToolWindowFeedback compileClass: 'contentFor: recoveryResult inputError: inputError activeError: activeError displayedResult: displayedResult
    | error content |
    error := inputError isNil ifTrue: [ activeError ] ifFalse: [ inputError ].
    error = displayedResult ifTrue: [ error := nil ].
    (recoveryResult isNil and: [ error isNil ]) ifTrue: [ ^ nil ].
    content := UIColumn new spacing: 0; yourself.
    recoveryResult notNil ifTrue: [
        content add: UIDivider new;
            add: (self sectionFor: recoveryResult role: #code identifier: ''workspaceRecoveryResult'') ].
    error notNil ifTrue: [
        content add: UIDivider new;
            add: (self sectionFor: error role: #error identifier: ''toolWindowError'') ].
    ^ content'.

ToolWindowFeedback compileClass: 'sectionFor: message role: aRole identifier: anIdentifier
    ^ UIColumn new padding: 12;
        add: (UILabel new role: aRole; identifier: anIdentifier;
            text: (message suffixFittingUTF8: 65536); yourself);
        yourself'.
