import Foundation

package struct ControlAddress: Hashable {
    package let windowID: Int64
    package let elementID: String

    package init(windowID: Int64, elementID: String) {
        self.windowID = windowID
        self.elementID = elementID
    }
}

/// Editor drafts can be newer than the image snapshot. Keep them until the VM
/// acknowledges the specific edit, or until its control leaves the snapshot.
package struct ControlEdits {
    package struct TextEdit {
        package let address: ControlAddress
        package let text: String
        fileprivate let revision: UInt64
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

    package init() {}

    package var hasPendingEdits: Bool { !drafts.isEmpty }
    package var hasLiveEdits: Bool { drafts.keys.contains { inputs[$0]?.live == true } }

    package var pendingEdits: [TextEdit] {
        drafts.values.sorted { $0.revision < $1.revision }
    }

    package func isCodeEditor(_ address: ControlAddress) -> Bool {
        inputs[address]?.kind == .codeEditor
    }

    package func text(at address: ControlAddress, fallback: String) -> String {
        drafts[address]?.text ?? inputs[address]?.text ?? fallback
    }

    package mutating func recordText(_ text: String, at address: ControlAddress) {
        revision &+= 1
        drafts[address] = TextEdit(address: address, text: text, revision: revision)
    }

    package mutating func acknowledge(_ edit: TextEdit) {
        if drafts[edit.address]?.revision == edit.revision {
            drafts.removeValue(forKey: edit.address)
        }
    }

    package func selection(at address: ControlAddress) -> NSRange {
        selections[address] ?? NSRange(location: 0, length: 0)
    }

    package mutating func recordSelection(_ range: NSRange, at address: ControlAddress) {
        if selections[address] != range { selections[address] = range }
    }

    package mutating func reconcile(with windows: [ToolWindowInfo]) {
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
