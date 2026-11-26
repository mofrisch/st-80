/// Metadata for a snapshot window hosted outside the main desktop cycle.
package struct TransientWindowInfo: Sendable {
    package let identifier: String
    package let title: String
    package let width: Int64
    package let height: Int64
    package let minimumWidth: Int64
    package let minimumHeight: Int64
}

extension SmalltalkSession {
    private static let bundledSettingsWorker = InterpreterWorker()

    package func settingsWindow() async throws -> (info: TransientWindowInfo, content: UIElementInfo) {
        if let presentation = try await worker.submitThrowing({ try $0.settingsWindow() }) { return presentation }
        return try await Self.bundledSettingsWorker.submitThrowing { runtime in
            guard let presentation = try runtime.settingsWindow() else {
                throw SmalltalkError("The Settings window class is missing.")
            }
            return presentation
        }
    }
}

extension SmalltalkRuntime {
    fileprivate func settingsWindow() throws -> (info: TransientWindowInfo, content: UIElementInfo)? {
        guard let windowClass = classes["SettingsWindow"] else { return nil }
        steps = 0
        let window = try send(.classObject(windowClass), "new", [])
        let info = try projectTransientWindow(window)
        guard case .object(let object) = window, let content = try projectWindowContent(object) else {
            throw SmalltalkError("The Settings window has no content.")
        }
        return (info, content)
    }

    func projectTransientWindow(_ value: Value) throws -> TransientWindowInfo {
        guard case .object(let window) = value, isUIClass(window.stClass, named: "UIWindow"),
              let identifier = window.fields["identifier"]?.textContents, !identifier.isEmpty, identifier.utf8.count <= 128,
              let title = window.fields["title"]?.textContents,
              case .integer(let width)? = window.fields["width"], (1...8192).contains(width),
              case .integer(let height)? = window.fields["height"], (1...8192).contains(height),
              case .integer(let minimumWidth)? = window.fields["minimumWidth"], (1...width).contains(minimumWidth),
              case .integer(let minimumHeight)? = window.fields["minimumHeight"], (1...height).contains(minimumHeight) else {
            throw SmalltalkError("The snapshot window has invalid geometry or metadata.")
        }
        return TransientWindowInfo(identifier: identifier, title: String(title.prefix(256)), width: width, height: height,
                                   minimumWidth: minimumWidth, minimumHeight: minimumHeight)
    }
}
