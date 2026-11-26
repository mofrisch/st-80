import SmalltalkCore
import SwiftUI

struct WindowToolbarView: View {
    let controller: AppController
    let windowID: Int64

    var body: some View {
        if let window = controller.presentedWindow(windowID)?.info, let toolbar = window.content?.windowToolbar {
            HStack(spacing: 5) {
                UIElementView(controller: controller, windowID: windowID, element: toolbar)
                if controller.workspaceExecution?.windowID == windowID, let stop = controller.workspaceStop {
                    UIElementView(host: .snapshot(isLoading: false, click: { _ in controller.stopWorkspaceExecution() },
                                                  select: { _, _ in }), element: stop)
                } else if controller.canRunWorkspaceWithBudget(in: window), let menu = controller.workspaceBudgets {
                    UIElementView(host: .snapshot(isLoading: controller.isRunning, click: { item in
                        Task { await controller.runWorkspaceWithBudget(item.command, windowID: windowID) }
                    }, select: { _, _ in }), element: menu)
                }
            }
            .controlSize(.small)
            .fixedSize()
        }
    }
}

struct ToolContentView: View {
    @Bindable var controller: AppController
    let windowID: Int64
    @State private var feedbackContent: (request: ToolWindowFeedback, content: UIElementInfo)?

    var body: some View {
        Group {
            if let window = controller.presentedWindow(windowID) {
                let feedback = ToolWindowFeedback(
                    recoveryResult: window.recoveryResult,
                    inputError: window.inputError,
                    activeError: controller.activeWindowID == windowID ? controller.error : nil,
                    displayedResult: window.info.content?.firstVisible { $0.accessibilityID == "evaluationResult" }?.text
                )
                VStack(spacing: 0) {
                    if let content = window.info.content {
                        UIElementView(controller: controller, windowID: windowID, element: content)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    if let feedbackContent, feedbackContent.request == feedback {
                        UIElementView(host: .snapshot(isLoading: false, click: { _ in }, select: { _, _ in }),
                                      element: feedbackContent.content)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .task(id: feedback) {
                    guard let feedback else { feedbackContent = nil; return }
                    let content = await SmalltalkSession.toolWindowFeedback(feedback)
                    guard !Task.isCancelled else { return }
                    feedbackContent = content.map { (feedback, $0) }
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
