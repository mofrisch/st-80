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
                VStack(spacing: 0) {
                    if let content = window.info.content {
                        UIElementView(controller: controller, windowID: windowID, element: content)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    if let result = window.recoveryResult {
                        Divider()
                        Text(result).font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled).padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("workspaceRecoveryResult")
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
        }.background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SnapshotWindowContentView: View {
    let content: () -> UIElementInfo?
    var isLoading: () -> Bool = { false }
    let click: (UIElementInfo) -> Void
    let select: (UIElementInfo, String) -> Void

    var body: some View {
        Group {
            if let content = content() {
                UIElementView(host: .snapshot(isLoading: isLoading(), click: click, select: select), element: content)
            } else {
                ProgressView().padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
