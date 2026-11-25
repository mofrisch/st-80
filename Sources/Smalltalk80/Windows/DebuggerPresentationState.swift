import Foundation
import Observation
import SmalltalkCore

@MainActor
@Observable
final class DebuggerPresentationState {
    @ObservationIgnored private var snapshot: DebuggerSnapshot
    private let onCommand: (DebuggerCommand) -> Void
    @ObservationIgnored private var rendering: Task<Void, Never>?
    @ObservationIgnored private var sendingCommand: Task<Void, Never>?
    @ObservationIgnored private var selectedFrameID: Int?
    private var phase = DebuggerPresentationPhase.paused
    private(set) var content: UIElementInfo?

    init(snapshot: DebuggerSnapshot, onCommand: @escaping (DebuggerCommand) -> Void) {
        self.snapshot = snapshot
        self.onCommand = onCommand
        render()
    }

    func update(_ snapshot: DebuggerSnapshot) {
        cancel()
        self.snapshot = snapshot
        selectedFrameID = nil
        phase = .paused
        render()
    }

    func select(_ control: UIElementInfo, row: String) {
        guard phase == .paused, sendingCommand == nil, control.enabled, control.command == "selectFrame",
              let id = Int(row), selectedFrameID != id else { return }
        selectedFrameID = id
        render()
    }

    func click(_ control: UIElementInfo) {
        guard control.enabled, let command = control.command.flatMap(DebuggerCommand.init(rawValue:)) else { return }
        if command == .stop {
            stop()
            return
        }
        guard sendingCommand == nil, phase != .stopping else { return }
        let snapshot = snapshot
        let phase = phase
        sendingCommand = Task { [weak self] in
            do {
                let next = try await snapshot.commandPhase(after: command, from: phase)
                guard !Task.isCancelled, let self else { return }
                sendingCommand = nil
                guard let next else { return }
                self.phase = next
                onCommand(command)
                render()
            } catch {
                guard !Task.isCancelled, let self else { return }
                sendingCommand = nil
                render(recoveringFrom: error.localizedDescription)
            }
        }
    }

    func stop() {
        guard phase != .stopping else { return }
        cancel()
        phase = .stopping
        // The command channel is available even when the presentation worker fails.
        onCommand(.stop)
        render()
    }

    func cancel() {
        rendering?.cancel()
        rendering = nil
        sendingCommand?.cancel()
        sendingCommand = nil
    }

    private func render(recoveringFrom problem: String? = nil) {
        rendering?.cancel()
        let snapshot = snapshot
        let selected = selectedFrameID
        let phase = phase
        rendering = Task { [weak self] in
            let content: UIElementInfo?
            if let problem {
                content = try? await snapshot.recoveryContent(message: problem, phase: phase)
            } else {
                do {
                    content = try await snapshot.controlTree(selectedFrameID: selected, phase: phase)
                } catch {
                    guard !Task.isCancelled else { return }
                    content = try? await snapshot.recoveryContent(message: error.localizedDescription, phase: phase)
                }
            }
            guard !Task.isCancelled else { return }
            self?.content = content
        }
    }
}
