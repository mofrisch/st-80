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
        Settings { Text("Fenster und Sitzung werden im Smalltalk-Image gespeichert.").padding(24) }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Neuer Workspace") { Task { await controller.openTool(.workspace) } }.keyboardShortcut("n").disabled(controller.isRunning)
                Button("Workspace öffnen …") { Task { await controller.openWorkspace() } }.keyboardShortcut("o").disabled(controller.isRunning)
                Button(controller.activeKind == .browser ? "Methode akzeptieren" : "Workspace speichern …") {
                    Task {
                        if controller.activeKind == .browser { await controller.performCommand("acceptMethod") }
                        else { await controller.saveWorkspace() }
                    }
                }
                .keyboardShortcut("s")
                .disabled(controller.isRunning || controller.activeKind == .browser && !controller.hasCommand("acceptMethod"))
                Divider()
                Button("Image öffnen …") { Task { await controller.openImage() } }
                    .keyboardShortcut("o", modifiers: [.command, .shift]).disabled(controller.isRunning)
                Button(controller.imageURL == nil ? "Image speichern …" : "Image speichern") { Task { await controller.saveImage() } }
                    .keyboardShortcut("s", modifiers: [.command, .shift]).disabled(controller.isRunning)
                Button("Image speichern unter …") { Task { await controller.saveImage(asNewFile: true) } }
                    .keyboardShortcut("s", modifiers: [.command, .option, .shift]).disabled(controller.isRunning)
            }
            CommandMenu("Smalltalk") {
                Button("Do it") { Task { await controller.performCommand("doIt") } }.keyboardShortcut("d")
                    .disabled(controller.isRunning || !controller.hasCommand("doIt"))
                Button("Print it") { Task { await controller.performCommand("printIt") } }.keyboardShortcut("p")
                    .disabled(controller.isRunning || !controller.hasCommand("printIt"))
                Divider()
                Button("Workspace anzeigen") { Task { await controller.showWorkspace() } }.keyboardShortcut("1")
                Button("Browser öffnen") { Task { await controller.openTool(.browser) } }.keyboardShortcut("2")
                Button("Transcript öffnen") { Task { await controller.openTool(.transcript) } }.keyboardShortcut("3")
                Button("Codeänderungen …") { Task { await controller.showChanges() } }.disabled(controller.isRunning)
                Button("Changes-Datei öffnen …") { Task { await controller.openChanges() } }.disabled(controller.isRunning)
                Divider()
                Button("Sitzung zurücksetzen") { Task { await controller.reset() } }.disabled(controller.isRunning)
            }
        }
    }
}
