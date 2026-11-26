import AppKit
import SmalltalkCore
import SwiftUI

/// Only native mechanics live here. The .st library owns sizes, display choice,
/// placement, lifetime, activation policy and restoration.
@MainActor
final class NativeWindowBackend {
    @MainActor
    private final class Entry {
        let window: NSWindow
        let delegate: WindowDelegate
        let identity: String
        var observedFrame: NSRect
        var frameRequest: Int64 = 0
        var stateRequest: Int64 = 0
        var latestFrameEvent: Int64 = 0
        var latestStateEvent: Int64 = 0
        var titlebarAccessory: NSTitlebarAccessoryViewController?

        init(window: NSWindow, delegate: WindowDelegate, identity: String) {
            self.window = window
            self.delegate = delegate
            self.identity = identity
            observedFrame = window.frame
        }
    }

    private struct Acknowledgements {
        var frames: [NativeWindowEvent.Kind] = []
        var states: [NativeWindowEvent.Kind] = []
    }

    private let content: (Int64) -> AnyView
    private let toolbar: (ToolWindowInfo) -> AnyView?
    private let onEvent: (NativeWindowEvent) -> Void
    private var entries: [Int64: Entry] = [:]
    private var transientWindows: [UUID: (window: NSWindow, delegate: TransientWindowDelegate)] = [:]
    private let windowStyle: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
    private var applying = false
    private var epoch = ""
    private var revision: Int64 = 0
    private var sequence: Int64 = 0
    private var focusRequest: Int64 = 0
    private var latestFocusEvent: Int64 = 0
    private var screenObserver: NSObjectProtocol?

    init(content: @escaping (Int64) -> AnyView, toolbar: @escaping (ToolWindowInfo) -> AnyView?,
         onEvent: @escaping (NativeWindowEvent) -> Void) {
        self.content = content
        self.toolbar = toolbar
        self.onEvent = onEvent
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    func execute(_ batch: WindowCommandBatch, preservingWindows: Bool = false,
                 recoveryWorkspace: ToolWindowInfo? = nil) {
        if batch.epoch != epoch { startEpoch(batch.epoch) }
        guard batch.revision > revision else { return }
        revision = batch.revision
        applying = true
        var acknowledgements = Acknowledgements()
        for command in batch.commands {
            if preservingWindows { continue }
            switch command {
            case .retain(let ids): retainWindows(ids)
            case .present(let info):
                present(info, after: batch.acknowledgedEvent, acknowledging: &acknowledgements)
            case .order(let ids, let active, let request):
                orderWindows(ids, active: active, request: request, after: batch.acknowledgedEvent)
            }
        }
        if preservingWindows, let recoveryWorkspace, entries[recoveryWorkspace.id] == nil {
            present(recoveryWorkspace, after: batch.acknowledgedEvent, acknowledging: &acknowledgements)
            entries[recoveryWorkspace.id]?.window.makeKeyAndOrderFront(nil)
        }
        applying = false
        for event in acknowledgements.frames { emit(event) }
        for event in acknowledgements.states { emit(event) }
    }

    func activateWindowForRecovery(_ id: Int64, identity: String) {
        guard let entry = entries[id], entry.identity == identity else { return }
        if entry.window.isMiniaturized { entry.window.deminiaturize(nil) }
        entry.window.makeKeyAndOrderFront(nil)
    }

    func showTransientWindow(_ id: UUID, info: TransientWindowInfo, content: AnyView,
                             onKeyChange: ((Bool) -> Void)? = nil, onClose: (() -> Void)? = nil) {
        let window = makeWindow(contentRect: NSRect(x: 0, y: 0, width: CGFloat(info.width), height: CGFloat(info.height)),
                                title: info.title, identifier: info.identifier)
        window.identifier = NSUserInterfaceItemIdentifier("\(info.identifier)-\(id.uuidString)")
        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.contentMinSize = NSSize(width: CGFloat(info.minimumWidth), height: CGFloat(info.minimumHeight))
        window.setContentSize(NSSize(width: CGFloat(info.width), height: CGFloat(info.height)))
        window.center()
        let delegate = TransientWindowDelegate(onKeyChange: onKeyChange) { [weak self] in
            self?.removeTransientWindow(id, close: false)
            onClose?()
        }
        window.delegate = delegate
        transientWindows[id] = (window, delegate)
        window.makeKeyAndOrderFront(nil)
    }

    @discardableResult
    func activateTransientWindow(_ id: UUID) -> Bool {
        guard let window = transientWindows[id]?.window else { return false }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func closeTransientWindow(_ id: UUID) { removeTransientWindow(id, close: true) }

    private func removeTransientWindow(_ id: UUID, close: Bool) {
        guard let entry = transientWindows.removeValue(forKey: id) else { return }
        entry.window.delegate = nil
        NSApp.removeWindowsItem(entry.window)
        if close { entry.window.close() }
    }

    private func startEpoch(_ newEpoch: String) {
        applying = true
        for id in Array(entries.keys) { remove(id) }
        applying = false
        epoch = newEpoch
        revision = 0
        sequence = 0
        focusRequest = 0
        latestFocusEvent = 0
        screensChanged()
    }

    private func retainWindows(_ ids: [Int64]) {
        let desired = Set(ids)
        for id in Array(entries.keys) where !desired.contains(id) { remove(id) }
    }

    private func present(_ info: ToolWindowInfo, after event: Int64, acknowledging acknowledgements: inout Acknowledgements) {
        if let old = entries[info.id], old.identity != info.identity {
            remove(info.id)
            focusRequest = 0
        }
        let existing = entries[info.id]
        let entry = existing ?? makeWindow(info)
        let isNew = existing == nil
        if isNew { entries[info.id] = entry }

        updateTitle(of: entry.window, to: info.title)
        updateTitlebar(for: entry, info: info)
        if isNew || (entry.frameRequest != info.frameRevision && entry.latestFrameEvent <= event) {
            applyFrame(info, to: entry)
            acknowledgements.frames.append(.frameApplied(info.id, request: info.frameRevision, facts(entry.observedFrame)))
        }
        if isNew || (entry.stateRequest != info.stateRevision && entry.latestStateEvent <= event) {
            applyMinimization(info, to: entry)
            if entry.window.isMiniaturized != info.minimized {
                acknowledgements.states.append(.minimized(info.id, entry.window.isMiniaturized))
            }
        }
        if isNew && !info.minimized { entry.window.orderFront(nil) }
    }

    private func updateTitlebar(for entry: Entry, info: ToolWindowInfo) {
        if let content = toolbar(info) {
            if let host = entry.titlebarAccessory?.view as? ToolbarHostingView {
                host.update(content)
                return
            }
            let host = ToolbarHostingView(rootView: AnyView(content.fixedSize()))
            host.update(content)
            let accessory = NSTitlebarAccessoryViewController()
            accessory.layoutAttribute = .right
            accessory.view = host
            entry.window.addTitlebarAccessoryViewController(accessory)
            entry.titlebarAccessory = accessory
        } else if let accessory = entry.titlebarAccessory,
                  let index = entry.window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === accessory }) {
            entry.window.removeTitlebarAccessoryViewController(at: index)
            entry.titlebarAccessory = nil
        }
    }

