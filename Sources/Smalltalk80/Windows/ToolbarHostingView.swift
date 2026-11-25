import AppKit
import SwiftUI

@MainActor
final class ToolbarHostingView: NSHostingView<AnyView> {
    private var fittedSize: NSSize?
    private var resizeScheduled = false

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }

    required init?(coder: NSCoder) { fatalError("ToolbarHostingView is created in code") }

    func update(_ content: AnyView) {
        rootView = AnyView(content.fixedSize())
        resizeToFit()
        scheduleResize()
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        // SwiftUI can invalidate its size while publishing a new snapshot.
        // Measure after that update finishes, rather than changing native
        // titlebar geometry from inside SwiftUI's layout pass.
        scheduleResize()
    }

    private func scheduleResize() {
        guard !resizeScheduled else { return }
        resizeScheduled = true
        Task { [weak self] in
            guard let self else { return }
            resizeScheduled = false
            resizeToFit()
        }
    }

    private func resizeToFit() {
        let size = fittingSize
        guard fittedSize != size else { return }
        fittedSize = size
        // AppKit may give the accessory the full titlebar height. Remember
        // the measured content size so that adjustment cannot cause a loop.
        setFrameSize(size)
    }
}
