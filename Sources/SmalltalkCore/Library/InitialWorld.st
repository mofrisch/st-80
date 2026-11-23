"Initial world. This code only runs in a pristine runtime, never in a loaded image."
ToolVM := ToolServices new.
TranscriptBuffer := TranscriptModel new.
Desktop := DesktopManager new.
(Desktop openWorkspace) text: (ToolVM exampleAt: #workspace).
Desktop openBrowser.
Desktop openTranscript.
Desktop activate: (Desktop windowAt: 1)
