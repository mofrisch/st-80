import Foundation

/// The VM snapshot owns display state. File associations and input errors are
/// attached to the lifetime of a particular window.
package struct PresentedWindow {
    package fileprivate(set) var info: ToolWindowInfo
    package fileprivate(set) var documentURL: URL?
    package fileprivate(set) var inputError: String?
}

package struct WindowPresentation {
    package private(set) var windows: [PresentedWindow] = []
    package var activeID: Int64?

    package init() {}

    package func window(_ id: Int64) -> PresentedWindow? {
        windows.first { $0.info.id == id }
    }

    package var activeWindow: PresentedWindow? { activeID.flatMap(window) }

    package var workspace: PresentedWindow? {
        if let activeWindow, activeWindow.info.kind == .workspace { return activeWindow }
        return windows.last { $0.info.kind == .workspace }
    }

    package mutating func update(from evaluation: EvaluationResult, replacingWindows: Bool) {
        let previous = replacingWindows ? [:] : Dictionary(uniqueKeysWithValues: windows.map { ($0.info.id, $0) })
        windows = evaluation.windows.map { info in
            guard var existing = previous[info.id], existing.info.identity == info.identity,
                  existing.info.kind == info.kind else { return PresentedWindow(info: info) }
            existing.info = info
            return existing
        }
        activeID = evaluation.activeWindowID
    }

    package mutating func setDocumentURL(_ url: URL, for id: Int64) {
        if let index = index(of: id) { windows[index].documentURL = url }
    }

    package mutating func setInputError(_ error: String?, for id: Int64) {
        if let index = index(of: id) { windows[index].inputError = error }
    }

    private func index(of id: Int64) -> Int? {
        windows.firstIndex { $0.info.id == id }
    }
}
