import AppKit
import SmalltalkCore
import SwiftUI

/// Only native mechanics live here. The .st library owns sizes, display choice,
/// placement, lifetime, activation policy and restoration.
@MainActor
final class NativeWindowBackend {
    @MainActor
    private final class Entry {
        let controller: NSWindowController
        let delegate: WindowDelegate
        let identity: String
        var window: NSWindow { controller.window! }
        var observedFrame: NSRect
        var frameRequest: Int64 = 0
        var stateRequest: Int64 = 0
        var latestFrameEvent: Int64 = 0
        var latestStateEvent: Int64 = 0
        init(_ controller: NSWindowController, _ delegate: WindowDelegate, identity: String) {
            self.controller = controller; self.delegate = delegate; self.identity = identity; observedFrame = controller.window!.frame
        }
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
        if batch.epoch != epoch {
            closeAll()
            epoch = batch.epoch; revision = 0; sequence = 0; focusRequest = 0; latestFocusEvent = 0
            screensChanged()
        }
        guard batch.revision > revision else { return }
        revision = batch.revision; applying = true
        var appliedFrames: [(Int64, Int64, WindowRect)] = []
        var appliedStates: [(Int64, Bool)] = []
        for command in batch.commands {
            switch command {
            case .retain(let ids):
                let desired = Set(ids)
                for id in Array(entries.keys) where !desired.contains(id) { remove(id) }
            case .present(let info):
                if let old = entries[info.id], old.identity != info.identity { remove(info.id); focusRequest = 0 }
                let isNew = entries[info.id] == nil
                let entry: Entry
                if let current = entries[info.id] { entry = current }
                else { entry = makeWindow(info); entries[info.id] = entry }
                if entry.window.title != info.title {
                    entry.window.title = info.title; entry.window.setAccessibilityLabel(info.title)
                    NSApp.changeWindowsItem(entry.window, title: info.title, filename: false)
                }
                if isNew || (entry.frameRequest != info.frameRevision && entry.latestFrameEvent <= batch.acknowledgedEvent) {
                    entry.window.minSize = NSSize(width: CGFloat(info.minimumWidth), height: CGFloat(info.minimumHeight))
                    entry.window.maxSize = NSSize(width: CGFloat(info.maximumWidth), height: CGFloat(info.maximumHeight))
                    let frame = rect(info.frame)
                    if !nearlyEqual(entry.window.frame, frame) { entry.window.setFrame(frame, display: true) }
                    entry.frameRequest = info.frameRevision; entry.observedFrame = entry.window.frame
                    appliedFrames.append((info.id, info.frameRevision, facts(entry.window.frame)))
                }
                if isNew || (entry.stateRequest != info.stateRevision && entry.latestStateEvent <= batch.acknowledgedEvent) {
                    if info.minimized && !entry.window.isMiniaturized { entry.window.miniaturize(nil) }
                    if !info.minimized && entry.window.isMiniaturized { entry.window.deminiaturize(nil) }
                    entry.stateRequest = info.stateRevision
                    if entry.window.isMiniaturized != info.minimized { appliedStates.append((info.id, entry.window.isMiniaturized)) }
                }
                if isNew && !info.minimized { entry.window.orderFront(nil) }
            case .order(let ids, let active, let request):
                guard request != focusRequest, latestFocusEvent <= batch.acknowledgedEvent else { continue }
                for id in ids { if let entry = entries[id], !entry.window.isMiniaturized { entry.window.orderFront(nil) } }
                if let id = active, let entry = entries[id], !entry.window.isMiniaturized { entry.window.makeKeyAndOrderFront(nil) }
                focusRequest = request
            }
        }
        applying = false
        for (id, request, frame) in appliedFrames { emit(.frameApplied(id, request: request, frame)) }
        for (id, minimized) in appliedStates { emit(.minimized(id, minimized)) }
    }

    /// Snapshot actual platform facts before an interpreter command or save.
    func captureGeometry() { for id in Array(entries.keys) { geometryChanged(id) } }

    func closeAll() {
        applying = true
        for id in Array(entries.keys) { remove(id) }
        applying = false
    }

    private func emit(_ kind: NativeWindowEvent.Kind) {
        guard !epoch.isEmpty else { return }
        sequence += 1
        switch kind {
        case .frame(let id, _): entries[id]?.latestFrameEvent = sequence
        case .minimized(let id, _): entries[id]?.latestStateEvent = sequence
        case .activated: latestFocusEvent = sequence
        default: break
        }
        let id: Int64?
        switch kind {
        case .frame(let value, _), .frameApplied(let value, _, _), .minimized(let value, _), .activated(let value), .closeRequested(let value): id = value
        case .screens: id = nil
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
        window.setAccessibilityIdentifier("toolWindow-\(info.id)"); window.setAccessibilityLabel(info.title)
        window.isReleasedWhenClosed = false; window.isRestorable = false; window.tabbingMode = .disallowed
        window.animationBehavior = .documentWindow
        window.contentViewController = NSHostingController(rootView: content(info.id))
        let delegate = WindowDelegate(id: info.id, backend: self); window.delegate = delegate
        NSApp.addWindowsItem(window, title: info.title, filename: false)
        return Entry(NSWindowController(window: window), delegate, identity: info.identity)
    }
    private func remove(_ id: Int64) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.window.delegate = nil; NSApp.removeWindowsItem(entry.window); entry.window.close()
    }
    private func rect(_ frame: WindowRect) -> NSRect { NSRect(x: CGFloat(frame.x), y: CGFloat(frame.y), width: CGFloat(frame.width), height: CGFloat(frame.height)) }
    private func facts(_ rect: NSRect) -> WindowRect { WindowRect(x: Int64(rect.minX.rounded()), y: Int64(rect.minY.rounded()), width: Int64(rect.width.rounded()), height: Int64(rect.height.rounded())) }
    private func nearlyEqual(_ a: NSRect, _ b: NSRect) -> Bool { abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5 }
    private func geometryChanged(_ id: Int64) {
        guard !applying, let entry = entries[id], !nearlyEqual(entry.window.frame, entry.observedFrame) else { return }
        entry.observedFrame = entry.window.frame; emit(.frame(id, facts(entry.window.frame)))
    }

    @MainActor
    private final class WindowDelegate: NSObject, NSWindowDelegate {
        let id: Int64
        weak var backend: NativeWindowBackend?
        init(id: Int64, backend: NativeWindowBackend) { self.id = id; self.backend = backend }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard let backend, !backend.applying else { return true }
            backend.emit(.closeRequested(id)); return false
        }
        func windowDidBecomeKey(_ notification: Notification) { if backend?.applying == false { backend?.emit(.activated(id)) } }
        func windowDidMove(_ notification: Notification) { backend?.geometryChanged(id) }
        func windowDidResize(_ notification: Notification) { backend?.geometryChanged(id) }
        func windowDidEndLiveResize(_ notification: Notification) { backend?.geometryChanged(id) }
        func windowDidMiniaturize(_ notification: Notification) { if backend?.applying == false { backend?.emit(.minimized(id, true)) } }
        func windowDidDeminiaturize(_ notification: Notification) { if backend?.applying == false { backend?.emit(.minimized(id, false)) } }
    }
}
