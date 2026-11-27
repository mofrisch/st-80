import AppKit
import SmalltalkCore
import SwiftUI

@main
struct Smalltalk80App: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate

    var body: some Scene {
        let controller = delegate.controller
        let menu = controller.applicationMenu
        let customMenus = menu?.children.filter { $0.kind == .menu && $0.visible && $0.role == nil } ?? []
        // The scene hosts the native menu bar. SettingsWindow comes from the image.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    nativeItems(controller.menuGroup("appSettings"), controller: controller)
                }
                CommandGroup(replacing: .newItem) {
                    nativeItems(controller.menuGroup("fileActions"), controller: controller)
                }
                CommandGroup(replacing: .saveItem) {
                    nativeItems(controller.menuGroup("fileClose"), controller: controller)
                }
                if let menu = customMenus.first {
                    CommandMenu(menu.text) { ApplicationMenuItems(controller: controller, children: menu.children) }
                }
                if let menu = customMenus.dropFirst().first {
                    CommandMenu(menu.text) { ApplicationMenuItems(controller: controller, children: menu.children) }
                }
            }
    }

    @ViewBuilder
    private func nativeItems(_ children: [UIElementInfo], controller: AppController) -> some View {
        let visible = children.filter(\.visible).flatMap { item -> [UIElementInfo] in
            if item.role == "browserCommands" {
                return controller.activeKind == .browser ? item.children.filter(\.visible) : []
            }
            return [item]
        }
        ForEach(visible) { item in
            if item.kind == .divider {
                Divider()
            } else if let action = item.command.flatMap(NativeMenuAction.init(rawValue:)),
                      item.showsInMenu(forNamedImage: controller.imageURL != nil) {
                Button(item.text) { Task { await action.perform(in: controller) } }
                    .keyboardShortcut(menuShortcut(item.label))
                    .disabled(!item.enabled || !action.isEnabled(in: controller))
            }
        }
    }
}

private struct ApplicationMenuItems: View {
    let controller: AppController
    let children: [UIElementInfo]

    var body: some View {
        ForEach(children.filter(\.visible)) { item in
            switch (item.kind, item.role) {
            case (.menu, "focusedCommands"):
                focusedCommands(withSuffix: item.children)
            case (.menu, "workspaceMenus"):
                ForEach(controller.workspaceAppMenus) { menu in
                    if let id = controller.workspaceWindow?.id {
                        UIElementView(controller: controller, windowID: id, element: menu)
                    }
                }
            case (.menu, _):
                Menu(item.text) { items(item.children) }.disabled(!item.enabled)
            case (.button, _):
                if let action = item.command.flatMap(NativeMenuAction.init(rawValue:)), item.showsInMenu(forNamedImage: controller.imageURL != nil) {
                    Button(item.text) { Task { await action.perform(in: controller) } }
                        .keyboardShortcut(menuShortcut(item.label))
                        .disabled(!item.enabled || !action.isEnabled(in: controller))
                }
            case (.divider, _):
                Divider()
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func focusedCommands(withSuffix suffix: [UIElementInfo]) -> some View {
        if controller.windowPresentation.isRecovering {
            ForEach(controller.recoveryMenuItems) { item in
                if item.kind == .divider {
                    Divider()
                } else if let command = item.command, let action = WorkspaceRecoveryAction(command: command) {
                    Button(item.text) { Task { await controller.performRecoveryCommand(action) } }
                        .keyboardShortcut(menuShortcut(item.label))
                        .disabled(!item.enabled || !controller.canRunRecoveryCommands)
                }
            }
            if !controller.recoveryMenuItems.isEmpty { items(suffix) }
        } else if let window = controller.applicationCommandWindow,
                  let commands = window.content?.applicationCommands, !commands.isEmpty {
            ForEach(commands) { item in
                if item.kind == .divider {
                    Divider()
                } else {
                    Button(item.text) {
                        Task { await controller.performApplicationCommand(item.id, in: window) }
                    }
                    .keyboardShortcut(menuShortcut(item.label.isEmpty ? defaultShortcut(for: item.command) : item.label))
                    .disabled(controller.isRunning || !item.enabled)
                }
            }
            items(suffix)
        }
    }

    private func items(_ children: [UIElementInfo]) -> ApplicationMenuItems {
        ApplicationMenuItems(controller: controller, children: children)
    }

    private func defaultShortcut(for command: String?) -> String {
        guard let command else { return "" }
        return controller.menuGroup("workspaceShortcuts").first { $0.visible && $0.command == command }?.label ?? ""
    }
}

private enum NativeMenuAction: String {
    case settings, acceptMethod, openImage, importInterchange, saveImage, saveImageAs, close
    case clearTranscript, arrangeTools, codeChanges, openChanges, reset
    case browser, workspace, transcript

    @MainActor
    func isEnabled(in controller: AppController) -> Bool {
        if self == .close { return true }
        guard !controller.isRunning else { return false }
        switch self {
        case .acceptMethod: return controller.hasCommand(rawValue)
        case .clearTranscript: return controller.canClearTranscript
        default: return true
        }
    }

    @MainActor
    func perform(in controller: AppController) async {
        guard isEnabled(in: controller) else { return }
        switch self {
        case .settings: await controller.showSettings()
        case .acceptMethod: await controller.performCommand(rawValue)
        case .openImage: await controller.openImage()
        case .importInterchange: await controller.chooseInterchangeFile()
        case .saveImage: await controller.saveImage()
        case .saveImageAs: await controller.saveImage(asNewFile: true)
        case .close: NSApp.keyWindow?.performClose(nil)
        case .clearTranscript: await controller.clearTranscript()
        case .arrangeTools: await controller.arrangeTools()
        case .codeChanges: await controller.showChanges()
        case .openChanges: await controller.openChanges()
        case .reset: await controller.reset()
        case .browser: await controller.openTool(.browser)
        case .workspace: await controller.openTool(.workspace)
        case .transcript: await controller.openTool(.transcript)
        }
    }
}

private extension UIElementInfo {
    func showsInMenu(forNamedImage hasName: Bool) -> Bool {
        switch role {
        case "namedImage": hasName
        case "unnamedImage": !hasName
        default: true
        }
    }
}

private func menuShortcut(_ description: String) -> KeyboardShortcut? {
    guard let key = description.last else { return nil }
    let lower = key.lowercased()
    guard lower.count == 1, let character = lower.first else { return nil }
    var modifiers: EventModifiers = []
    for symbol in description.dropLast() {
        switch symbol {
        case "⌘": modifiers.insert(.command)
        case "⇧": modifiers.insert(.shift)
        case "⌥": modifiers.insert(.option)
        case "⌃": modifiers.insert(.control)
        default: return nil
        }
    }
    return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
}
