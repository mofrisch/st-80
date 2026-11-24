import AppKit
import Observation
import SmalltalkCore
import SwiftUI

@MainActor
final class NativeDebuggerWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var state: DebuggerWindowState?
    private var onClose: (() -> Void)?

    func show(_ snapshot: DebuggerSnapshot, onCommand: @escaping (DebuggerCommand) -> Void,
              onClose: @escaping () -> Void) {
        self.onClose = onClose
        if let window, let state {
            state.update(snapshot, onCommand: onCommand)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let state = DebuggerWindowState(snapshot: snapshot, onCommand: onCommand)
        let size = NSSize(width: 840, height: 540)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Debugger"
        window.identifier = NSUserInterfaceItemIdentifier("debugger")
        window.setAccessibilityIdentifier("debugger")
        window.setAccessibilityLabel(window.title)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.delegate = self
        let hosting = NSHostingController(rootView: DebuggerView(state: state))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.contentMinSize = NSSize(width: 620, height: 360)
        window.setContentSize(size)
        window.center()

        self.state = state
        self.window = window
        NSApp.addWindowsItem(window, title: window.title, filename: false)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        onClose = nil
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window, notification.object as? NSWindow === window else { return }
        let callback = onClose
        onClose = nil
        window.delegate = nil
        NSApp.removeWindowsItem(window)
        self.window = nil
        state?.cancelRendering()
        state = nil
        callback?()
    }
}

@MainActor
@Observable
private final class DebuggerWindowState {
    @ObservationIgnored private var snapshot: DebuggerSnapshot
    @ObservationIgnored private var onCommand: (DebuggerCommand) -> Void
    @ObservationIgnored private var rendering: Task<Void, Never>?
    @ObservationIgnored private var selectedFrameID: Int?
    private(set) var phase = DebuggerPresentationPhase.paused
    private(set) var content: UIElementInfo?
    private(set) var presentationError: String?

    init(snapshot: DebuggerSnapshot, onCommand: @escaping (DebuggerCommand) -> Void) {
        self.snapshot = snapshot
        self.onCommand = onCommand
        render()
    }

    func update(_ snapshot: DebuggerSnapshot, onCommand: @escaping (DebuggerCommand) -> Void) {
        self.snapshot = snapshot
        self.onCommand = onCommand
        selectedFrameID = nil
        phase = .paused
        render()
    }

    func select(_ control: UIElementInfo, row: String) {
        guard phase == .paused, control.command == "selectFrame", let id = Int(row),
              snapshot.frames.contains(where: { $0.id == id }), selectedFrameID != id else { return }
        selectedFrameID = id
        render()
    }

    func click(_ control: UIElementInfo) {
        guard let command = control.command.flatMap(DebuggerCommand.init(rawValue:)) else { return }
        perform(command)
    }

    func perform(_ command: DebuggerCommand) {
        if command == .stop {
            guard phase != .stopping else { return }
            phase = .stopping
        } else {
            guard phase == .paused else { return }
            if case .error = snapshot.reason { return }
            phase = .running
        }
        onCommand(command)
        render()
    }

    func cancelRendering() {
        rendering?.cancel()
        rendering = nil
    }

    private func render() {
        cancelRendering()
        let snapshot = snapshot
        let selected = selectedFrameID
        let phase = phase
        rendering = Task { [weak self] in
            do {
                let content = try await snapshot.controlTree(selectedFrameID: selected, phase: phase)
                guard !Task.isCancelled else { return }
                self?.content = content
                self?.presentationError = nil
            } catch {
                guard !Task.isCancelled else { return }
                self?.presentationError = error.localizedDescription
            }
        }
    }
}

private struct DebuggerView: View {
    let state: DebuggerWindowState

    var body: some View {
        Group {
            if let content = state.content, state.presentationError == nil {
                UIElementView(host: .snapshot(isLoading: false, click: state.click, select: state.select), element: content)
            } else {
                // The command path stays usable even if the image's view fails.
                VStack(alignment: .leading, spacing: 8) {
                    if let error = state.presentationError {
                        Text(error).foregroundStyle(.red).textSelection(.enabled)
                    } else {
                        ProgressView()
                    }
                    Button("Stop", role: .destructive) { state.perform(.stop) }
                        .disabled(state.phase == .stopping)
                        .accessibilityIdentifier("debuggerStop")
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
