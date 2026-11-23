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
        state = nil
        callback?()
    }
}

@MainActor
@Observable
private final class DebuggerWindowState {
    private(set) var snapshot: DebuggerSnapshot
    private(set) var isRunning = false
    private(set) var isStopping = false
    var selectedFrameID: Int?
    @ObservationIgnored private var onCommand: (DebuggerCommand) -> Void

    init(snapshot: DebuggerSnapshot, onCommand: @escaping (DebuggerCommand) -> Void) {
        self.snapshot = snapshot
        self.onCommand = onCommand
        selectedFrameID = snapshot.frames.first?.id
    }

    var selectedFrame: DebuggerFrame? {
        snapshot.frames.first { $0.id == selectedFrameID } ?? snapshot.frames.first
    }

    var error: String? {
        guard case .error(let message) = snapshot.reason else { return nil }
        return message
    }

    var canStep: Bool { !isRunning && !isStopping && error == nil }

    func update(_ snapshot: DebuggerSnapshot, onCommand: @escaping (DebuggerCommand) -> Void) {
        self.snapshot = snapshot
        self.onCommand = onCommand
        selectedFrameID = snapshot.frames.first?.id
        isRunning = false
        isStopping = false
    }

    func perform(_ command: DebuggerCommand) {
        switch command {
        case .stop:
            guard !isStopping else { return }
            isStopping = true
        default:
            guard canStep else { return }
            isRunning = true
        }
        onCommand(command)
    }
}

private struct DebuggerView: View {
    @Bindable var state: DebuggerWindowState

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            if let error = state.error {
                Label {
                    Text(error).textSelection(.enabled)
                        .accessibilityIdentifier("debuggerError")
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
            }
            HSplitView {
                stack.frame(minWidth: 160, idealWidth: 220, maxWidth: 320)
                if let frame = state.selectedFrame {
                    VSplitView {
                        DebuggerSourceView(frame: frame)
                            .frame(minHeight: 114, idealHeight: 290)
                        ValueTable(rows: frame.variables, name: \.name, value: \.value, className: \.className,
                                   identifier: "debuggerVariables", rowIdentifierPrefix: "debuggerVariable")
                            .frame(minHeight: 95, idealHeight: 150)
                    }
                } else {
                    ContentUnavailableView("No active frame", systemImage: "square.stack")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .disabled(state.isRunning || state.isStopping)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button("Continue") { state.perform(.resume) }
                .buttonStyle(.borderedProminent)
                .disabled(!state.canStep)
                .accessibilityIdentifier("debuggerContinue")
            Button("Step Into") { state.perform(.stepInto) }
                .disabled(!state.canStep)
                .accessibilityIdentifier("debuggerStepInto")
            Button("Step Over") { state.perform(.stepOver) }
                .disabled(!state.canStep)
                .accessibilityIdentifier("debuggerStepOver")
            Button("Step Out") { state.perform(.stepOut) }
                .disabled(!state.canStep || state.snapshot.frames.count < 2)
                .accessibilityIdentifier("debuggerStepOut")
            Spacer()
            if state.isRunning || state.isStopping {
                Text(state.isStopping ? "Stopping…" : "Running…")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Divider().frame(height: 18)
            Button(state.error == nil ? "Stop" : "Close", role: state.error == nil ? .destructive : nil) {
                state.perform(.stop)
            }
            .disabled(state.isStopping)
            .accessibilityIdentifier("debuggerStop")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Call Stack")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider()
            List(selection: $state.selectedFrameID) {
                ForEach(state.snapshot.frames, id: \.id) { frame in
                    HStack(spacing: 6) {
                        Text(frame.title)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Text(String(frame.line))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .tag(frame.id)
                    .accessibilityIdentifier("debuggerFrame-\(frame.id)")
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("debuggerStack")
        }
    }
}

private struct DebuggerSourceView: View {
    let frame: DebuggerFrame

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(frame.title)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityIdentifier("debuggerFrameTitle")
                Spacer()
                Text("Line \(frame.line), column \(frame.column)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("debuggerLocation")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            if frame.source.isEmpty {
                Text("Source unavailable")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                source
            }
            if !frame.instruction.isEmpty {
                Divider()
                Text(frame.instruction)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .accessibilityIdentifier("debuggerInstruction")
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var source: some View {
        let lines = frame.source.split(omittingEmptySubsequences: false) {
            $0 == "\n" || $0 == "\r" || $0 == "\r\n"
        }
        return ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.indices, id: \.self) { index in
                        sourceLine(lines[index], number: index + 1)
                            .id(index + 1)
                    }
                }
            }
            .accessibilityIdentifier("debuggerSource")
            .task(id: [frame.id, frame.line]) {
                guard lines.indices.contains(frame.line - 1) else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                reader.scrollTo(frame.line, anchor: .center)
            }
        }
    }

    private func sourceLine(_ source: Substring, number: Int) -> some View {
        let current = number == frame.line
        let width: CGFloat = 42
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(String(number))
                .foregroundStyle(.secondary)
                .frame(width: width, alignment: .trailing)
                .accessibilityHidden(true)
            Text(markedSource(source, column: current ? frame.column : nil))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 14, design: .monospaced))
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .background(current ? Color.accentColor.opacity(0.14) : .clear)
        .overlay(alignment: .leading) {
            if current {
                Rectangle().fill(Color.accentColor).frame(width: 2)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
    }

    private func markedSource(_ source: Substring, column: Int?) -> AttributedString {
        var marked = AttributedString(String(source))
        if let column, column > 0,
           let start = marked.characters.index(marked.startIndex, offsetBy: column - 1, limitedBy: marked.endIndex),
           start < marked.endIndex {
            let end = marked.characters.index(after: start)
            marked[start..<end].backgroundColor = Color.accentColor.opacity(0.3)
        }
        return marked
    }
}
