import SmalltalkCore
import SwiftUI

/// Recognize the stock chrome in both the boot library and saved images.
/// An image that defines its own layout falls back to the projected view.
enum StandardToolChrome {
    static func result(in pane: UIElementInfo) -> UIElementInfo? {
        guard pane.kind == .scroll, pane.children.count == 2,
              pane.children[0].kind == .label, pane.children[0].role == "caption",
              pane.children[1].kind == .label, pane.children[1].accessibilityID == "evaluationResult"
        else { return nil }
        return pane.children[1]
    }

    static func imageBar(_ bar: UIElementInfo) -> Bool {
        guard bar.kind == .row, bar.children.count == 3 else { return false }
        let status = bar.children[0]
        return status.kind == .column && status.children.map(\.role) == ["imageName", "imageStatus"] &&
            bar.children[1].kind == .spacer && bar.children[2].kind == .button &&
            bar.children[2].accessibilityID == "saveImageButton"
    }
}

struct ToolResultView: View {
    let controller: AppController
    let windowID: Int64
    let result: UIElementInfo
    @State private var isExpanded = false

    private var isError: Bool { result.role == "error" }
    private var hasResult: Bool {
        result.visible && !result.text.isEmpty && result.text != "Ready." &&
            result.text != "Ready. Press ⌘D to run the selection or the entire workspace."
    }

    var body: some View {
        if hasResult {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Label(isError ? "Error" : "Result", systemImage: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(isError ? Color.red : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                    .accessibilityIdentifier("toolResultToggle")
                    if isExpanded {
                        Spacer()
                    } else {
                        resultText.lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                if isExpanded {
                    ScrollView {
                        resultText
                            .padding(.horizontal, 10)
                            .padding(.bottom, 8)
                    }
                    .frame(idealHeight: 68, maxHeight: 112)
                }
            }
            .onChange(of: result.text) { isExpanded = false }
        }
    }

    private var resultText: some View {
        UIElementView(controller: controller, windowID: windowID, element: result)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkspaceControls {
    let editor: UIElementInfo
    let run: UIElementInfo
    let examples: UIElementInfo
    let result: UIElementInfo

    init?(_ content: UIElementInfo) {
        let children = content.children
        guard content.kind == .column, content.visible, children.count == 7,
              children[1].kind == .divider, children[3].kind == .divider, children[5].kind == .divider,
              children[2].kind == .codeEditor, children[2].accessibilityID == "workspaceEditor",
              let result = StandardToolChrome.result(in: children[4]),
              StandardToolChrome.imageBar(children[6])
        else { return nil }

        let toolbar = children[0]
        guard toolbar.kind == .row, toolbar.visible, toolbar.children.count == 5,
              toolbar.children[0].kind == .label, toolbar.children[0].role == "heading",
              toolbar.children[1].kind == .spacer, toolbar.children[2].kind == .menu,
              toolbar.children[3].kind == .button, toolbar.children[3].command == "printIt",
              toolbar.children[4].kind == .button, toolbar.children[4].command == "doIt",
              toolbar.children[4].accessibilityID == "executeButton"
        else { return nil }

        let editor = children[2]
        if let menu = editor.contextMenuItems {
            let commands = Set(menu.compactMap(\.command))
            guard commands.isSuperset(of: ["doIt", "printIt", "inspectIt"]) else { return nil }
        }
        self.editor = editor
        run = toolbar.children[4]
        examples = toolbar.children[2]
        self.result = result
    }
}

struct WorkspaceToolbar: View {
    let controller: AppController
    let windowID: Int64
    private let controls: WorkspaceControls

    init?(controller: AppController, windowID: Int64, content: UIElementInfo) {
        guard let controls = WorkspaceControls(content) else { return nil }
        self.controller = controller
        self.windowID = windowID
        self.controls = controls
    }

    var body: some View {
        HStack(spacing: 5) {
            Button {
                Task { await controller.clickControl(windowID: windowID, elementID: controls.run.id) }
            } label: {
                HStack(spacing: 6) {
                    Text(controls.run.text)
                    Text("⌘D").font(.caption).accessibilityHidden(true)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!controls.run.enabled || !controls.run.visible)
            .accessibilityLabel(controls.run.text)
            .accessibilityIdentifier("executeButton")

            Menu {
                let commands = controller.editorContextItems(windowID: windowID, editor: controls.editor)
                ForEach(Array(commands.enumerated()), id: \.offset) { _, item in
                    if case .command(let title, let identifier, let action, let enabled) = item,
                       ["printIt", "inspectIt", "debugIt"].contains(identifier) {
                        Button(title) {
                            Task { await controller.performEditorContextAction(action, windowID: windowID) }
                        }
                        .disabled(!enabled)
                        .accessibilityIdentifier("workspaceAction-\(identifier)")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.callout)
                    .padding(.horizontal, 5)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Workspace actions")
            .accessibilityLabel("Workspace actions")
            .accessibilityIdentifier("workspaceActions")
        }
        .controlSize(.small)
        .disabled(controller.isRunning)
        .fixedSize()
    }
}

struct WorkspaceExamplesMenu: View {
    let controller: AppController

    var body: some View {
        if let window = controller.workspaceWindow, let content = window.content,
           let examples = WorkspaceControls(content)?.examples, examples.visible {
            UIElementView(controller: controller, windowID: window.id, element: examples)
        }
    }
}

struct WorkspaceToolView: View {
    let controller: AppController
    let windowID: Int64
    private let controls: WorkspaceControls
    init?(controller: AppController, windowID: Int64, content: UIElementInfo) {
        guard let controls = WorkspaceControls(content) else { return nil }
        self.controller = controller
        self.windowID = windowID
        self.controls = controls
    }

    var body: some View {
        VStack(spacing: 0) {
            UIElementView(controller: controller, windowID: windowID, element: controls.editor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ToolResultView(controller: controller, windowID: windowID, result: controls.result)
        }
    }
}

struct TranscriptToolView: View {
    let controller: AppController
    let windowID: Int64
    private let log: UIElementInfo
    private let clear: UIElementInfo

    init?(controller: AppController, windowID: Int64, content: UIElementInfo) {
        guard let clear = Self.clearButton(in: content) else { return nil }
        self.controller = controller
        self.windowID = windowID
        log = content.children[2]
        self.clear = clear
    }

    static func clearButton(in content: UIElementInfo) -> UIElementInfo? {
        let children = content.children
        guard content.kind == .column, content.visible, children.count == 3,
              children[1].kind == .divider, children[2].kind == .scroll, children[2].role == "followEnd",
              children[2].children.count == 1, children[2].children.first?.accessibilityID == "transcriptOutput"
        else { return nil }
        let toolbar = children[0]
        guard toolbar.kind == .row, toolbar.children.count == 3,
              toolbar.children[0].kind == .label, toolbar.children[0].role == "heading",
              toolbar.children[1].kind == .spacer, toolbar.children[2].kind == .button
        else { return nil }
        let clear = toolbar.children[2]
        return clear.text == "Clear" ? clear : nil
    }

    var body: some View {
        UIElementView(controller: controller, windowID: windowID, element: log)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .contextMenu {
                if clear.visible {
                    Button("Clear Transcript") {
                        Task { await controller.clickControl(windowID: windowID, elementID: clear.id) }
                    }
                    .disabled(!clear.enabled || controller.isRunning)
                    .accessibilityIdentifier("clearTranscript")
                }
            }
    }
}
