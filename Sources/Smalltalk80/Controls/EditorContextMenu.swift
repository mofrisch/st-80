import SmalltalkCore

enum EditorContextAction: Equatable {
    case control(String)
    case legacyInspect
    case debugWorkspace(editorID: String)
}

enum EditorContextItem {
    case command(title: String, identifier: String, action: EditorContextAction, enabled: Bool)
    case divider

    init?(projected element: UIElementInfo) {
        guard element.visible else { return nil }
        switch element.kind {
        case .button:
            self = .command(title: element.text, identifier: element.command ?? element.id,
                            action: .control(element.id), enabled: element.enabled)
        case .divider:
            self = .divider
        default:
            return nil
        }
    }
}
