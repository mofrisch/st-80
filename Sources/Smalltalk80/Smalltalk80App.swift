import AppKit
import SwiftUI

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

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
                Divider()
                Button("Show Workspace") { Task { await controller.showWorkspace() } }.keyboardShortcut("1")
                Button("Open Browser") { Task { await controller.openTool(.browser) } }.keyboardShortcut("2")
                Button("Open Transcript") { Task { await controller.openTool(.transcript) } }.keyboardShortcut("3")
                Button("Code Changes …") { Task { await controller.showChanges() } }.disabled(controller.isRunning)
                Button("Open Changes File …") { Task { await controller.openChanges() } }.disabled(controller.isRunning)
                Divider()
                Button("Reset Session") { Task { await controller.reset() } }.disabled(controller.isRunning)
            }
        }
    }
}
