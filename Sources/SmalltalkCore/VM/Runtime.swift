import Foundation

struct ReturnSignal: Error {
    // Execution never crosses an actor boundary; this is interpreter control flow.
    nonisolated(unsafe) let value: Value
    let homeID: Int
}

final class SmalltalkRuntime {
    // Superclasses precede their subclasses so the same hierarchy can seed and
    // identify the built-in classes.
    private static let builtinHierarchy: [(name: String, superclass: String?)] = [
        ("Object", nil),
        ("Class", "Object"),
        ("UndefinedObject", "Object"),
        ("Boolean", "Object"),
        ("True", "Boolean"),
        ("False", "Boolean"),
        ("Number", "Object"),
        ("Integer", "Number"),
        ("SmallInteger", "Integer"),
        ("String", "Object"),
        ("Symbol", "Object"),
        ("Array", "Object"),
        ("BlockClosure", "Object"),
        ("Transcript", "Object"),
    ]
    static let builtinNames = Set(builtinHierarchy.map(\.name))

    var journal = SourceJournal()
    var catalogDirty = false
    var evaluatingToolSource = false
    var capturingTestPhase = false
    var toolRequests: [NativeToolRequest] = []
    var objectInspectors: [UUID: Value] = [:]
    var changesBrowser: Value?
    var mvcBindingIndex = MVCBindingIndex()
    var recordingChanges = false
    var bootstrapError: String?
    let windowEpoch = UUID().uuidString
    var windowCommandRevision: Int64 = 0
    var acknowledgedWindowEvent: Int64 = 0
    var classes: [String: STClass] = [:]
    var globals: [String: Value] = [:]
    var transcript = ""
    var steps = 0
    var depth = 0
    var nextHome = 0
    var activeHomes: Set<Int> = []
    var activations: [(body: BytecodeBody, context: Context)] = []
    var bytecodeOperands: [BytecodeOperand] = []
    var evaluationRoots: [Value] = []
    var pendingMessages: [(receiver: Value, lookup: MessageLookup)] = []
    var debugger: DebuggerExecution?
    var debuggerCancellation: DebuggerChannel?
    var useASTInterpreterForTesting = false
    let compilationMode: Bool
    var arrayLimit: Int { compilationMode ? 524_288 : 4_096 }
    let memory: ObjectMemory
    var environments: [Environment] { memory.environments }
    var objects: [STObject] { memory.objects }
    var arrays: [STArray] { memory.arrays }

    init(bootstrap: Bool = true, compilationMode: Bool = false, memory: ObjectMemory? = nil) {
        self.compilationMode = compilationMode
        self.memory = memory ?? ObjectMemory(hardLimit: compilationMode ? 1_000_000 : 100_000,
                                             initialThreshold: compilationMode ? 32_768 : 4096)
        for (name, superclass) in Self.builtinHierarchy {
            let stClass = STClass(name, superclass: superclass.flatMap { classes[$0] })
            classes[name] = stClass
            globals[name] = .classObject(stClass)
        }
        globals["Transcript"] = .transcript
        if bootstrap {
            do {
                let library = try SystemLibrary.shared.get()
                try library.install(in: self)
                _ = try evaluate(library.initialWorld)
            } catch { bootstrapError = error.localizedDescription }
        }
        catalogDirty = false
        recordingChanges = bootstrap
        transcript = ""
    }

    func tick() throws {
        try debuggerCancellation?.checkStop()
        steps += 1
        guard steps <= (compilationMode ? 24_000_000 : 100_000) else {
            throw SmalltalkError(compilationMode ? "The Smalltalk compiler reached its execution limit." : "Execution stopped after 100,000 steps. Check loops and recursion.")
        }
    }

    func enter() throws {
        try tick()
        guard depth < (compilationMode ? 1400 : 128) else { throw SmalltalkError("Maximum call depth reached.") }
        depth += 1
    }

    /// Start a top-level operation with its own transcript and execution budget.
    func beginEvaluation() {
        transcript = ""
        resetExecutionBudget()
    }

    /// Use only between evaluations, after the stack has unwound.
    func resetExecutionBudget() {
        steps = 0
        depth = 0
    }

    func environment(parent: Environment? = nil) throws -> Environment {
        try withRoots(environments: parent.map { [$0] } ?? []) { _ in
            try checkAllocation()
            let environment = Environment(parent: parent)
            memory.register(environment)
            return environment
        }
    }

    func array(_ values: [Value]) throws -> Value {
        guard values.count <= arrayLimit else { throw SmalltalkError("Arrays are limited to \(arrayLimit.formatted(.number.locale(Locale(identifier: "en_US")))) elements.") }
        return try withRoots(values) { _ in
            try checkAllocation()
            let array = STArray(values)
            memory.register(array)
            return .array(array)
        }
    }

