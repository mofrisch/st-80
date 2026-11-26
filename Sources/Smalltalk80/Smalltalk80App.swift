import AppKit
import SwiftUI

@main
struct Smalltalk80App: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    private var controller: AppController { delegate.controller }

    var body: some Scene {
        // The scene hosts the menu commands. SettingsWindow comes from the image.
        Settings { EmptyView() }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { Task { await controller.showSettings() } }
                    .keyboardShortcut(",").disabled(controller.isRunning)
            }
            CommandGroup(replacing: .newItem) {
                if controller.activeKind == .browser {
                    Button("Accept") { Task { await controller.performCommand("acceptMethod") } }
                        .keyboardShortcut("s").disabled(controller.isRunning || !controller.hasCommand("acceptMethod"))
                    Divider()
                }
                Button("Open Image …") { Task { await controller.openImage() } }
                    .keyboardShortcut("o", modifiers: [.command, .shift]).disabled(controller.isRunning)
                Button(controller.imageURL == nil ? "Save Image …" : "Save Image") { Task { await controller.saveImage() } }
                    .keyboardShortcut("s", modifiers: [.command, .shift]).disabled(controller.isRunning)
                Button("Save Image As …") { Task { await controller.saveImage(asNewFile: true) } }
                    .keyboardShortcut("s", modifiers: [.command, .option, .shift]).disabled(controller.isRunning)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Close") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
            }
            CommandMenu("Smalltalk") {
                toolCommands
                ForEach(controller.workspaceAppMenus) { menu in
                    if let id = controller.workspaceWindow?.id {
                        UIElementView(controller: controller, windowID: id, element: menu)
                    }
                }
                Button("Clear Transcript") { Task { await controller.clearTranscript() } }
                    .disabled(controller.isRunning || !controller.canClearTranscript)
                Button("Arrange Tools") { Task { await controller.arrangeTools() } }.disabled(controller.isRunning)
                Button("Code Changes …") { Task { await controller.showChanges() } }.disabled(controller.isRunning)
                Button("Open Changes File …") { Task { await controller.openChanges() } }.disabled(controller.isRunning)
                Divider()
                Button("Reset Session") { Task { await controller.reset() } }.disabled(controller.isRunning)
            }
            CommandMenu("Tools") {
                Button("Browser") { Task { await controller.openTool(.browser) } }
                    .keyboardShortcut("b").disabled(controller.isRunning)
                Button("Workspace") { Task { await controller.openTool(.workspace) } }
                    .keyboardShortcut("w").disabled(controller.isRunning)
                Button("Transcript") { Task { await controller.openTool(.transcript) } }
                    .keyboardShortcut("t").disabled(controller.isRunning)
            }
        }
    }

    @ViewBuilder
    private var toolCommands: some View {
        if controller.windowPresentation.isRecovering {
            Group {
                Button("Do it") { Task { await controller.performRecoveryCommand(.evaluate) } }.keyboardShortcut("d")
                Button("Print it") { Task { await controller.performRecoveryCommand(.print) } }.keyboardShortcut("p")
                Button("Inspect it") { Task { await controller.performRecoveryCommand(.inspect) } }.keyboardShortcut("i")
            }
            .disabled(!controller.canRunRecoveryCommands)
            Divider()
        } else if let window = controller.applicationCommandWindow,
                  let commands = window.content?.applicationCommands, !commands.isEmpty {
            ForEach(commands) { item in
                if item.kind == .divider {
                    Divider()
                } else {
                    Button(item.text) {
                        Task { await controller.performApplicationCommand(item.id, in: window) }
                    }
                    .keyboardShortcut(shortcut(for: item.command))
                    .disabled(controller.isRunning || !item.enabled)
                }
            }
            Divider()
        }
    }

    private func shortcut(for command: String?) -> KeyboardShortcut? {
        switch command {
        case "doIt": KeyboardShortcut("d")
        case "printIt": KeyboardShortcut("p")
        case "inspectIt": KeyboardShortcut("i")
        case "debugIt": KeyboardShortcut("d", modifiers: [.command, .shift])
        default: nil
        }
    }
}
