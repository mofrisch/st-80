import Foundation

/// Native actions requested by a Smalltalk control. File dialogs and the
/// platform's version-history window are handled by the app.
public enum NativeToolRequest: Sendable {
    case saveImage
    case showVersions(className: String, selector: String)
}

extension SmalltalkRuntime {
    func toolPrimitive(_ selector: String, _ args: [Value]) throws -> Value? {
        func outcome(_ operation: () throws -> String) throws -> Value {
            let result: (Bool, String)
            do { result = (true, try operation()) }
            catch { result = (false, error.localizedDescription) }
            return try array([.boolean(result.0), .string(result.1)])
        }
        switch selector {
        case "classNames": return try array(classes.keys.sorted().map(Value.string))
        case "classNamed:": return try classes[string(args[0])].map(Value.classObject) ?? .nilValue
        case "bindingSummary":
            let summary = bindingInfos().map { "\($0.name)  [\($0.className)]\n\($0.value)" }.joined(separator: "\n\n")
            return .string(String(summary.prefix(10_000)))
        case "evaluateSource:":
            return try outcome {
                guard !evaluatingToolSource else { throw SmalltalkError("Eine Workspace-Auswertung läuft bereits.") }
                let enclosingDepth = depth
                let enclosingSteps = steps
                evaluatingToolSource = true
                steps = 0
                depth = 0
                catalogDirty = true
                defer {
                    evaluatingToolSource = false
                    steps = enclosingSteps
                    depth = enclosingDepth
                }
                return printValue(try evaluate(string(args[0])))
            }
        case "compileSource:in:":
            guard case .classObject(let target) = args[1] else { throw SmalltalkError("Klasse erwartet.") }
            return try outcome { try compile(string(args[0]), in: target) }
        case "createSubclass:fields:":
            return try outcome {
                guard let root = classes["Object"] else { throw SmalltalkError("Basisklasse Object fehlt.") }
                let target = try subclass(of: root, name: string(args[0]), fields: string(args[1]))
                return target.name
            }
        case "success:": return try array([.boolean(true), .string(string(args[0]))])
        case "lineBreak": return .string("\n")
        case "exampleAt:":
            switch try symbol(args[0]) {
            case "workspace": return .string(SmalltalkExamples.workspace)
            case "collections": return .string(SmalltalkExamples.collections)
            case "classes": return .string(SmalltalkExamples.classes)
            case "windows": return .string("window := Desktop openWorkspace.\nwindow title: 'Mein Workspace'.\nwindow text: '6 * 7'")
            case "userInterface": return .string(SmalltalkExamples.userInterface)
            default: throw SmalltalkError("Unbekanntes Workspace-Beispiel.")
            }
        case "requestSaveImage":
            toolRequests.append(.saveImage)
            return .nilValue
        case "requestVersionsFor:selector:":
            toolRequests.append(.showVersions(className: try string(args[0]), selector: try string(args[1])))
            return .nilValue
        default: return nil
        }
    }

    func refreshToolWindowsIfNeeded() throws {
        guard catalogDirty else { return }
        catalogDirty = false
        guard case .object(let desktop)? = globals["Desktop"],
              case .object(let model)? = desktop.fields["model"],
              case .array(let windows)? = model.fields["windows"] else { return }
        for case .object(let window) in windows.elements where window.stClass.lookup("refreshTools") != nil {
            _ = try send(.object(window), "refreshTools", [])
        }
    }
}
