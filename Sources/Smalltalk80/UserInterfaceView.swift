import SmalltalkCore
import SwiftUI

struct WindowToolbarView: View {
    let controller: AppController
    let windowID: Int64

    var body: some View {
        if let toolbar = controller.presentedWindow(windowID)?.info.content?.windowToolbar {
            UIElementView(controller: controller, windowID: windowID, element: toolbar)
                .controlSize(.small)
                .fixedSize()
        }
    }
}

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
                        if let error = window.inputError ?? (controller.activeWindowID == windowID ? controller.error : nil),
                           window.info.content?.firstVisible(where: { $0.accessibilityID == "evaluationResult" })?.text != error {
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

struct UIElementView: View {
    @Bindable var controller: AppController
    let windowID: Int64
    let element: UIElementInfo

    var body: some View {
        if element.visible {
            content
                .disabled(controller.isRunning || !controller.canPerform(element, in: windowID))
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
            codeEditor.frame(maxWidth: .infinity, minHeight: 64, maxHeight: .infinity)
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
            row
        case .split:
            Group {
                if element.role == "vertical" {
                    VSplitView { children }
                } else {
                    HSplitView { children }
                }
            }.accessibilityIdentifier(identifier)
        case .scroll:
            if let items = element.contextMenuItems, !items.isEmpty {
                scroll.contextMenu {
                    ForEach(items) { item in control(item) }
                }
            } else {
                scroll
            }
        case .menu:
            menu
        case .spacer:
            Spacer(minLength: 8)
        case .divider:
            Divider()
        }
    }

    private var children: some View {
        ForEach(element.children.filter { !$0.isWindowChrome }) { child in control(child) }
    }

    private func control(_ child: UIElementInfo) -> some View {
        // Type erasure bounds the recursive SwiftUI view type.
        AnyView(UIElementView(controller: controller, windowID: windowID, element: child))
    }

    @ViewBuilder
    private var row: some View {
        switch element.role {
        case "segmented":
            ControlGroup { children }.fixedSize()
        case "compactBar", "paneHeader":
            HStack(spacing: element.role == "paneHeader" ? 4 : 8) { children }
                .controlSize(.small)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
        default:
            HStack(spacing: CGFloat(element.spacing)) { children }
                .padding(CGFloat(element.padding))
        }
    }

    private var scroll: some View {
        let followsEnd = element.role == "followEnd"
        return ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(element.spacing)) {
                    children
                    if followsEnd { Color.clear.frame(height: 1).id("end") }
                }
                .padding(CGFloat(element.padding))
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .onChange(of: element.children.map(\.text), initial: true) {
                if followsEnd { reader.scrollTo("end", anchor: .bottom) }
            }
            .background(followsEnd ? Color(nsColor: .textBackgroundColor) : .clear)
        }
    }

    @ViewBuilder
    private var menu: some View {
        if element.role == "paneMenu" || element.role == "moreMenu" {
            Menu {
                children
            } label: {
                Image(systemName: element.role == "paneMenu" ? "ellipsis.circle" : "ellipsis")
                    .accessibilityLabel(element.text)
                    .padding(.horizontal, element.role == "moreMenu" ? 5 : 0)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(element.text)
            .accessibilityLabel(element.text)
            .accessibilityIdentifier(identifier)
        } else {
            Menu(element.text) { children }
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
            allowsUndo: !element.readOnly,
            usesSmalltalkSourceStyle: element.role == "source",
            highlightsForSource: controller.sourceHighlights,
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
            Button(action: click) {
                HStack(spacing: 6) {
                    Text(element.text)
                    if !element.label.isEmpty {
                        Text(element.label).font(.caption).accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .fixedSize()
            .accessibilityLabel(element.text)
            .accessibilityIdentifier(identifier)
        } else if element.role == "disclosureOpen" || element.role == "disclosureClosed" {
            let expanded = element.role == "disclosureOpen"
            Button(action: click) {
                Label(element.text, systemImage: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel(element.text)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier(identifier)
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
        case "codePreview": Text(element.text).font(.system(size: 13, design: .monospaced)).lineLimit(1)
        case "errorPreview": Text(element.text).font(.system(size: 13, design: .monospaced)).foregroundStyle(.red).lineLimit(1)
        default: Text(element.text)
        }
    }
}

extension UIElementInfo {
    var isWindowChrome: Bool { role == "windowToolbar" || role == "applicationMenu" }

    var windowToolbar: UIElementInfo? {
        children.first { $0.role == "windowToolbar" && $0.visible }
    }
}
