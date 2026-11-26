extension SmalltalkSession {
    // SwiftUI establishes the native menu groups on the first scene pass.
    // This private runtime executes only the bundled menu builders.
    private static let initialMenus = Result {
        let runtime = SmalltalkRuntime(bootstrap: false)
        try SystemLibrary.shared.get().install(in: runtime)
        return (bar: try runtime.projectApplicationMenu("menuBar"),
                recovery: try runtime.projectApplicationMenu("recoveryCommands"))
    }

    package static func bundledApplicationMenus() throws -> (bar: UIElementInfo, recovery: UIElementInfo) {
        try initialMenus.get()
    }

    package func applicationMenu() async throws -> UIElementInfo {
        try await worker.submitThrowing { try $0.projectApplicationMenu("menuBar") }
    }
}

extension SmalltalkRuntime {
    fileprivate func projectApplicationMenu(_ selector: String) throws -> UIElementInfo {
        guard let presenter = classes["ApplicationMenu"] else {
            throw SmalltalkError("The application menu class is missing.")
        }
        steps = 0
        let tree = try send(.classObject(presenter), selector, [])
        let kind: UIElementKind = selector == "menuBar" ? .column : .menu
        guard let content = try projectContent(tree), content.kind == kind else {
            throw SmalltalkError("The application menu has invalid content.")
        }
        return content
    }
}
