import Foundation

/// Native actions requested by a Smalltalk control. File dialogs and the
/// platform's version-history window are handled by the app.
public enum NativeToolRequest: Sendable {
    case saveImage
    case showVersions(className: String, selector: String, side: MethodSide = .instance)
}

extension SmalltalkRuntime {
    func toolPrimitive(_ selector: String, _ args: [Value]) throws -> Value? {
        func outcome(_ operation: () throws -> String) throws -> Value {
            let result: (Bool, String)
            do { result = (true, try operation()) }
            catch { result = (false, error.localizedDescription) }
            return try array([.boolean(result.0), .string(result.1)])
        }
        func target(_ argument: Value) throws -> STClass {
            guard case .classObject(let stClass) = argument else { throw SmalltalkError("Expected a class.") }
            return stClass
        }
        func side(_ argument: Value) throws -> MethodSide {
            guard let methodSide = MethodSide(rawValue: try symbol(argument)) else { throw SmalltalkError("Expected #instance or #class.") }
            return methodSide
        }
        switch selector {
        case "classNames": return try array(classes.keys.sorted().map(Value.string))
        case "classNamed:": return try classes[string(args[0])].map(Value.classObject) ?? .nilValue
        case "classNameOf:": return try .string(target(args[0]).name)
        case "classDetails:":
            let stClass = try target(args[0])
            return try array([.string(stClass.superclass?.name ?? ""), .string(stClass.fields.isEmpty ? "None" : stClass.fields.joined(separator: " · "))])
        case "methodNamesFor:side:":
            return try array(reflectedMethods(on: target(args[0]), side: side(args[1])).map { .string($0.selector) })
        case "methodSourceAt:in:side:":
            return try reflectedMethodSource(string(args[0]), on: target(args[1]), side: side(args[2])).map(Value.string) ?? .nilValue
        case "isPrimitiveAt:in:side:":
            return try .boolean(isReflectedPrimitive(string(args[0]), on: target(args[1]), side: side(args[2])))
        case "bindingSummary":
            let summary = bindingInfos().map { "\($0.name)  [\($0.className)]\n\($0.value)" }.joined(separator: "\n\n")
            return .string(String(summary.prefix(10_000)))
        case "evaluateSource:":
            return try outcome {
                guard !evaluatingToolSource else { throw SmalltalkError("A workspace evaluation is already running.") }
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
        case "compileSource:in:", "compileSource:in:side:":
            let stClass = try target(args[1])
            let methodSide = args.count == 3 ? try side(args[2]) : .instance
            return try outcome { try compile(string(args[0]), in: stClass, side: methodSide) }
        case "createSubclass:fields:":
            return try outcome {
                guard let root = classes["Object"] else { throw SmalltalkError("The base class Object is missing.") }
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
            case "windows": return .string("window := Desktop openWorkspace.\nwindow title: 'My Workspace'.\nwindow text: '6 * 7'")
            case "userInterface": return .string(SmalltalkExamples.userInterface)
            default: throw SmalltalkError("Unknown workspace example.")
            }
        case "requestSaveImage":
            toolRequests.append(.saveImage)
            return .nilValue
        case "requestVersionsFor:selector:", "requestVersionsFor:selector:side:":
            let methodSide = args.count == 3 ? try side(args[2]) : .instance
            toolRequests.append(.showVersions(className: try string(args[0]), selector: try string(args[1]), side: methodSide))
            return .nilValue
        default: return nil
        }
    }

    func refreshToolWindowsIfNeeded() throws {
        guard catalogDirty else { return }
        catalogDirty = false
        guard let windows = desktopWindows else { return }
        for case .object(let window) in windows.elements where window.stClass.lookup("refreshTools") != nil {
            _ = try send(.object(window), "refreshTools", [])
        }
    }
}
