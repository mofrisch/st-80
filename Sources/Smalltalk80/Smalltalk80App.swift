import AppKit
import SwiftUI

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()
    private var quitPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Use the bundled artwork for Dock and About, bypassing stale system icons.
        if let icon = Bundle.main.image(forResource: "AppIcon") {
            NSImage(named: NSImage.applicationIconName)?.setName(nil)
            icon.setName(NSImage.applicationIconName)
            NSApp.applicationIconImage = icon
        }
        Task { await controller.load(); NSApp.activate(ignoringOtherApps: true) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitPending { return .terminateLater }
        guard sender.modalWindow == nil else { return .terminateCancel }
        guard controller.isRunning || controller.imageNeedsSaving() else { return .terminateNow }

        quitPending = true
        controller.stopDebugging()
        Task {
            await controller.waitForCurrentOperation()
            let shouldQuit = controller.imageNeedsSaving() ? await confirmQuit() : true
            quitPending = false
            sender.reply(toApplicationShouldTerminate: shouldQuit)
        }
        return .terminateLater
    }

    private func confirmQuit() async -> Bool {
        let alert = NSAlert()
        alert.messageText = "Save changes to the Smalltalk image?"
        alert.informativeText = "Your changes since the last save will be lost if you quit without saving."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        alert.addButton(withTitle: "Don't Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            switch await controller.saveImage() {
            case .saved:
                return !controller.imageNeedsSaving()
            case .cancelled:
                return false
            case .failed(let reason):
                let failure = NSAlert()
                failure.messageText = "Could not save the image"
                failure.informativeText = reason
                failure.runModal()
                return false
            }
        case .alertThirdButtonReturn:
            return true
        default:
            return false
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Task { await controller.showWorkspace() } }
        return true
    }
}

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
