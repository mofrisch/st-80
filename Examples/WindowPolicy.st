"All window policy is ordinary Smalltalk. Native windows remain separate macOS windows."
UIWindow subclass: #GuardedWindow instanceVariableNames: 'allowClose'.
GuardedWindow compile: 'initialize
    super initialize.
    allowClose := false.
    self title: ''Smalltalk verwaltet dieses Fenster''.
    self minimumWidth: 600 height: 400'.
GuardedWindow compile: 'canClose ^ allowClose'.
GuardedWindow compile: 'allowClose: aBoolean allowClose := aBoolean. self changed: #canClose'.

Controller subclass: #WindowPolicyController instanceVariableNames: ''.
WindowPolicyController compile: 'closeWindow model allowClose: true; close'.

window := GuardedWindow new.
controller := WindowPolicyController new.
controller model: window.
label := UILabel new.
label text: 'Die native Schließtaste wird zunächst abgelehnt.'.
button := UIButton new.
button title: 'Schließen erlauben'.
button onClickSend: #closeWindow to: controller.
column := UIColumn new.
column padding: 20; spacing: 12; add: label; add: button.
window content: column; open.

"Desktop model enthält Zustand, Desktop ist der Controller.
 Desktop screens enthält die vom Backend gemeldeten sichtbaren Bildschirmflächen.
 Desktop constrain: window und Desktop restoreWindows führen die Smalltalk-Regeln aus."
Desktop model
