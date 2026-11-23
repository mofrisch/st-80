import Foundation
import SmalltalkCore

/// The VM snapshot owns display state. File associations and input errors are
/// native details attached to the lifetime of a particular window.
struct PresentedWindow {
    var info: ToolWindowInfo
    var documentURL: URL?
    var inputError: String?
    var showsBytecode = false
}

struct WindowPresentation {
    private(set) var windows: [PresentedWindow] = []
    var activeID: Int64?

    func window(_ id: Int64) -> PresentedWindow? {
        windows.first { $0.info.id == id }
    }

    var activeWindow: PresentedWindow? { activeID.flatMap(window) }

    var workspace: PresentedWindow? {
        if let activeWindow, activeWindow.info.kind == .workspace { return activeWindow }
        return windows.last { $0.info.kind == .workspace }
    }

    mutating func update(from evaluation: EvaluationResult, replacingWindows: Bool) {
        let previous = replacingWindows ? [:] : Dictionary(uniqueKeysWithValues: windows.map { ($0.info.id, $0) })
        windows = evaluation.windows.map { info in
            guard var existing = previous[info.id], existing.info.identity == info.identity,
                  existing.info.kind == info.kind else { return PresentedWindow(info: info) }
            existing.info = info
            if info.browserMethod == nil { existing.showsBytecode = false }
            return existing
        }
        activeID = evaluation.activeWindowID
    }

    mutating func setDocumentURL(_ url: URL, for id: Int64) {
        if let index = index(of: id) { windows[index].documentURL = url }
    }

    mutating func setInputError(_ error: String?, for id: Int64) {
        if let index = index(of: id) { windows[index].inputError = error }
    }

    mutating func toggleBytecode(for id: Int64) {
        guard let index = index(of: id), windows[index].info.browserMethod != nil else { return }
        windows[index].showsBytecode.toggle()
    }

    private func index(of id: Int64) -> Int? {
        windows.firstIndex { $0.info.id == id }
    }
}
