import AppKit
import SmalltalkCore
import SwiftUI

struct NativeVerticalSplit: NSViewControllerRepresentable {
    let host: UIElementHost
    let identifier: String
    let panes: [UIElementInfo]

    final class Coordinator {
        var paneIDs: [String] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = VerticalSplitController()
        let split = controller.splitView
        split.isVertical = false
        split.dividerStyle = .thin
        return controller
    }

    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        controller.splitView.setAccessibilityIdentifier(identifier)
        let previous = Dictionary(uniqueKeysWithValues: zip(context.coordinator.paneIDs, controller.splitViewItems))
        let items = panes.map { pane in
            let content = AnyView(UIElementView(host: host, element: pane)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
            let item: NSSplitViewItem
            if let existing = previous[pane.id], let hosting = existing.viewController as? NSHostingController<AnyView> {
                hosting.rootView = content
                item = existing
            } else {
                let hosting = NSHostingController(rootView: content)
                hosting.sizingOptions = []
                item = NSSplitViewItem(viewController: hosting)
            }
            let minimum = pane.minimumHeight.map { CGFloat($0) } ?? NSSplitViewItem.unspecifiedDimension
            let maximum = pane.maximumHeight.map { CGFloat($0) } ?? NSSplitViewItem.unspecifiedDimension
            if item.minimumThickness != minimum { item.minimumThickness = minimum }
            if item.maximumThickness != maximum { item.maximumThickness = maximum }
            return item
        }
        let ids = panes.map(\.id)
        if context.coordinator.paneIDs != ids {
            controller.splitViewItems = items
            context.coordinator.paneIDs = ids
        }
    }
}

private final class VerticalSplitController: NSSplitViewController {
    override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect,
                            forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        let effectiveRect = super.splitView(splitView, effectiveRect: proposedEffectiveRect,
                                            forDrawnRect: drawnRect, ofDividerAt: dividerIndex)
        guard !effectiveRect.isEmpty else { return effectiveRect }
        // Keep the visible line thin while allowing clicks just above and below it.
        let grabArea = NSRect(x: drawnRect.minX, y: drawnRect.midY - 7.5,
                              width: drawnRect.width, height: 15)
        return effectiveRect.union(grabArea)
    }
}