    func array(count: Int) throws -> Value {
        // Validate sizes from an image before constructing the placeholder
        // storage, including sizes that cannot fit in a host allocation.
        guard (0...arrayLimit).contains(count) else {
            throw SmalltalkError("Arrays are limited to \(arrayLimit.formatted(.number.locale(Locale(identifier: "en_US")))) elements.")
        }
        return try array(Array(repeating: .nilValue, count: count))
    }

    func run(_ source: String, inspectingResult: Bool = false) -> EvaluationResult {
        beginEvaluation()
        catalogDirty = true
        do {
            if inspectingResult, source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw SmalltalkError("Enter an expression to inspect.")
            }
            let value = try evaluate(source)
            if inspectingResult {
                try requestInspection(value)
                return finishEvaluation()
            }
            return finishEvaluation(value: printValue(value))
        } catch {
            return finishEvaluation(error: error.localizedDescription)
        }
    }

    func evaluate(_ source: String) throws -> Value {
        let syntax = try compileWorkspace(source)
        let body = BytecodeBody.lower(syntax)
        nextHome += 1
        let homeID = nextHome
        activeHomes.insert(homeID)
        defer { activeHomes.remove(homeID) }
        let context = Context(environment: try environment(), receiver: .nilValue, homeClass: nil, homeID: homeID,
                              isWorkspace: true, debuggerOrigin: DebuggerOrigin(source: source))
        do { return try execute(body, context: context, referenceBody: useASTInterpreterForTesting ? syntax : nil, debuggerKind: .workspace) }
        catch let signal as ReturnSignal where signal.homeID == homeID { return signal.value }
    }

    func execute(_ body: BytecodeBody, context: Context, referenceBody: Body? = nil, debuggerKind: DebuggerFrameKind = .method) throws -> Value {
        activations.append((body, context))
        debugger?.enter(context: context, kind: debuggerKind)
        defer {
            debugger?.leave()
            activations.removeLast()
        }
        for name in body.temporaries { context.environment.values[name] = .nilValue }
        if useASTInterpreterForTesting, let referenceBody {
            var result: Value = .nilValue
            for expression in referenceBody.expressions { result = try evaluate(expression, context: context) }
            return result
        }
        return try executeBytecode(body, context: context)
    }

    func checkHomeForReturn(_ context: Context) throws {
        guard activeHomes.contains(context.homeID) else {
            throw SmalltalkError("The home context of this block has already returned, so ^ cannot return from it.")
        }
    }

    func variable(_ name: String, context: Context) throws -> Value {
        switch name {
        case "nil": return .nilValue
        case "true": return .boolean(true)
        case "false": return .boolean(false)
        case "self": return context.receiver
        case "super": throw SmalltalkError("super must be the receiver of a message.")
        default: break
        }
        if let environment = context.environment.binding(name), let value = environment.values[name] { return value }
        if case .object(let object) = context.receiver, let value = object.fields[name] { return value }
        if let value = globals[name] { return value }
        throw SmalltalkError("Unknown variable: \(name)")
    }

    func assign(_ name: String, value: Value, context: Context) throws {
        guard !["nil", "true", "false", "self", "super", "thisContext", "Transcript"].contains(name), classes[name] == nil else {
            throw SmalltalkError("\(name) cannot be reassigned.")
        }
        if let environment = context.environment.binding(name) { environment.values[name] = value; return }
        if case .object(let object) = context.receiver, object.fields[name] != nil { object.fields[name] = value; return }
        if context.isWorkspace || globals[name] != nil {
            guard globals.count < 1_024 || globals[name] != nil else { throw SmalltalkError("Too many workspace variables.") }
            globals[name] = value
            return
        }
        throw SmalltalkError("Variable \(name) is undeclared.")
    }

    func value(_ literal: Literal) throws -> Value {
        switch literal {
        case .integer(let n): return .integer(n)
        case .string(let s): return .string(s)
        case .symbol(let s): return .symbol(s)
        case .array(let elements):
            return try withRoots { roots in
                var values: [Value] = []
                for element in elements {
                    let value = try value(element)
                    roots.add(value)
                    values.append(value)
                }
                return try array(values)
            }
        }
    }

    func classOf(_ value: Value) -> STClass {
        let name: String
        switch value {
        case .integer: name = "SmallInteger"
        case .string: name = "String"
        case .symbol: name = "Symbol"
        case .boolean(let b): name = b ? "True" : "False"
        case .nilValue: name = "UndefinedObject"
        case .classObject: name = "Class"
        case .object(let object): return object.stClass
        case .array: name = "Array"
        case .block: name = "BlockClosure"
        case .transcript: name = "Transcript"
        }
        return classes[name]!
    }
}
