import AppKit
import SmalltalkCore
import SwiftUI

/// Presents the language's persistent window objects as ordinary macOS windows.
/// Smalltalk remains the owner of window lifetime and saved geometry.
@MainActor
final class NativeWindowManager {
    @MainActor
    private final class Entry {
        let controller: NSWindowController
        let delegate: WindowDelegate
        var modelFrame: NSRect
        var observedFrame: NSRect
        var modelMinimized: Bool

        var window: NSWindow { controller.window! }

        init(controller: NSWindowController, delegate: WindowDelegate, modelFrame: NSRect, observedFrame: NSRect, minimized: Bool) {
            self.controller = controller
            self.delegate = delegate
            self.modelFrame = modelFrame
            self.observedFrame = observedFrame
            modelMinimized = minimized
        }
    }

    private let content: (Int64) -> AnyView
    private let onActivate: (Int64) -> Void
    private let onClose: (Int64) -> Void
    private let onFrame: (Int64, NSRect) -> Void
    private let onMinimize: (Int64, Bool) -> Void
    private var entries: [Int64: Entry] = [:]
    private var isSynchronizing = false
    private var activeID: Int64?
    private var orderIDs: [Int64] = []

    init(
        content: @escaping (Int64) -> AnyView,
        onActivate: @escaping (Int64) -> Void,
        onClose: @escaping (Int64) -> Void,
        onFrame: @escaping (Int64, NSRect) -> Void,
        onMinimize: @escaping (Int64, Bool) -> Void
    ) {
        self.content = content
        self.onActivate = onActivate
        self.onClose = onClose
        self.onFrame = onFrame
        self.onMinimize = onMinimize
    }

    func synchronize(_ windows: [ToolWindowInfo], activeID requestedActiveID: Int64?) {
        isSynchronizing = true
        defer { isSynchronizing = false }

        let desiredIDs = Set(windows.map(\.id))
        for id in Array(entries.keys) where !desiredIDs.contains(id) {
            removeWindow(id)
        }

        var newIDs: Set<Int64> = []
        // The supplied list is ordered back-to-front by the Smalltalk manager.
        for info in windows {
            let modelFrame = frame(from: info)
            let entry: Entry
            if let existing = entries[info.id] {
                entry = existing
                let minimum = minimumSize(for: info.kind)
                let minimumChanged = entry.window.minSize != minimum
                if minimumChanged { entry.window.minSize = minimum }
                // A native drag may already be ahead of the asynchronously
                // returned model. Only apply a genuinely new model rectangle.
                if entry.modelFrame != modelFrame || minimumChanged {
                    entry.modelFrame = modelFrame
                    let restored = visibleFrame(modelFrame, minimum: minimum)
                    entry.observedFrame = restored
                    if !nearlyEqual(entry.window.frame, restored) {
                        entry.window.setFrame(restored, display: true)
                    }
                }
            } else {
                entry = makeWindow(info, modelFrame: modelFrame)
                entries[info.id] = entry
                newIDs.insert(info.id)
                entry.window.orderFront(nil)
            }

            if entry.window.title != info.title {
                entry.window.title = info.title
                entry.window.setAccessibilityLabel(info.title)
                NSApp.changeWindowsItem(entry.window, title: info.title, filename: false)
            }
            if entry.modelMinimized != info.minimized || newIDs.contains(info.id) {
                entry.modelMinimized = info.minimized
                if info.minimized && !entry.window.isMiniaturized {
                    entry.window.miniaturize(nil)
                } else if !info.minimized && entry.window.isMiniaturized {
                    entry.window.deminiaturize(nil)
                }
            }
        }

        let requestedOrder = windows.map(\.id)
        if requestedOrder != orderIDs {
            for id in requestedOrder {
                if let entry = entries[id], !entry.window.isMiniaturized {
                    entry.window.orderFront(nil)
                }
            }
            orderIDs = requestedOrder
            if let id = requestedActiveID, let entry = entries[id], entry.window.isKeyWindow {
                entry.window.orderFront(nil)
            }
        }

        let shouldActivate = requestedActiveID != activeID || requestedActiveID.map(newIDs.contains) == true
        activeID = requestedActiveID
        if shouldActivate, let id = requestedActiveID, let entry = entries[id], !entry.modelMinimized, !entry.window.isKeyWindow {
            entry.window.makeKeyAndOrderFront(nil)
        }
    }

    /// Captures actual native geometry, including windows currently minimized.
    func captureFrames() -> [Int64: NSRect] {
        entries.mapValues { $0.window.frame }
    }

    /// Used for application teardown; it does not send language close messages.
    func closeAll() {
        isSynchronizing = true
        defer { isSynchronizing = false }
        for id in Array(entries.keys) { removeWindow(id) }
        activeID = nil
        orderIDs = []
    }

