import SmalltalkCore
import SwiftUI

struct ToolContentView: View {
    @Bindable var controller: AppController
    let windowID: Int64

    var body: some View {
        Group {
            if let window = controller.presentedWindow(windowID) {
                if window.info.kind == .changes {
                    ChangesView(controller: controller)
                } else {
                    VStack(spacing: 0) {
                        if let content = window.info.content {
                            UIElementView(controller: controller, windowID: windowID, element: content)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        if let error = window.inputError ?? controller.error {
                            Divider()
                            Text(error).foregroundStyle(.red)
                                .textSelection(.enabled).padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }.background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct UIElementView: View {
    @Bindable var controller: AppController
    let windowID: Int64
    let element: UIElementInfo

    var body: some View {
        if element.visible {
            content
                .disabled(!element.enabled || controller.isRunning ||
                          (element.command == "acceptMethod" && controller.presentedWindow(windowID)?.showsBytecode == true))
                .frame(
                    minWidth: element.minimumWidth.map { CGFloat($0) },
                    maxWidth: element.maximumWidth.map { CGFloat($0) },
                    minHeight: element.minimumHeight.map { CGFloat($0) },
                    maxHeight: element.maximumHeight.map { CGFloat($0) },
                    alignment: .topLeading
                )
        }
    }

    var identifier: String { element.accessibilityID ?? "ui-\(element.id)" }

    var text: Binding<String> {
        Binding(
            get: { controller.inputText(windowID: windowID, element: element) },
            set: { controller.editInput(windowID: windowID, elementID: element.id, text: $0) }
        )
    }

    @ViewBuilder
    var content: some View {
        switch element.kind {
        case .label:
            labelView.textSelection(.enabled).accessibilityIdentifier(identifier)
        case .button:
            button
        case .textField:
            VStack(alignment: .leading, spacing: 4) {
                if !element.label.isEmpty { Text(element.label).font(.callout) }
                TextField(element.placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(element.label.isEmpty ? element.placeholder : element.label)
                    .accessibilityIdentifier(identifier)
            }
        case .codeEditor:
            if identifier == "methodEditor", let window = controller.presentedWindow(windowID), window.info.kind == .browser {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button(window.showsBytecode ? "Source" : "Bytecode") {
                            controller.toggleBrowserBytecode(windowID: windowID)
                        }
                        .controlSize(.small)
                        .disabled(window.info.browserMethod == nil)
                        .accessibilityIdentifier("methodBytecodeToggle")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    Divider()
                    if window.showsBytecode, let method = window.info.browserMethod {
                        BrowserBytecodeEditor(controller: controller, windowID: windowID, method: method)
                            .id(method)
                    } else {
                        codeEditor
                    }
                }
            } else {
                codeEditor
            }
        case .list:
            Group {
                if element.role == "pane" {
                    list.listStyle(.bordered).controlSize(.small)
                } else {
                    list.listStyle(.sidebar)
                }
            }.accessibilityIdentifier(identifier)
        case .column:
            VStack(alignment: .leading, spacing: CGFloat(element.spacing)) { children }
                .padding(CGFloat(element.padding))
        case .row:
            HStack(alignment: .center, spacing: CGFloat(element.spacing)) { children }
                .padding(CGFloat(element.padding))
        case .split:
            if element.role == "vertical" {
                VSplitView { children }
            } else {
                HSplitView { children }
            }
        case .scroll:
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: CGFloat(element.spacing)) {
                        children
                        if element.role == "followEnd" { Color.clear.frame(height: 1).id("end") }
                    }
                    .padding(CGFloat(element.padding))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .onChange(of: element.children.map(\.text), initial: true) {
                    if element.role == "followEnd" { reader.scrollTo("end", anchor: .bottom) }
                }
            }
        case .menu:
            if element.role == "paneMenu" {
                Menu {
                    children
                } label: {
                    Image(systemName: "ellipsis.circle").accessibilityLabel(element.text)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier(identifier)
            } else {
                Menu(element.text) { children }
            }
        case .spacer:
            Spacer(minLength: 8)
        case .divider:
            Divider()
        }
    }

    private var children: some View {
        ForEach(element.children) { child in
            // Type erasure bounds the recursive SwiftUI view type.
            AnyView(UIElementView(controller: controller, windowID: windowID, element: child))
        }
    }

    private var codeEditor: some View {
        CodeEditor(
            text: text,
            selection: Binding(
                get: { controller.editorSelection(windowID: windowID, elementID: element.id) },
                set: { controller.setEditorSelection($0, windowID: windowID, elementID: element.id) }
            ),
            isEditable: !element.readOnly && element.enabled && !controller.isRunning,
            identifier: identifier,
            label: element.label,
            contextMenuItems: controller.editorContextItems(windowID: windowID, editor: element),
            contextCommandsEnabled: element.enabled && !controller.isRunning,
            onContextCommand: { action, selection in
                Task { await controller.performEditorContextAction(action, windowID: windowID, selection: selection) }
            }
        )
    }

    private var list: some View {
        List(selection: Binding(
            get: { element.selection },
            set: { value in
                Task { await controller.selectControl(windowID: windowID, elementID: element.id, value: value) }
            }
        )) {
            ForEach(element.items, id: \.self) { entry in
                Text(entry).font(.system(size: 12, design: .monospaced)).tag(entry)
            }
        }
    }

    @ViewBuilder
    private var button: some View {
        if element.role == "primary" {
            Button(element.text, action: click)
                .buttonStyle(.borderedProminent).accessibilityIdentifier(identifier)
        } else {
            Button(element.text, action: click).accessibilityIdentifier(identifier)
        }
    }

    private func click() {
        Task { await controller.clickControl(windowID: windowID, elementID: element.id) }
    }

    @ViewBuilder
    private var labelView: some View {
        switch element.role {
        case "heading": Text(element.text).font(.headline)
        case "caption": Text(element.text).font(.caption).foregroundStyle(.secondary)
        case "code": Text(element.text).font(.system(size: 13, design: .monospaced))
        case "error": Text(element.text).font(.system(size: 13, design: .monospaced)).foregroundStyle(.red)
        case "imageName":
            Text(controller.imageURL?.lastPathComponent ?? "No image saved yet").font(.caption.weight(.medium))
        case "imageStatus":
            if controller.imageHasChanges {
                Text("Unsaved changes").font(.caption).foregroundStyle(.secondary)
            } else if controller.imageURL != nil {
                Text("Saved").font(.caption).foregroundStyle(.secondary)
            }
        default: Text(element.text)
        }
    }
}

private struct BrowserBytecodeEditor: View {
    let controller: AppController
    let windowID: Int64
    let method: BrowserMethodSelection
    @State private var listing: String?
    @State private var selection = NSRange(location: 0, length: 0)

    var body: some View {
        let text = method.isPrimitive ? "This VM primitive has no bytecode." : listing ?? "Loading bytecode…"
        CodeEditor(text: .constant(text), selection: $selection, isEditable: false,
                   identifier: "bytecodeEditor", label: "Method Bytecode")
            .task {
                guard !method.isPrimitive else { return }
                let value = await controller.browserBytecode(windowID: windowID, method: method)
                guard !Task.isCancelled else { return }
                listing = value ?? "Bytecode unavailable."
            }
    }
}
