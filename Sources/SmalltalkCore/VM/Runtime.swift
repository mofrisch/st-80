import Foundation

public enum MethodSide: String, Codable, CaseIterable, Sendable {
    case instance
    case classSide = "class"

    public func displayName(for className: String) -> String {
        self == .classSide ? "\(className) class" : className
    }
}

enum Value {
    case integer(Int64), string(String), symbol(String), boolean(Bool), nilValue
    case classObject(STClass), object(STObject), block(STBlock), array(STArray), transcript
}

final class STClass {
    let name: String
    var superclass: STClass?
    var ownFields: [String]
    var methods: [String: Method] = [:]
    var classMethods: [String: Method] = [:]
    var fields: [String] { (superclass?.fields ?? []) + ownFields }

    init(_ name: String, superclass: STClass?, fields: [String] = []) {
        self.name = name
        self.superclass = superclass
        ownFields = fields
    }

    subscript(side: MethodSide) -> [String: Method] {
        get { side == .instance ? methods : classMethods }
        set {
            switch side {
            case .instance: methods = newValue
            case .classSide: classMethods = newValue
            }
        }
    }

    func fields(for side: MethodSide) -> [String] { side == .instance ? fields : [] }

    func lookup(_ selector: String, side: MethodSide = .instance) -> (Method, STClass)? {
        if let method = self[side][selector] { return (method, self) }
        return superclass?.lookup(selector, side: side)
    }
}

final class STObject {
    // Native handles are stable while live and regenerated on image load.
    let nativeID = UUID().uuidString
    let stClass: STClass
    var fields: [String: Value]

    init(_ stClass: STClass) {
        self.stClass = stClass
        fields = Dictionary(uniqueKeysWithValues: stClass.fields.map { ($0, .nilValue) })
    }
}

final class STArray {
    var elements: [Value]
    init(_ elements: [Value]) { self.elements = elements }
}

final class Environment {
    var values: [String: Value] = [:]
    var parent: Environment?
    init(parent: Environment? = nil) { self.parent = parent }

    func binding(_ name: String) -> Environment? {
        var scope: Environment? = self
        while let current = scope {
            if current.values[name] != nil { return current }
            scope = current.parent
        }
        return nil
    }
}

struct Context {
    let environment: Environment
    let receiver: Value
    let homeClass: STClass?
    let homeID: Int
    let isWorkspace: Bool
    var methodSide: MethodSide = .instance
    var debuggerOrigin: DebuggerOrigin?
}

enum MessageLookup {
    case normal
    case instanceSuper(STClass)
    case classSuper(STClass?)
}

final class STBlock {
    let parameters: [String]
    let body: BytecodeBody
    let referenceBody: Body?
    private var capturedContext: Context?
    var context: Context {
        get {
            guard let capturedContext else { preconditionFailure("Using a collected block without a GC root.") }
            return capturedContext
        }
        set { capturedContext = newValue }
    }

    init(parameters: [String], body: BytecodeBody, context: Context, referenceBody: Body? = nil) {
        self.parameters = parameters
        self.body = body
        self.referenceBody = referenceBody
        capturedContext = context
    }

    func clearReferences() { capturedContext = nil }
}

struct ReturnSignal: Error {
    // Execution never crosses an actor boundary; this is interpreter control flow.
    nonisolated(unsafe) let value: Value
    let homeID: Int
}

public struct MethodInfo: Identifiable, Sendable {
    public var id: String { selector }
    public let selector: String
    public let source: String
    public let isPrimitive: Bool
}

public struct ClassInfo: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let superclass: String?
    public let fields: [String]
    public let methods: [MethodInfo]
    public let classMethods: [MethodInfo]
}

public struct BindingInfo: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let value: String
    public let className: String
}

public struct EvaluationResult: Sendable {
    public let value: String?
    public let error: String?
    /// A failed Smalltalk operation, distinct from an invalid native projection.
    public let executionError: String?
    public let transcript: String
    public let classes: [ClassInfo]
    public let bindings: [BindingInfo]
    public let windows: [ToolWindowInfo]
    public let activeWindowID: Int64?
    public let windowCommands: WindowCommandBatch
    public let toolRequests: [NativeToolRequest]
    public let changes: [ChangeInfo]
    public let savedChangeSequence: Int64
    public let changesPath: String?
}