    private func updateTitle(of window: NSWindow, to title: String) {
        guard window.title != title else { return }
        window.title = title
        window.setAccessibilityLabel(title)
        NSApp.changeWindowsItem(window, title: title, filename: false)
    }

    private func applyFrame(_ info: ToolWindowInfo, to entry: Entry) {
        let window = entry.window
        window.minSize = NSSize(width: CGFloat(info.minimumWidth), height: CGFloat(info.minimumHeight))
        window.maxSize = NSSize(width: CGFloat(info.maximumWidth), height: CGFloat(info.maximumHeight))
        let frame = rect(info.frame)
        if !nearlyEqual(window.frame, frame) { window.setFrame(frame, display: true) }
        entry.frameRequest = info.frameRevision
        entry.observedFrame = window.frame
    }

    private func applyMinimization(_ info: ToolWindowInfo, to entry: Entry) {
        let window = entry.window
        if info.minimized && !window.isMiniaturized { window.miniaturize(nil) }
        if !info.minimized && window.isMiniaturized { window.deminiaturize(nil) }
        entry.stateRequest = info.stateRevision
    }

    private func orderWindows(_ ids: [Int64], active: Int64?, request: Int64, after event: Int64) {
        guard request != focusRequest, latestFocusEvent <= event else { return }
        for id in ids {
            if let entry = entries[id], !entry.window.isMiniaturized { entry.window.orderFront(nil) }
        }
        if let id = active, let entry = entries[id], !entry.window.isMiniaturized {
            entry.window.makeKeyAndOrderFront(nil)
        }
        focusRequest = request
    }

    /// Snapshot actual platform facts before an interpreter command or save.
    func captureGeometry() {
        for id in Array(entries.keys) { geometryChanged(id) }
    }

