"Open a new native window from Smalltalk"
window := Desktop openWorkspace.
window title: 'My Workspace'.
window text: '6 * 7'.
window moveToX: 180 y: 240.
window resizeWidth: 700 height: 500.
Desktop openTranscript.
Transcript show: 'Windows are Smalltalk objects.'; cr.
Desktop windows size
