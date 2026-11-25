import Foundation
import Observation
import SmalltalkCore

@MainActor
@Observable
final class InspectorPresentationState {
    private let session: SmalltalkSession
    @ObservationIgnored private var snapshot: InspectorSnapshot
    @ObservationIgnored private var rendering: Task<Void, Never>?
    private(set) var content: UIElementInfo?
    private(set) var isLoading = true

    init(snapshot: InspectorSnapshot, session: SmalltalkSession) {
        self.snapshot = snapshot
        self.session = session
        render()
    }

    func click(_ control: UIElementInfo) { perform(control, row: nil) }

    func select(_ control: UIElementInfo, row: String) { perform(control, row: row) }

    func close() {
        rendering?.cancel()
        rendering = nil
        let id = snapshot.id
        Task { [session] in await session.closeInspector(id) }
    }

    private func perform(_ control: UIElementInfo, row: String?) {
        guard !isLoading, control.enabled, let command = control.command else { return }
        render(command: command, row: row)
    }

    private func render(command: String? = nil, row: String? = nil) {
        isLoading = true
        let snapshot = snapshot
        rendering = Task { [weak self, session] in
            guard !Task.isCancelled else { return }
            defer { if !Task.isCancelled { self?.isLoading = false } }
            do {
                let updated: InspectorSnapshot
                if let command {
                    guard let result = try await session.inspectorAction(command, row: row, in: snapshot),
                          !Task.isCancelled else { return }
                    updated = result
                } else {
                    updated = snapshot
                }
                let tree = try await session.inspectorContent(for: updated)
                guard !Task.isCancelled else { return }
                self?.snapshot = updated
                self?.content = tree
            } catch {
                guard !Task.isCancelled else { return }
                let tree = try? await session.inspectorRecoveryContent(error.localizedDescription)
                guard !Task.isCancelled else { return }
                self?.content = tree
            }
        }
    }
}
