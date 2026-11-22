"Ein neues natives Fenster aus Smalltalk öffnen"
window := Desktop openWorkspace.
window title: 'Mein Workspace'.
window text: '6 * 7'.
window moveToX: 180 y: 240.
window resizeWidth: 700 height: 500.
Desktop openTranscript.
Transcript show: 'Fenster sind Smalltalk-Objekte.'; cr.
Desktop windows size
