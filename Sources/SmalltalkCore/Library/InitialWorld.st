"Initial world. This code only runs in a pristine runtime, never in a loaded image."
ToolVM := ToolServices new.
TranscriptBuffer := TranscriptModel new.
SystemOrganization := BrowserOrganization new.
Desktop := DesktopManager new.
(Desktop openWorkspace) text: WorkspaceExamples workspace.
Desktop openBrowser.
Desktop openTranscript.
Desktop arrangeTools.
Desktop activate: (Desktop windowAt: 1)
