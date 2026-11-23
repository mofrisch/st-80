"All window policy is ordinary Smalltalk. Native windows remain separate macOS windows."
UIWindow subclass: #GuardedWindow instanceVariableNames: 'allowClose'.
GuardedWindow compile: 'initialize
    super initialize.
    allowClose := false.
    self title: ''Smalltalk manages this window''.
    self minimumWidth: 600 height: 400'.
GuardedWindow compile: 'canClose ^ allowClose'.
GuardedWindow compile: 'allowClose: aBoolean allowClose := aBoolean. self changed: #canClose'.

Controller subclass: #WindowPolicyController instanceVariableNames: ''.
WindowPolicyController compile: 'closeWindow model allowClose: true; close'.

window := GuardedWindow new.
controller := WindowPolicyController new.
controller model: window.
label := UILabel new.
label text: 'This window initially refuses requests to close.'.
button := UIButton new.
button title: 'Allow Closing'.
button onClickSend: #closeWindow to: controller.
column := UIColumn new.
column padding: 20; spacing: 12; add: label; add: button.
window content: column; open.

"Desktop model holds the state. Desktop is the controller.
 Desktop screens holds the visible display areas reported by the backend.
 Desktop constrain: window and Desktop restoreWindows apply the Smalltalk window rules."
Desktop model
