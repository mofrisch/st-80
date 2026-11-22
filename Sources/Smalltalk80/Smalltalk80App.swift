import AppKit
import SwiftUI

@main
struct Smalltalk80App: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Smalltalk/80", id: "main") {
            SystemView(model: model)
                .frame(minWidth: 1_050, minHeight: 700)
                .task { await model.load() }
        }
        .defaultSize(width: 1_280, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Neuer Workspace") { model.example("") }.keyboardShortcut("n").disabled(model.isRunning)
                Button("Workspace öffnen …") { model.openWorkspace() }.keyboardShortcut("o").disabled(model.isRunning)
                Button(model.mode == .browser ? "Methode akzeptieren" : "Workspace speichern …") {
                    if model.mode == .browser { Task { await model.acceptMethod() } }
                    else { model.saveWorkspace() }
                }
                .keyboardShortcut("s")
                .disabled(model.isRunning || model.mode == .browser && (model.isPrimitive || model.methodSource.isEmpty))
                Divider()
                Button("Image öffnen …") { Task { await model.openImage() } }
                    .keyboardShortcut("o", modifiers: [.command, .shift]).disabled(model.isRunning)
                Button(model.imageURL == nil ? "Image speichern …" : "Image speichern") {
                    Task { await model.saveImage() }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift]).disabled(model.isRunning)
                Button("Image speichern unter …") { Task { await model.saveImage(asNewFile: true) } }
                    .keyboardShortcut("s", modifiers: [.command, .option, .shift]).disabled(model.isRunning)
            }
            CommandMenu("Smalltalk") {
                Button("Do it") { Task { await model.run() } }.keyboardShortcut("d")
                    .disabled(model.isRunning || model.mode != .workspace)
                Button("Print it") { Task { await model.run(printResult: true) } }.keyboardShortcut("p")
                    .disabled(model.isRunning || model.mode != .workspace)
                Divider()
                Button("Workspace anzeigen") { model.mode = .workspace }.keyboardShortcut("1")
                Button("Browser anzeigen") { model.mode = .browser }.keyboardShortcut("2")
                Divider()
                Button("Sitzung zurücksetzen") { Task { await model.reset() } }.disabled(model.isRunning)
            }
        }
    }
}
