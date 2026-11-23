import SmalltalkCore
import SwiftUI

struct UserInterfaceView: View {
    @Bindable var controller: AppController
    @Bindable var state: ToolWindowState

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView {
                    if let content = state.content {
                        UIElementView(controller: controller, windowID: state.id, element: content)
                            .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let error = state.error {
                Divider()
                Text(error).font(.callout).foregroundStyle(.red)
                    .textSelection(.enabled).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct UIElementView: View {
    @Bindable var controller: AppController
    let windowID: Int64
    let element: UIElementInfo

    var body: some View {
        elementContent
            .disabled(!element.enabled || controller.isRunning)
    }

    @ViewBuilder
    private var elementContent: some View {
        switch element.kind {
        case .label:
            Text(element.text).textSelection(.enabled)
                .accessibilityIdentifier("ui-\(element.id)")
        case .button:
            Button(element.text) {
                Task { await controller.clickControl(windowID: windowID, elementID: element.id) }
            }
            .accessibilityIdentifier("ui-\(element.id)")
        case .textField:
            VStack(alignment: .leading, spacing: 4) {
                if !element.label.isEmpty { Text(element.label).font(.callout) }
                TextField(element.placeholder, text: Binding(
                    get: { controller.inputText(windowID: windowID, element: element) },
                    set: { controller.editInput(windowID: windowID, elementID: element.id, text: $0) }
                ))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(element.label.isEmpty ? element.placeholder : element.label)
                .accessibilityIdentifier("ui-\(element.id)")
            }
        case .column:
            VStack(alignment: .leading, spacing: CGFloat(element.spacing)) {
                ForEach(element.children) { child in
                    // Type erasure bounds SwiftUI's recursive view type.
                    AnyView(UIElementView(controller: controller, windowID: windowID, element: child))
                }
            }.padding(CGFloat(element.padding))
        case .row:
            HStack(alignment: .top, spacing: CGFloat(element.spacing)) {
                ForEach(element.children) { child in
                    AnyView(UIElementView(controller: controller, windowID: windowID, element: child))
                }
            }.padding(CGFloat(element.padding))
        case .spacer:
            Spacer(minLength: 8)
        }
    }
}
