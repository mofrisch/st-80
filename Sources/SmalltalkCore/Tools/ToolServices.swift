import Foundation

/// Native actions requested by a Smalltalk control.
public enum NativeToolRequest: Sendable {
    case saveImage
    case openInspector(InspectorSnapshot)
    case debugWorkspace(windowID: Int64, identity: String, source: String)
}

extension SmalltalkRuntime {
    func toolPrimitive(_ selector: String, _ args: [Value]) throws -> Value? {
        func outcome(_ operation: () throws -> String) throws -> Value {
            let result: (Bool, String)
            do { result = (true, try operation()) }
            catch where error is ExceptionHandlerReturn || error is ReturnSignal { throw error }
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
        case "failTest:":
            throw SmalltalkError(try string(args[0]), isTestFailure: true)
        case "captureTestPhase:":
            return try captureTestPhase(args[0])
        case "inspect:":
            try requestInspection(args[0])
            return args[0]
        case "collectGarbage": return .integer(Int64(collectGarbage().lastReclaimed))
        case "gcStatistics":
            let stats = memory.statistics
            return try array([
                .symbol("nodes"), .integer(Int64(stats.liveNodes)),
                .symbol("objects"), .integer(Int64(stats.liveObjects)),
                .symbol("arrays"), .integer(Int64(stats.liveArrays)),
                .symbol("blocks"), .integer(Int64(stats.liveBlocks)),
                .symbol("environments"), .integer(Int64(stats.liveEnvironments)),
                .symbol("slots"), .integer(Int64(stats.liveSlots)),
                .symbol("collections"), .integer(Int64(stats.totalCollections)),
                .symbol("reclaimed"), .integer(Int64(stats.totalReclaimed)),
                .symbol("lastPauseNanoseconds"), .integer(Int64(clamping: stats.lastPauseNanoseconds))
            ])
        case "noteCatalogChange":
            catalogDirty = true
            return .nilValue
        case "classNames": return try array(classes.keys.sorted().map(Value.string))
        case "classNamed:": return try classes[string(args[0])].map(Value.classObject) ?? .nilValue
        case "classNameOf:": return try .string(target(args[0]).name)
        case "definitionOf:": return try .string(definitionSource(for: target(args[0])))
        case "canRedefine:": return try .boolean(!Self.builtinNames.contains(target(args[0]).name))
        case "acceptDefinition:in:basedOn:":
            let stClass = try target(args[1])
            return try outcome {
                guard try definitionSource(for: stClass) == string(args[2]) else {
                    throw SmalltalkError("The class definition changed. Reopen it before accepting your edits.")
                }
                try acceptDefinition(string(args[0]), for: stClass)
                return "\(stClass.name) definition accepted."
            }
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
        case "evaluateSource:", "inspectSource:":
            return try outcome {
                guard !evaluatingToolSource else { throw SmalltalkError("A workspace evaluation is already running.") }
                let source = try string(args[0])
                if selector == "inspectSource:", source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw SmalltalkError("Enter an expression to inspect.")
                }
                // Tool source is nested in the current command. Its caller's
                // work and native stack frames still count toward the limits.
                evaluatingToolSource = true
                catalogDirty = true
                defer { evaluatingToolSource = false }
                let value = try evaluate(source)
                if selector == "inspectSource:" {
                    try requestInspection(value)
                    return "Object Inspector opened."
                }
                return printValue(value)
            }
        case "compileSource:in:", "compileSource:in:side:":
            let stClass = try target(args[1])
            let methodSide = args.count == 3 ? try side(args[2]) : .instance
            return try outcome { try compile(string(args[0]), in: stClass, side: methodSide) }
        case "acceptMethod:in:side:selector:basedOn:":
            let stClass = try target(args[1])
            let methodSide = try side(args[2])
            let originalSelector = isNil(args[3]) ? nil : try string(args[3])
            let originalSource = try string(args[4])
            return try outcome {
                try compile(string(args[0]), in: stClass, side: methodSide) { method in
                    if let originalSelector,
                       stClass[methodSide][originalSelector]?.source != originalSource {
                        throw SmalltalkError("The method changed. Reopen it before accepting your edits.")
                    }
                    if method.selector != originalSelector, stClass[methodSide][method.selector] != nil {
                        throw SmalltalkError("A method named \(method.selector) already exists. Reopen it before accepting your edits.")
                    }
                }
            }
        case "createSubclass:fields:":
            return try outcome {
                guard let root = classes["Object"] else { throw SmalltalkError("The base class Object is missing.") }
                let target = try subclass(of: root, name: string(args[0]), fields: string(args[1]))
                return target.name
            }
        case "success:": return try array([.boolean(true), .string(string(args[0]))])
        case "lineBreak": return .string("\n")
        case "exampleAt:":
            let key = Value.symbol(try symbol(args[0]))
            if let catalog = classes["WorkspaceExamples"] {
                return try send(.classObject(catalog), "sourceAt:", [key])
            }
            // Stored workspaces may still send the original tool message.
            return .string(try SmalltalkExamples.bundledSource("sourceAt:", arguments: [key]))
        case "bytecodeOf:in:side:":
            let stClass = try target(args[1])
            guard let method = try stClass[side(args[2])][string(args[0])] else { return .string("Bytecode unavailable.") }
            let listing = method.body.disassembly(parameters: method.parameters)
            if listing.utf8.count <= 65_536 { return .string(listing) }
            let prefix = String(decoding: listing.utf8.prefix(65_500), as: UTF8.self)
            return .string(prefix + "\n… listing truncated")
        case "requestDebugSource:for:":
            let source = try string(args[0])
            guard case .object(let window) = args[1], case .integer(let id)? = window.fields["id"],
                  isUIClass(window.stClass, named: "WorkspaceWindow"), projectedWindow(withID: id) === window,
                  source.utf8.count <= 65_536 else {
                throw SmalltalkError("A debug request requires an open workspace and at most 64 KiB of source.")
            }
            toolRequests.append(.debugWorkspace(windowID: id, identity: window.nativeID, source: source))
            return .nilValue
        case "requestSaveImage":
            toolRequests.append(.saveImage)
            return .nilValue
        default: return try inspectionPrimitive(selector, args) ?? changeHistoryPrimitive(selector, args)
        }
    }

    private func captureTestPhase(_ block: Value) throws -> Value {
        guard !capturingTestPhase else { throw SmalltalkError("A test phase is already running.") }
        let enclosingSteps = steps
        capturingTestPhase = true
        steps = 0
        defer {
            steps = enclosingSteps
            capturingTestPhase = false
        }
        do {
            _ = try invokeBlock(block)
            return .nilValue
        } catch let error as SmalltalkError {
            return try array([
                .symbol(error.isTestFailure ? "failure" : "error"),
                .string(error.message),
                error.position.map { .integer(Int64($0.line)) } ?? .nilValue,
                error.position.map { .integer(Int64($0.column)) } ?? .nilValue,
            ])
        }
    }

    func finishWorkspaceEvaluation(value: String?, error: String?, target: (id: Int64, identity: String)?) -> EvaluationResult {
        // Reporting a step-limit error needs a fresh presentation budget.
        resetExecutionBudget()
        var failure = error
        if let target, let workspace = projectedWindow(withID: target.id), workspace.nativeID == target.identity,
           isUIClass(workspace.stClass, named: "WorkspaceWindow") {
            do {
                try withRoots([.object(workspace)]) { _ in
                    let outcome = try array([.boolean(failure == nil), .string(value ?? failure ?? "")])
                    _ = try send(.object(workspace), "result:", [outcome])
                }
            } catch {
                failure = failure ?? error.localizedDescription
            }
        }
        return finishEvaluation(value: value, error: failure)
    }
}
