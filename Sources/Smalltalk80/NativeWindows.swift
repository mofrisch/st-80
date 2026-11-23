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
    private let onEvent: (NativeWindowEvent) -> Void
    private var entries: [Int64: Entry] = [:]
    private var applying = false
    private var epoch = ""
    private var revision: Int64 = 0
    private var sequence: Int64 = 0
    private var focusRequest: Int64 = 0
    private var latestFocusEvent: Int64 = 0
    private var screenObserver: NSObjectProtocol?

    init(content: @escaping (Int64) -> AnyView, onEvent: @escaping (NativeWindowEvent) -> Void) {
        self.content = content; self.onEvent = onEvent
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    func execute(_ batch: WindowCommandBatch) {
        if batch.epoch != epoch { startEpoch(batch.epoch) }
        guard batch.revision > revision else { return }
        revision = batch.revision
        applying = true
        var acknowledgements = Acknowledgements()
        for command in batch.commands {
            switch command {
            case .retain(let ids): retainWindows(ids)
            case .present(let info):
                present(info, after: batch.acknowledgedEvent, acknowledging: &acknowledgements)
            case .order(let ids, let active, let request):
                orderWindows(ids, active: active, request: request, after: batch.acknowledgedEvent)
            }
        }
        applying = false
        for event in acknowledgements.frames { emit(event) }
        for event in acknowledgements.states { emit(event) }
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
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let window = NSWindow(contentRect: NSWindow.contentRect(forFrameRect: rect(info.frame), styleMask: style), styleMask: style, backing: .buffered, defer: false)
        window.title = info.title
        window.identifier = NSUserInterfaceItemIdentifier("toolWindow-\(info.id)")
        window.setAccessibilityIdentifier("toolWindow-\(info.id)")
        window.setAccessibilityLabel(info.title)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.animationBehavior = .documentWindow
        window.contentViewController = NSHostingController(rootView: content(info.id))
        let delegate = WindowDelegate(id: info.id, backend: self)
        window.delegate = delegate
        NSApp.addWindowsItem(window, title: info.title, filename: false)
        return Entry(window: window, delegate: delegate, identity: info.identity)
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
