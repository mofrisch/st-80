import AppKit
import SwiftUI

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Task { await model.load(); NSApp.activate(ignoringOtherApps: true) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Task { await model.showWorkspace() } }
        return true
    }
}

@main
struct Smalltalk80App: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    private var model: AppModel { delegate.model }

    var body: some Scene {
        Settings { Text("Fenster und Sitzung werden im Smalltalk-Image gespeichert.").padding(24) }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Neuer Workspace") { Task { await model.openTool(.workspace) } }.keyboardShortcut("n").disabled(model.isRunning)
                Button("Workspace öffnen …") { Task { await model.openWorkspace() } }.keyboardShortcut("o").disabled(model.isRunning)
                Button(model.activeKind == .browser ? "Methode akzeptieren" : "Workspace speichern …") {
                    if model.activeKind == .browser { Task { await model.acceptMethod() } }
                    else { model.saveWorkspace() }
                }
                .keyboardShortcut("s")
                .disabled(model.isRunning || model.activeKind == .browser && (model.isPrimitive || model.methodSource.isEmpty))
                Divider()
                Button("Image öffnen …") { Task { await model.openImage() } }
                    .keyboardShortcut("o", modifiers: [.command, .shift]).disabled(model.isRunning)
                Button(model.imageURL == nil ? "Image speichern …" : "Image speichern") { Task { await model.saveImage() } }
                    .keyboardShortcut("s", modifiers: [.command, .shift]).disabled(model.isRunning)
                Button("Image speichern unter …") { Task { await model.saveImage(asNewFile: true) } }
                    .keyboardShortcut("s", modifiers: [.command, .option, .shift]).disabled(model.isRunning)
            }
            CommandMenu("Smalltalk") {
                Button("Do it") { Task { await model.run() } }.keyboardShortcut("d")
                    .disabled(model.isRunning || model.activeKind != .workspace)
                Button("Print it") { Task { await model.run(printResult: true) } }.keyboardShortcut("p")
                    .disabled(model.isRunning || model.activeKind != .workspace)
                Divider()
                Button("Workspace anzeigen") { Task { await model.showWorkspace() } }.keyboardShortcut("1")
                Button("Browser öffnen") { Task { await model.openTool(.browser) } }.keyboardShortcut("2")
                Button("Transcript öffnen") { Task { await model.openTool(.transcript) } }.keyboardShortcut("3")
                Divider()
                Button("Sitzung zurücksetzen") { Task { await model.reset() } }.disabled(model.isRunning)
            }
        }
    }
}
