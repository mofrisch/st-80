import SwiftUI

@main
struct Smalltalk80App: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    private var controller: AppController { delegate.controller }

    var body: some Scene {
        Settings { Text("Windows and session state are stored in the Smalltalk image.").padding(24) }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Workspace") { Task { await controller.openTool(.workspace) } }.keyboardShortcut("n").disabled(controller.isRunning)
                Button("Open Workspace …") { Task { await controller.openWorkspace() } }.keyboardShortcut("o").disabled(controller.isRunning)
                Button(controller.activeKind == .browser ? "Accept" : "Save Workspace …") {
                    Task {
                        if controller.activeKind == .browser { await controller.performCommand("acceptMethod") }
                        else { await controller.saveWorkspace() }
                    }
                }
                .keyboardShortcut("s")
                .disabled(controller.isRunning || controller.activeKind == .browser && !controller.hasCommand("acceptMethod"))
                Divider()
                Button("Open Image …") { Task { await controller.openImage() } }
                    .keyboardShortcut("o", modifiers: [.command, .shift]).disabled(controller.isRunning)
                Button(controller.imageURL == nil ? "Save Image …" : "Save Image") { Task { await controller.saveImage() } }
                    .keyboardShortcut("s", modifiers: [.command, .shift]).disabled(controller.isRunning)
                Button("Save Image As …") { Task { await controller.saveImage(asNewFile: true) } }
                    .keyboardShortcut("s", modifiers: [.command, .option, .shift]).disabled(controller.isRunning)
            }
            CommandMenu("Smalltalk") {
                Button("Do it") { Task { await controller.performCommand("doIt") } }.keyboardShortcut("d")
                    .disabled(controller.isRunning || !controller.hasCommand("doIt"))
                Button("Print it") { Task { await controller.performCommand("printIt") } }.keyboardShortcut("p")
                    .disabled(controller.isRunning || !controller.hasCommand("printIt"))
                Button("Inspect it") { Task { await controller.inspectWorkspace() } }.keyboardShortcut("i")
                    .disabled(controller.isRunning || !controller.canInspectWorkspace)
                Button("Debug it") { Task { await controller.debugWorkspace() } }
                    .keyboardShortcut("d", modifiers: [.command, .shift]).disabled(!controller.canDebugWorkspace)
                Divider()
                ForEach(controller.workspaceAppMenus) { menu in
                    if let id = controller.workspaceWindow?.id {
                        UIElementView(controller: controller, windowID: id, element: menu)
                    }
                }
                Button("Show Workspace") { Task { await controller.showWorkspace() } }.keyboardShortcut("1")
                Button("Open Browser") { Task { await controller.openTool(.browser) } }.keyboardShortcut("2")
                Button("Open Transcript") { Task { await controller.openTool(.transcript) } }.keyboardShortcut("3")
                Button("Clear Transcript") { Task { await controller.clearTranscript() } }
                    .disabled(controller.isRunning || !controller.canClearTranscript)
                Button("Arrange Tools") { Task { await controller.arrangeTools() } }.disabled(controller.isRunning)
                Button("Code Changes …") { Task { await controller.showChanges() } }.disabled(controller.isRunning)
                Button("Open Changes File …") { Task { await controller.openChanges() } }.disabled(controller.isRunning)
                Divider()
                Button("Reset Session") { Task { await controller.reset() } }.disabled(controller.isRunning)
            }
        }
    }
}
