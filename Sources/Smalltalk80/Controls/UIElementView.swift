import SmalltalkCore
import SwiftUI

enum UIElementHost {
    case window(AppController, Int64)
    case snapshot(isLoading: Bool, click: (UIElementInfo) -> Void, select: (UIElementInfo, String) -> Void)

    var window: (controller: AppController, id: Int64)? {
        if case .window(let controller, let id) = self { return (controller, id) }
        return nil
    }

    @MainActor
    func canPerform(_ element: UIElementInfo) -> Bool {
        switch self {
        case .window(let controller, let id):
            return !controller.isRunning && controller.canPerform(element, in: id)
        case .snapshot(let isLoading, _, _):
            return !isLoading && element.enabled
        }
    }
}

struct UIElementView: View {
    let host: UIElementHost
    let element: UIElementInfo

    init(controller: AppController, windowID: Int64, element: UIElementInfo) {
        self.init(host: .window(controller, windowID), element: element)
    }

    init(host: UIElementHost, element: UIElementInfo) {
        self.host = host
        self.element = element
    }

    var body: some View {
        if element.visible {
            content
                .disabled(!host.canPerform(element))
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
        guard let (controller, windowID) = host.window else { return .constant(element.text) }
        return Binding(
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
            if let options = element.editor {
                codeEditor(options).frame(maxWidth: .infinity, minHeight: 64, maxHeight: .infinity)
            }
        case .sourceView:
            if let position = element.sourcePosition {
                PositionedSourceView(text: element.text, line: position.line, column: position.column, identifier: identifier)
            }
        case .list:
            Group {
                if element.role == "pane" {
                    list.listStyle(.bordered).controlSize(.small)
                } else {
                    list.listStyle(.sidebar)
                }
            }.accessibilityIdentifier(identifier)
        case .historyList:
            List(selection: Binding(get: { element.selection }, set: select)) {
                ForEach(element.historyEntries) { entry in
                    if element.role == "compactEntries" {
                        HStack(spacing: 6) {
                            Text(entry.title).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                            Text(entry.subtitle).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .tag(entry.id)
                        .accessibilityIdentifier(element.historyRowIdentifierPrefix.map { "\($0)-\(entry.id)" } ?? entry.id)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                            HStack {
                                Text(entry.subtitle)
                                if !entry.badge.isEmpty { Text(entry.badge).foregroundStyle(.orange) }
                            }.font(.caption)
                        }.tag(entry.id)
                    }
                }
            }.accessibilityIdentifier(identifier)
        case .valueTable:
            if let table = element.table {
                NativeValueTable(table: table, identifier: identifier, onOpen: element.readOnly ? nil : { select($0) })
            }
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
                }.accessibilityIdentifier(identifier)
            } else {
                scroll.accessibilityIdentifier(identifier)
            }
        case .menu:
            menu
        case .spacer:
            Spacer(minLength: 8)
        case .divider:
            Divider()
        }
    }

    @ViewBuilder
    private var children: some View {
        let children = element.children.filter { !$0.isWindowChrome }
        switch host {
        case .window:
            ForEach(children) { child in control(child) }
        case .snapshot:
            // The image creates new controls for each snapshot. Keep native view state at the same position.
            ForEach(children.indices, id: \.self) { index in
                control(children[index]).id(children[index].accessibilityID)
            }
        }
    }

    private func control(_ child: UIElementInfo) -> some View {
        // Type erasure bounds the recursive SwiftUI view type.
        AnyView(UIElementView(host: host, element: child))
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

    @ViewBuilder
    private func codeEditor(_ options: UIEditorInfo) -> some View {
        if let (controller, windowID) = host.window {
            NativeCodeEditor(
                text: text,
                selection: Binding(
                    get: { controller.editorSelection(windowID: windowID, elementID: element.id) },
                    set: { controller.setEditorSelection($0, windowID: windowID, elementID: element.id) }
                ),
                isEditable: !element.readOnly && element.enabled && !controller.isRunning,
                identifier: identifier,
                label: element.label,
                allowsUndo: options.undoEnabled,
                lineNumbers: options.lineNumbers,
                syntaxHighlighting: options.syntaxHighlighting,
                editingMenu: options.editingMenu,
                highlightsForSource: controller.sourceHighlights,
                contextMenuItems: controller.editorContextItems(windowID: windowID, editor: element),
                contextCommandsEnabled: element.enabled && !controller.isRunning,
                onContextCommand: { action, selection in
                    Task { await controller.performEditorContextAction(action, windowID: windowID, selection: selection) }
                }
            )
        } else {
            NativeCodeEditor(text: text, selection: .constant(NSRange()), isEditable: false, identifier: identifier,
                             label: element.label, allowsUndo: false, lineNumbers: options.lineNumbers,
                             syntaxHighlighting: false, editingMenu: options.editingMenu)
        }
    }

    private var list: some View {
        List(selection: Binding(get: { element.selection }, set: select)) {
            ForEach(element.items, id: \.self) { entry in
                Text(entry).font(.system(size: 12, design: .monospaced)).tag(entry)
            }
        }
    }

    private func select(_ value: String?) {
        switch host {
        case .window(let controller, let windowID):
            Task { await controller.selectControl(windowID: windowID, elementID: element.id, value: value) }
        case .snapshot(_, _, let select):
            if let value { select(element, value) }
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
        } else if element.role == "destructive" {
            Button(element.text, role: .destructive, action: click).accessibilityIdentifier(identifier)
        } else if let icon = element.icon {
            Button(action: click) { Label(element.text, systemImage: icon) }
                .accessibilityIdentifier(identifier)
        } else {
            Button(element.text, action: click).accessibilityIdentifier(identifier)
        }
    }

    private func click() {
        switch host {
        case .window(let controller, let windowID):
            Task { await controller.clickControl(windowID: windowID, elementID: element.id) }
        case .snapshot(_, let click, _):
            click(element)
        }
    }

    @ViewBuilder
    private var labelView: some View {
        switch element.role {
        case "heading": Text(element.text).font(.headline)
        case "caption": Text(element.text).font(.caption).foregroundStyle(.secondary)
        case "breadcrumb": Text(element.text).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
        case "pageNumber": Text(element.text).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        case "code", "document": Text(element.text).font(.system(size: 13, design: .monospaced))
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
