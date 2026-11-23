import SmalltalkCore
import SwiftUI

/// Presents the standard BrowserWindow controls from the running image.
/// The image still owns selection, edits, and every tool action.
struct ClassicBrowserView: View {
    let controller: AppController
    let windowID: Int64
    private let filter: UIElementInfo
    private let definition: UIElementInfo
    private let newMethod: UIElementInfo
    private let sides: [UIElementInfo]
    private let panes: [Pane]
    private let heading: UIElementInfo
    private let hint: UIElementInfo
    private let accept: UIElementInfo
    private let versions: UIElementInfo
    private let organizationForm: UIElementInfo
    private let editor: UIElementInfo
    private let result: UIElementInfo

    init?(controller: AppController, windowID: Int64, content: UIElementInfo) {
        // An image can mount its own BrowserWindow content. Only rearrange the
        // standard controls when the expected structure is present.
        guard content.kind == .column, content.visible,
              content.children.map(\.kind) == [.row, .divider, .split, .divider, .scroll, .divider, .row],
              StandardToolChrome.imageBar(content.children[6]) else { return nil }
        let actions = content.children[0]
        let split = content.children[2]
        let resultPane = content.children[4]
        guard actions.visible, split.visible, resultPane.visible,
              actions.children.map(\.kind) == [.textField, .spacer, .button, .button, .button, .button],
              split.role == "vertical", split.children.count == 2,
              let filter = actions.child(id: "classFilter", kind: .textField),
              actions.children.contains(where: { $0.kind == .button && $0.text == "Create Class …" }),
              actions.children.contains(where: { $0.kind == .button && $0.text == "Details" }),
              let definition = actions.child(id: "classDefinition", kind: .button),
              let newMethod = actions.child(id: "newMethod", kind: .button),
              let result = StandardToolChrome.result(in: resultPane) else { return nil }

        let navigation = split.children[0]
        let source = split.children[1]
        guard navigation.kind == .split, navigation.visible, navigation.accessibilityID == "browserNavigation",
              navigation.children.count == 4,
              source.kind == .column, source.visible,
              source.children.map(\.kind) == [.row, .divider, .column, .column, .split] else { return nil }
        let panes = navigation.children.compactMap(Pane.init)
        let toolbar = source.children[0]
        let editors = source.children[4]
        guard toolbar.visible, toolbar.children.count == 5,
              panes.map({ $0.list.accessibilityID }) == ["categoryList", "classList", "protocolList", "methodList"],
              editors.children.map(\.kind) == [.codeEditor, .scroll],
              editors.children[1].children.count == 1,
              editors.children[1].children[0].kind == .label, editors.children[1].children[0].role == "code",
              let editor = editors.child(id: "methodEditor", kind: .codeEditor),
              let sideBar = toolbar.children.first(where: { $0.kind == .row }),
              let instanceSide = sideBar.child(id: "instanceMethodSide", kind: .button),
              let classSide = sideBar.child(id: "classMethodSide", kind: .button),
              let title = toolbar.children.first(where: { $0.kind == .column }),
              let heading = title.children.first(where: { $0.kind == .label && $0.role == "heading" }),
              let hint = title.children.first(where: { $0.kind == .label && $0.role == "caption" }),
              let accept = toolbar.child(id: "executeButton", kind: .button),
              let versions = toolbar.child(id: "methodVersionsButton", kind: .button) else { return nil }

        self.controller = controller
        self.windowID = windowID
        self.filter = filter
        self.definition = definition
        self.newMethod = newMethod
        self.sides = [instanceSide, classSide]
        self.panes = panes
        self.heading = heading
        self.hint = hint
        self.accept = accept
        self.versions = versions
        self.organizationForm = source.children[3]
        self.editor = editor
        self.result = result
    }

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                navigationBar
                Divider()
                HSplitView {
                    ForEach(panes) { pane in
                        paneView(pane)
                    }
                }
                .accessibilityIdentifier("browserNavigation")
            }
            .frame(minHeight: 140, idealHeight: 190, maxHeight: 255)

            VStack(spacing: 0) {
                methodBar
                Divider()
                control(organizationForm)
                control(editor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if result.role == "error" || result.text != heading.text {
                    ToolResultView(controller: controller, windowID: windowID, result: result)
                }
            }
            .frame(minHeight: 145, maxHeight: .infinity)
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 8) {
            control(filter)
            Spacer()
            ControlGroup {
                ForEach(sides) { side in control(side) }
            }
            .fixedSize()
        }
        .controlSize(.small)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
    }

    private var methodBar: some View {
        HStack(spacing: 8) {
            control(heading).lineLimit(1)
            if hint.text == "Class Definition" || hint.text == "VM Primitive" {
                control(hint).lineLimit(1)
            }
            Spacer(minLength: 4)
            if versions.enabled {
                actionsMenu([versions], label: "Method Actions", identifier: "methodActions")
            }
            control(accept).fixedSize()
        }
        .controlSize(.small)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
    }

    private func paneView(_ pane: Pane) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                control(pane.title).lineLimit(1)
                Spacer(minLength: 2)
                if let menu = pane.menu {
                    control(menu)
                } else if pane.list.accessibilityID == "classList" {
                    control(definition).fixedSize()
                } else if pane.list.accessibilityID == "methodList" {
                    control(newMethod).fixedSize()
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 27)
            control(pane.list)
        }
        .frame(minWidth: 142, idealWidth: 180, maxWidth: .infinity, alignment: .topLeading)
    }

    private func actionsMenu(_ actions: [UIElementInfo], label: String, identifier: String) -> some View {
        Menu {
            ForEach(actions) { action in control(action) }
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel(label)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(controller.isRunning)
        .help(label)
        .accessibilityIdentifier(identifier)
    }

    private func control(_ element: UIElementInfo) -> some View {
        UIElementView(controller: controller, windowID: windowID, element: element)
    }

    private struct Pane: Identifiable {
        var id: String { list.id }
        let title: UIElementInfo
        let menu: UIElementInfo?
        let list: UIElementInfo

        init?(_ element: UIElementInfo) {
            guard element.kind == .column, element.visible, element.children.count == 2,
                  element.children[0].kind == .row, element.children[0].visible,
                  element.children[1].kind == .list else { return nil }
            let header = element.children[0].children
            guard header.map(\.kind) == [.label, .spacer] || header.map(\.kind) == [.label, .spacer, .menu] else { return nil }
            title = header[0]
            menu = header.count == 3 ? header[2] : nil
            self.list = element.children[1]
        }
    }
}

private extension UIElementInfo {
    func child(id: String, kind: UIElementKind) -> UIElementInfo? {
        children.first { $0.accessibilityID == id && $0.kind == kind }
    }
}