/// An isolated, persistent object space. Evaluations run away from the UI actor.
public actor SmalltalkSession {
    let worker = InterpreterWorker()

    public init() {}

    public func evaluate(_ source: String) async -> EvaluationResult {
        await worker.submit { $0.run(source) }
    }

    public func inspectSource(_ source: String) async -> EvaluationResult {
        await worker.submit { $0.run(source, inspectingResult: true) }
    }

    public func snapshot() async -> EvaluationResult { await worker.submit { $0.snapshot() } }

    public func compile(_ source: String, in className: String, side: MethodSide = .instance) async -> EvaluationResult {
        await worker.submit { runtime in
            runtime.transcript = ""
            runtime.steps = 0
            runtime.depth = 0
            do {
                guard let stClass = runtime.classes[className] else { throw SmalltalkError("Class \(className) does not exist.") }
                let selector = try runtime.compile(source, in: stClass, side: side)
                return runtime.finishEvaluation(value: "\(side.displayName(for: className)) » \(selector)")
            } catch { return runtime.snapshot(error: error.localizedDescription) }
        }
    }

    public func reset() async -> EvaluationResult {
        await worker.submit { runtime in
            runtime = SmalltalkRuntime()
            return runtime.snapshot()
        }
    }
}

final class SmalltalkRuntime {
    var journal = SourceJournal()
    var catalogDirty = false
    var evaluatingToolSource = false
    var capturingTestPhase = false
    var toolRequests: [NativeToolRequest] = []
    var objectInspectors: [UUID: Value] = [:]
    var changesBrowser: Value?
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
        func add(_ name: String, _ superclass: String? = "Object") {
            let stClass = STClass(name, superclass: superclass.flatMap { classes[$0] })
            classes[name] = stClass
            globals[name] = .classObject(stClass)
        }
        add("Object", nil)
        add("Class")
        add("UndefinedObject")
        add("Boolean")
        add("True", "Boolean")
        add("False", "Boolean")
        add("Number")
        add("Integer", "Number")
        add("SmallInteger", "Integer")
        add("String")
        add("Symbol")
        add("Array")
        add("BlockClosure")
        add("Transcript")
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

