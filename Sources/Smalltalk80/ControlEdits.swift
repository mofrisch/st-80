import Foundation
import SmalltalkCore

struct ControlAddress: Hashable {
    let windowID: Int64
    let elementID: String
}

/// Native drafts can be newer than the image snapshot. Keep them until the VM
/// acknowledges the specific edit, or until its control leaves the snapshot.
struct ControlEdits {
    struct TextEdit {
        let address: ControlAddress
        let text: String
        let revision: UInt64
    }

    private struct Input {
        let kind: UIElementKind
        let text: String
        let live: Bool
    }

    private var drafts: [ControlAddress: TextEdit] = [:]
    private var inputs: [ControlAddress: Input] = [:]
    private var selections: [ControlAddress: NSRange] = [:]
    private var revision: UInt64 = 0

    var hasPendingEdits: Bool { !drafts.isEmpty }
    var hasLiveEdits: Bool { drafts.keys.contains { inputs[$0]?.live == true } }

    var pendingEdits: [TextEdit] {
        drafts.values.sorted { $0.revision < $1.revision }
    }

    func isCodeEditor(_ address: ControlAddress) -> Bool {
        inputs[address]?.kind == .codeEditor
    }

    func text(at address: ControlAddress, fallback: String) -> String {
        drafts[address]?.text ?? inputs[address]?.text ?? fallback
    }

    mutating func recordText(_ text: String, at address: ControlAddress) {
        revision &+= 1
        drafts[address] = TextEdit(address: address, text: text, revision: revision)
    }

    mutating func acknowledge(_ edit: TextEdit) {
        if drafts[edit.address]?.revision == edit.revision {
            drafts.removeValue(forKey: edit.address)
        }
    }

    func selection(at address: ControlAddress) -> NSRange {
        selections[address] ?? NSRange(location: 0, length: 0)
    }

    mutating func recordSelection(_ range: NSRange, at address: ControlAddress) {
        if selections[address] != range { selections[address] = range }
    }

    mutating func reconcile(with windows: [ToolWindowInfo]) {
        var mounted: [ControlAddress: Input] = [:]
        func collectInputs(_ element: UIElementInfo, windowID: Int64) {
            if element.kind == .textField || element.kind == .codeEditor {
                let address = ControlAddress(windowID: windowID, elementID: element.id)
                mounted[address] = Input(kind: element.kind, text: element.text, live: element.liveInput)
            }
            for child in element.children { collectInputs(child, windowID: windowID) }
        }
        for window in windows {
            if let content = window.content { collectInputs(content, windowID: window.id) }
        }

        selections = selections.filter { address, range in
            guard let editor = mounted[address], editor.kind == .codeEditor else { return false }
            if drafts[address] == nil, inputs[address]?.text != editor.text {
                return NSMaxRange(range) <= editor.text.utf16.count
            }
            return true
        }
        drafts = drafts.filter { mounted[$0.key] != nil }
        inputs = mounted
    }
}

extension UIElementInfo {
    func firstVisible(where matches: (UIElementInfo) -> Bool) -> UIElementInfo? {
        guard visible else { return nil }
        if matches(self) { return self }
        for child in children {
            if let found = child.firstVisible(where: matches) { return found }
        }
        for item in contextMenuItems ?? [] {
            if let found = item.firstVisible(where: matches) { return found }
        }
        return nil
    }
}