    private func makeWindow(_ info: ToolWindowInfo, modelFrame: NSRect) -> Entry {
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let minimum = minimumSize(for: info.kind)
        let restored = visibleFrame(modelFrame, minimum: minimum)
        // Give SwiftUI a valid content area during its very first layout pass.
        let contentRect = NSWindow.contentRect(forFrameRect: restored, styleMask: styleMask)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = info.title
        window.identifier = NSUserInterfaceItemIdentifier("toolWindow-\(info.id)")
        window.setAccessibilityIdentifier("toolWindow-\(info.id)")
        window.setAccessibilityLabel(info.title)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.animationBehavior = .documentWindow
        window.minSize = minimum
        window.contentViewController = NSHostingController(rootView: content(info.id))

        window.setFrame(restored, display: false)
        let delegate = WindowDelegate(id: info.id, manager: self)
        window.delegate = delegate
        let controller = NSWindowController(window: window)
        NSApp.addWindowsItem(window, title: info.title, filename: false)
        return Entry(controller: controller, delegate: delegate, modelFrame: modelFrame, observedFrame: window.frame, minimized: info.minimized)
    }

    private func removeWindow(_ id: Int64) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.window.delegate = nil
        NSApp.removeWindowsItem(entry.window)
        entry.window.close()
    }

    private func frame(from info: ToolWindowInfo) -> NSRect {
        NSRect(x: CGFloat(info.x), y: CGFloat(info.y), width: CGFloat(info.width), height: CGFloat(info.height))
    }

    private func minimumSize(for kind: ToolKind) -> NSSize {
        switch kind {
        case .workspace: NSSize(width: 480, height: 320)
        case .browser: NSSize(width: 750, height: 500)
        case .transcript: NSSize(width: 400, height: 200)
        }
    }

    private func visibleFrame(_ proposed: NSRect, minimum: NSSize) -> NSRect {
        let screens = NSScreen.screens.map(\.visibleFrame)
        guard !screens.isEmpty else {
            return NSRect(x: proposed.minX, y: proposed.minY, width: max(minimum.width, proposed.width), height: max(minimum.height, proposed.height))
        }
        // Keep a saved window on the display containing most of it. A removed
        // display falls back to the closest currently available screen.
        let visible = screens.max { first, second in
            let firstArea = intersectionArea(first, proposed)
            let secondArea = intersectionArea(second, proposed)
            if firstArea != secondArea { return firstArea < secondArea }
            return distanceSquared(first, proposed) > distanceSquared(second, proposed)
        }!
        let width = min(visible.width, max(minimum.width, proposed.width))
        let height = min(visible.height, max(minimum.height, proposed.height))
        return NSRect(
            x: min(max(proposed.minX, visible.minX), visible.maxX - width),
            y: min(max(proposed.minY, visible.minY), visible.maxY - height),
            width: width,
            height: height
        )
    }

    private func intersectionArea(_ first: NSRect, _ second: NSRect) -> CGFloat {
        let intersection = first.intersection(second)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private func distanceSquared(_ first: NSRect, _ second: NSRect) -> CGFloat {
        let dx = first.midX - second.midX
        let dy = first.midY - second.midY
        return dx * dx + dy * dy
    }

    private func nearlyEqual(_ first: NSRect, _ second: NSRect) -> Bool {
        abs(first.minX - second.minX) < 0.5 && abs(first.minY - second.minY) < 0.5
            && abs(first.width - second.width) < 0.5 && abs(first.height - second.height) < 0.5
    }

    private func becameKey(_ id: Int64) {
        guard !isSynchronizing, entries[id] != nil else { return }
        onActivate(id)
    }

    private func geometryChanged(_ id: Int64) {
        guard !isSynchronizing, let entry = entries[id] else { return }
        let actual = entry.window.frame
        guard !nearlyEqual(actual, entry.observedFrame) else { return }
        entry.observedFrame = actual
        onFrame(id, actual)
    }

    private func minimized(_ id: Int64, _ minimized: Bool) {
        guard !isSynchronizing, entries[id] != nil else { return }
        onMinimize(id, minimized)
    }

    @MainActor
    private final class WindowDelegate: NSObject, NSWindowDelegate {
        let id: Int64
        weak var manager: NativeWindowManager?

        init(id: Int64, manager: NativeWindowManager) {
            self.id = id
            self.manager = manager
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard let manager, !manager.isSynchronizing else { return true }
            // Let Smalltalk accept the close before removing its native window.
            manager.onClose(id)
            return false
        }

        func windowDidBecomeKey(_ notification: Notification) { manager?.becameKey(id) }
        func windowDidMove(_ notification: Notification) { manager?.geometryChanged(id) }
        func windowDidResize(_ notification: Notification) { manager?.geometryChanged(id) }
        func windowDidEndLiveResize(_ notification: Notification) { manager?.geometryChanged(id) }
        func windowDidMiniaturize(_ notification: Notification) { manager?.minimized(id, true) }
        func windowDidDeminiaturize(_ notification: Notification) { manager?.minimized(id, false) }
    }
}