    func run(_ source: String, inspectingResult: Bool = false) -> EvaluationResult {
        transcript = ""
        steps = 0
        depth = 0
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

    func evaluate(_ expression: Expression, context: Context) throws -> Value {
        try enter()
        defer { depth -= 1 }
        do {
            switch expression.kind {
            case .literal(let literal): return try value(literal)
            case .variable(let name): return try variable(name, context: context)
            case .assignment(let name, let expression):
                let value = try evaluate(expression, context: context)
                try assign(name, value: value, context: context)
                return value
            case .send(let receiverExpression, let selector, let arguments):
                let (receiver, lookup) = try messageReceiver(receiverExpression, context: context)
                return try evaluateMessage(receiver, selector, arguments, context: context, startingAt: lookup)
            case .cascade(let receiverExpression, let messages):
                let (receiver, lookup) = try messageReceiver(receiverExpression, context: context)
                return try withRoots([receiver]) { _ in
                    var result = receiver
                    for message in messages {
                        result = try evaluateMessage(receiver, message.selector, message.arguments, context: context, startingAt: lookup)
                    }
                    return result
                }
            case .block(let parameters, let body):
                return .block(try block(parameters: parameters, body: BytecodeBody.lower(body), context: context, referenceBody: body))
            case .returnValue(let expression):
                try checkHomeForReturn(context)
                throw ReturnSignal(value: try evaluate(expression, context: context), homeID: context.homeID)
            }
        } catch var error as SmalltalkError {
            error.locate(at: expression.position, in: context)
            throw error
        }
    }

    func checkHomeForReturn(_ context: Context) throws {
        guard activeHomes.contains(context.homeID) else {
            throw SmalltalkError("The home context of this block has already returned, so ^ cannot return from it.")
        }
    }

    private func evaluateMessage(_ receiver: Value, _ selector: String, _ arguments: [Expression], context: Context, startingAt lookup: MessageLookup) throws -> Value {
        // Earlier operands stay live while a later argument may redefine a class.
        let rootCount = evaluationRoots.count
        evaluationRoots.append(receiver)
        pendingMessages.append((receiver, lookup))
        defer {
            evaluationRoots.removeSubrange(rootCount...)
            pendingMessages.removeLast()
        }
        var values: [Value] = []
        for argument in arguments {
            let value = try evaluate(argument, context: context)
            values.append(value)
            evaluationRoots.append(value)
        }
        return try send(receiver, selector, values, startingAt: lookup)
    }

    func messageReceiver(_ expression: Expression, context: Context) throws -> (Value, MessageLookup) {
        if case .variable("super") = expression.kind { return (context.receiver, try superLookup(context)) }
        return (try evaluate(expression, context: context), .normal)
    }

    func superLookup(_ context: Context) throws -> MessageLookup {
        if context.methodSide == .classSide, let home = context.homeClass { return .classSuper(home.superclass) }
        guard let superclass = context.homeClass?.superclass else { throw SmalltalkError("super is unavailable here.") }
        return .instanceSuper(superclass)
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

    func lookupMethod(_ selector: String, on receiver: Value, startingAt lookup: MessageLookup = .normal) -> (Method, STClass, MethodSide)? {
        let classStart: STClass?
        let instanceStart: STClass
        switch lookup {
        case .normal:
            if case .classObject(let target) = receiver { classStart = target } else { classStart = nil }
            instanceStart = classOf(receiver)
        case .classSuper(let parent):
            classStart = parent
            instanceStart = classOf(receiver)
        case .instanceSuper(let parent):
            classStart = nil
            instanceStart = parent
        }
        if let (method, owner) = classStart?.lookup(selector, side: .classSide) { return (method, owner, .classSide) }
        if let (method, owner) = instanceStart.lookup(selector) { return (method, owner, .instance) }
        return nil
    }

    func send(_ receiver: Value, _ selector: String, _ arguments: [Value], startingAt lookup: MessageLookup = .normal) throws -> Value {
        try withRoots([receiver] + arguments) { _ in
            try enter()
            defer { depth -= 1 }
            guard arguments.count == CodeValidator.arity(of: selector) else { throw SmalltalkError("Wrong number of arguments for \(selector).") }
            if let (method, owner, side) = lookupMethod(selector, on: receiver, startingAt: lookup) {
                return try invoke(method, owner: owner, receiver: receiver, arguments: arguments, side: side)
            }
            if let result = try primitive(receiver, selector, arguments) { return result }
            throw SmalltalkError("\(classOf(receiver).name) does not understand \(selector).")
        }
    }

    func invoke(_ method: Method, owner: STClass, receiver: Value, arguments: [Value], side: MethodSide) throws -> Value {
        try withRoots([receiver] + arguments) { _ in
            guard method.parameters.count == arguments.count else { throw SmalltalkError("Wrong number of arguments for \(method.selector).") }
            let environment = try environment()
            for (name, value) in zip(method.parameters, arguments) { environment.values[name] = value }
            nextHome += 1
            let homeID = nextHome
            activeHomes.insert(homeID)
            defer { activeHomes.remove(homeID) }
            let origin = compilationMode ? nil : DebuggerOrigin(source: method.source, selector: method.selector)
            let context = Context(environment: environment, receiver: receiver, homeClass: owner, homeID: homeID,
                                  isWorkspace: false, methodSide: side, debuggerOrigin: origin)
            do {
                _ = try execute(method.body, context: context, referenceBody: method.referenceBody)
                return receiver
            } catch let signal as ReturnSignal where signal.homeID == homeID { return signal.value }
        }
    }

    func invokeBlock(_ value: Value, _ arguments: [Value] = []) throws -> Value {
        try withRoots([value] + arguments) { _ in
            guard case .block(let block) = value else { throw SmalltalkError("Expected a block [...].") }
            guard block.parameters.count == arguments.count else { throw SmalltalkError("Expected \(block.parameters.count) block arguments, got \(arguments.count).") }
            try enter()
            defer { depth -= 1 }
            let environment = try environment(parent: block.context.environment)
            for (name, value) in zip(block.parameters, arguments) { environment.values[name] = value }
            let lexical = block.context
            let context = Context(environment: environment, receiver: lexical.receiver, homeClass: lexical.homeClass,
                                  homeID: lexical.homeID, isWorkspace: lexical.isWorkspace, methodSide: lexical.methodSide,
                                  debuggerOrigin: lexical.debuggerOrigin)
            return try execute(block.body, context: context, referenceBody: block.referenceBody, debuggerKind: .block)
        }
    }

    @discardableResult
    func compile(_ source: String, in stClass: STClass, side: MethodSide = .instance,
                 validating validate: ((Method) throws -> Void)? = nil) throws -> String {
        guard !compilationMode else { throw SmalltalkError("Compilation is already in progress.") }
        let method = try compileMethod(source, fields: stClass.fields(for: side))
        try validate?(method)
        guard stClass[side].count < 512 || stClass[side][method.selector] != nil else { throw SmalltalkError("Too many methods in \(side.displayName(for: stClass.name)).") }
        if recordingChanges {
            try journal.append(kind: .method, className: stClass.name, selector: method.selector, side: side, source: source)
        }
        stClass[side][method.selector] = method
        catalogDirty = true
        return method.selector
    }

    func printValue(_ value: Value, depth: Int = 0) -> String {
        guard depth < 5 else { return "…" }
        switch value {
        case .integer(let n): return String(n)
        case .string(let s): return "'\(s.replacingOccurrences(of: "'", with: "''"))'"
        case .symbol(let s): return "#\(s)"
        case .boolean(let b): return b ? "true" : "false"
        case .nilValue: return "nil"
        case .classObject(let stClass): return stClass.name
        case .object(let object):
            let fields = object.stClass.fields.prefix(8).map { "\($0): \(printValue(object.fields[$0] ?? .nilValue, depth: depth + 1))" }.joined(separator: ", ")
            return fields.isEmpty ? "a \(object.stClass.name)" : "a \(object.stClass.name) (\(fields))"
        case .array(let array):
            let values = array.elements.prefix(32).map { printValue($0, depth: depth + 1) }.joined(separator: " ")
            return "#(\(values)\(array.elements.count > 32 ? " …" : ""))"
        case .block(let block): return "[Block · \(block.parameters.count) arguments]"
        case .transcript: return "Transcript"
        }
    }

    func snapshot(value: String? = nil, error: String? = nil, requests: [NativeToolRequest] = []) -> EvaluationResult {
        var presentationError: String?
        do { try synchronizeChangesBrowser() } catch { presentationError = error.localizedDescription }
        let infos = classes.values.sorted { $0.name < $1.name }.map { stClass in
            ClassInfo(name: stClass.name, superclass: stClass.superclass?.name, fields: stClass.fields,
                      methods: reflectedMethods(on: stClass, side: .instance), classMethods: reflectedMethods(on: stClass, side: .classSide))
        }
        let bindings = bindingInfos()
        let desktop = projectWindows()
        return EvaluationResult(value: value, error: error ?? desktop.error ?? presentationError, executionError: error, transcript: transcript, classes: infos, bindings: bindings, windows: desktop.windows, activeWindowID: desktop.activeID, windowCommands: projectWindowCommands(desktop.windows, active: desktop.activeID, valid: desktop.error == nil), toolRequests: requests, changes: Array(journal.records.suffix(2000)), savedChangeSequence: journal.savedSequence, changesPath: journal.url?.path)
    }
    func bindingInfos() -> [BindingInfo] {
        return globals.compactMap { name, value -> BindingInfo? in
            if ["Desktop", "ToolVM", "TranscriptBuffer"].contains(name) { return nil }
            if case .classObject = value { return nil }
            if case .transcript = value { return nil }
            return BindingInfo(name: name, value: printValue(value), className: classOf(value).name)
        }.sorted { $0.name < $1.name }
    }
}