    private func emit(_ kind: NativeWindowEvent.Kind) {
        guard !epoch.isEmpty else { return }
        sequence += 1
        let id: Int64?
        switch kind {
        case .frame(let windowID, _):
            id = windowID
            entries[windowID]?.latestFrameEvent = sequence
        case .minimized(let windowID, _):
            id = windowID
            entries[windowID]?.latestStateEvent = sequence
        case .activated(let windowID):
            id = windowID
            latestFocusEvent = sequence
        case .frameApplied(let windowID, _, _), .closeRequested(let windowID):
            id = windowID
        case .screens:
            id = nil
        }
        onEvent(NativeWindowEvent(epoch: epoch, sequence: sequence, kind: kind, windowIdentity: id.flatMap { entries[$0]?.identity }))
    }

    private func screensChanged() {
        let screens = NSScreen.screens.map { screen in
            ScreenInfo(id: String(describing: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? screen.localizedName), frame: facts(screen.visibleFrame))
        }
        emit(.screens(screens))
    }

    private func makeWindow(_ info: ToolWindowInfo) -> Entry {
        let contentRect = NSWindow.contentRect(forFrameRect: rect(info.frame), styleMask: windowStyle)
        let window = makeWindow(contentRect: contentRect, title: info.title, identifier: "toolWindow-\(info.id)")
        window.animationBehavior = .documentWindow
        window.contentViewController = NSHostingController(rootView: content(info.id))
        let delegate = WindowDelegate(id: info.id, backend: self)
        window.delegate = delegate
        return Entry(window: window, delegate: delegate, identity: info.identity)
    }

    private func makeWindow(contentRect: NSRect, title: String, identifier: String) -> NSWindow {
        let window = NSWindow(contentRect: contentRect, styleMask: windowStyle, backing: .buffered, defer: false)
        window.title = title
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        window.setAccessibilityIdentifier(identifier)
        window.setAccessibilityLabel(title)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        NSApp.addWindowsItem(window, title: title, filename: false)
        return window
    }
    private func remove(_ id: Int64) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.window.delegate = nil
        NSApp.removeWindowsItem(entry.window)
        entry.window.close()
    }
    private func rect(_ frame: WindowRect) -> NSRect { NSRect(x: CGFloat(frame.x), y: CGFloat(frame.y), width: CGFloat(frame.width), height: CGFloat(frame.height)) }
    private func facts(_ rect: NSRect) -> WindowRect { WindowRect(x: Int64(rect.minX.rounded()), y: Int64(rect.minY.rounded()), width: Int64(rect.width.rounded()), height: Int64(rect.height.rounded())) }
    private func nearlyEqual(_ a: NSRect, _ b: NSRect) -> Bool { abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5 }
    private func geometryChanged(_ id: Int64) {
        guard !applying, let entry = entries[id], !nearlyEqual(entry.window.frame, entry.observedFrame) else { return }
        entry.observedFrame = entry.window.frame
        emit(.frame(id, facts(entry.observedFrame)))
    }

    @MainActor
    private final class TransientWindowDelegate: NSObject, NSWindowDelegate {
        let onKeyChange: ((Bool) -> Void)?
        let onClose: () -> Void

        init(onKeyChange: ((Bool) -> Void)?, onClose: @escaping () -> Void) {
            self.onKeyChange = onKeyChange
            self.onClose = onClose
        }

        func windowDidBecomeKey(_ notification: Notification) { onKeyChange?(true) }
        func windowDidResignKey(_ notification: Notification) { onKeyChange?(false) }
        func windowWillClose(_ notification: Notification) { onClose() }
    }

    @MainActor
    private final class WindowDelegate: NSObject, NSWindowDelegate {
        let id: Int64
        weak var backend: NativeWindowBackend?
        init(id: Int64, backend: NativeWindowBackend) {
            self.id = id
            self.backend = backend
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard let backend, !backend.applying else { return true }
            backend.emit(.closeRequested(id))
            return false
        }
        func windowDidBecomeKey(_ notification: Notification) { if backend?.applying == false { backend?.emit(.activated(id)) } }
        func windowDidMove(_ notification: Notification) { backend?.geometryChanged(id) }
        func windowDidResize(_ notification: Notification) { backend?.geometryChanged(id) }
        func windowDidEndLiveResize(_ notification: Notification) { backend?.geometryChanged(id) }
        func windowDidMiniaturize(_ notification: Notification) { if backend?.applying == false { backend?.emit(.minimized(id, true)) } }
        func windowDidDeminiaturize(_ notification: Notification) { if backend?.applying == false { backend?.emit(.minimized(id, false)) } }
    }
}
