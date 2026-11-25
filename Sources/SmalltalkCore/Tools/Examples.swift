import Foundation

/// The shipped sources for Swift callers. Open workspaces use the catalog in their live image.
public enum SmalltalkExamples {
    public static let workspace = shippedSource("workspace")
    public static let collections = shippedSource("collections")
    public static let classes = shippedSource("classes")
    public static let legacyUserInterface = shippedSource("legacyUserInterface")
    public static let mvcDefinitions = shippedSource("mvcDefinitions")
    public static let userInterface = shippedSource("userInterface")
    public static let precedence = shippedSource("precedence")

    static func bundledSource(_ selector: String, arguments: [Value] = []) throws -> String {
        let runtime = SmalltalkRuntime(bootstrap: false)
        let catalog = try SystemLibrary.shared.get().bundledClass("WorkspaceExamples", in: runtime)
        let value = try runtime.send(.classObject(catalog), selector, arguments)
        return try runtime.string(value)
    }

    private static func shippedSource(_ selector: String) -> String {
        do { return try bundledSource(selector) }
        catch { preconditionFailure("Could not read the bundled workspace example \(selector): \(error.localizedDescription)") }
    }
}
