import Foundation

/// The ANSI Smalltalk Interchange Format wraps ordinary method and initializer
/// source in versioned chunks. The image's compiler still parses their contents.
enum SmalltalkInterchange {
    static let maximumBytes = 4 * 1_024 * 1_024
    private static let classSelector = "named:superclass:indexedInstanceVariables:instanceVariableNames:classVariableNames:sharedPools:classInstanceVariableNames:"

    struct ClassDeclaration {
        let name: String
        let superclass: String
        let indexedStorage: IndexedStorage?
        let fields: [String]
        let classVariables: [String]
        let pools: [String]
        let classFields: [String]
    }

    enum Entry {
        case classDefinition(ClassDeclaration)
        case global(String, constant: Bool)
        case pool(String)
        case poolVariable(pool: String, name: String, constant: Bool)
        case method(owner: String, side: MethodSide, Method)
        case initializer(owner: String, poolVariable: String?, syntax: Body, source: String)
    }

    static func recognizes(_ source: String) -> Bool {
        let source = source.first == "\u{FEFF}" ? source.dropFirst() : source[...]
        return source.prefixMatch(of: /(?:\s|"[^"]*")*Smalltalk(?:\s|"[^"]*")+interchangeVersion:/) != nil
    }

    static func names(in source: String) -> [String] {
        source.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func classDeclaration(in body: Body) throws -> ClassDeclaration? {
        guard case let (receiver, selector, arguments)? = send(in: body),
              receiver == "Class", selector == classSelector else { return nil }
        let storage: IndexedStorage?
        switch arguments[2].kind {
        case .literal(.symbol("none")): storage = nil
        case .literal(.symbol(let kind)):
            guard let valid = IndexedStorage(rawValue: kind) else { throw invalid("Unknown indexed storage \(kind).") }
            storage = valid
        default: throw invalid("Indexed storage must be #none, #byte or #object.")
        }
        return try ClassDeclaration(
            name: literalName(arguments[0]), superclass: literalText(arguments[1]), indexedStorage: storage,
            fields: nameList(arguments[3]), classVariables: nameList(arguments[4]), pools: nameList(arguments[5]),
            classFields: nameList(arguments[6])
        )
    }

    static func parse(_ source: String, in runtime: SmalltalkRuntime) throws -> [Entry] {
        let chunks = try chunks(in: source)
        guard let first = chunks.first,
              case let ("Smalltalk", "interchangeVersion:", arguments)? = send(in: try runtime.compileWorkspace(first)) else {
            throw invalid("The file must begin with a Smalltalk interchangeVersion: header.")
        }
        guard try literalText(arguments[0]) == "1.0" else { throw invalid("Unsupported interchange version. Expected 1.0.") }
        var entries: [Entry] = []
        var next = 1
        func bodyChunk() throws -> String {
            guard next < chunks.count else { throw invalid("Expected a method or initializer after its header.") }
            defer { next += 1 }
            return chunks[next]
        }
        while next < chunks.count {
            var chunk = next + 1
            do {
                let syntax = try runtime.compileWorkspace(chunks[next])
                next += 1
                if syntax.temporaries.isEmpty, syntax.expressions.isEmpty { continue }
                if let declaration = try classDeclaration(in: syntax) {
                    entries.append(.classDefinition(declaration))
                    continue
                }
                guard let (owner, selector, arguments) = send(in: syntax) else {
                    throw invalid("Expected a declaration, method header, initializer header or annotation.")
                }
                switch (owner, selector) {
                case ("Global", "variable:"), ("Global", "constant:"):
                    entries.append(.global(try literalName(arguments[0]), constant: selector == "constant:"))
                case ("Pool", "named:"):
                    entries.append(.pool(try literalName(arguments[0])))
                case ("Annotation", "key:value:"):
                    for argument in arguments { _ = try literalText(argument) }
                case (_, "variable:"), (_, "constant:"):
                    entries.append(.poolVariable(pool: owner, name: try literalName(arguments[0]), constant: selector == "constant:"))
                case (_, "method"), (_, "classMethod"):
                    let source = try bodyChunk()
                    chunk += 1
                    entries.append(.method(owner: owner, side: selector == "method" ? .instance : .classSide,
                                           try runtime.compileMethod(source)))
                case (_, "initializer"), (_, "initializerFor:"):
                    let variable = try arguments.first.map(literalName)
                    let source = try bodyChunk()
                    chunk += 1
                    entries.append(.initializer(owner: owner, poolVariable: variable, syntax: try runtime.compileWorkspace(source), source: source))
                default: throw invalid("Unsupported interchange header \(owner) \(selector).")
                }
            } catch {
                throw invalid("Chunk \(chunk). \(error.localizedDescription)")
            }
        }
        return entries
    }

    private static func chunks(in source: String) throws -> [String] {
        guard source.utf8.count <= maximumBytes else { throw invalid("The file exceeds 4 MiB.") }
        let source = source.first == "\u{FEFF}" ? source.dropFirst() : source[...]
        var bytes = source.utf8.makeIterator()
        var next = bytes.next()
        var current: [UInt8] = []
        var chunks: [String] = []
        while let byte = next {
            next = bytes.next()
            guard byte == 33 else { current.append(byte); continue }
            if next == 33 {
                current.append(byte)
                next = bytes.next()
            } else {
                chunks.append(String(decoding: current, as: UTF8.self))
                current.removeAll(keepingCapacity: true)
            }
        }
        guard String(decoding: current, as: UTF8.self).allSatisfy(\.isWhitespace) else {
            throw invalid("The last chunk is missing its ! separator.")
        }
        return chunks
    }

    private static func send(in body: Body) -> (String, String, [Expression])? {
        guard body.temporaries.isEmpty, body.expressions.count == 1,
              case .send(let receiver, let selector, let arguments) = body.expressions[0].kind,
              case .variable(let name) = receiver.kind else { return nil }
        return (name, selector, arguments)
    }

    private static func literalText(_ expression: Expression) throws -> String {
        guard case .literal(.string(let text)) = expression.kind else { throw invalid("Expected a quoted string.") }
        return text
    }

    private static func literalName(_ expression: Expression) throws -> String {
        let name = try literalText(expression)
        guard CodeValidator.validNames([name]) else { throw invalid("Invalid declaration name \(name).") }
        return name
    }

    private static func nameList(_ expression: Expression) throws -> [String] {
        let result = try names(in: literalText(expression))
        guard CodeValidator.validNames(result) else { throw invalid("Invalid or repeated name in a declaration.") }
        return result
    }

    static func invalid(_ message: String) -> SmalltalkError {
        SmalltalkError("ANSI Smalltalk interchange. " + message)
    }
}

extension SmalltalkRuntime {
    func superclass(named name: String) throws -> STClass? {
        if name.isEmpty || name == "nil" { return nil }
        guard let parent = classes[name] else { throw SmalltalkInterchange.invalid("Unknown superclass \(name).") }
        return parent
    }

    @discardableResult
    func defineInterchangeClass(_ definition: SmalltalkInterchange.ClassDeclaration) throws -> STClass {
        try subclass(of: superclass(named: definition.superclass), name: definition.name,
                     fields: definition.fields.joined(separator: " "), classFields: definition.classFields,
                     classVariables: definition.classVariables, pools: definition.pools,
                     indexedStorage: definition.indexedStorage, ansi: true)
    }

    func runInterchange(_ sources: [String]) -> EvaluationResult {
        beginEvaluation()
        do {
            _ = try importInterchange(sources)
            return finishEvaluation(value: "nil")
        } catch {
            return finishEvaluation(error: error.localizedDescription)
        }
    }

    func importInterchange(_ sources: [String]) throws -> Value {
        let entries = try sources.flatMap { try SmalltalkInterchange.parse($0, in: self) }
        try installInterchangeDeclarations(entries)
        for entry in entries {
            guard case .initializer(let owner, let poolVariable, let syntax, let source) = entry else { continue }
            if let poolVariable {
                let value = try executeSource(syntax, source: source, initializer: true, initializingPool: owner)
                sharedPools[owner]![poolVariable]!.value = value
                if sharedPools[owner]![poolVariable]!.kind == .constant {
                    sharedPools[owner]![poolVariable]!.kind = .initializedConstant
                }
            } else if let home = classes[owner] {
                _ = try executeSource(syntax, source: source, initializer: true, classHome: home)
            } else {
                let value = try executeSource(syntax, source: source, initializer: true)
                if owner != "Global" {
                    globals[owner] = value
                    if declaredGlobals[owner] == .constant { declaredGlobals[owner] = .initializedConstant }
                }
            }
        }
        return .nilValue
    }

    private func installInterchangeDeclarations(_ entries: [SmalltalkInterchange.Entry]) throws {
        let previousGlobals = globals
        let previousClasses = classes
        let previousPools = sharedPools
        let previousDeclaredGlobals = declaredGlobals
        let previousCatalog = catalogDirty
        let shouldRecord = recordingChanges
        recordingChanges = false
        defer { recordingChanges = shouldRecord }
        do {
            func reserveGlobal(_ name: String) throws {
                guard globals[name] == nil else { throw SmalltalkInterchange.invalid("\(name) already exists.") }
                guard globals.count < 1_024 else { throw SmalltalkInterchange.invalid("Too many global bindings.") }
                globals[name] = .nilValue
            }
            var declarations: [SmalltalkInterchange.ClassDeclaration] = []
            for entry in entries {
                switch entry {
                case .global(let name, let constant):
                    try reserveGlobal(name)
                    declaredGlobals[name] = constant ? .constant : .variable
                case .pool(let name):
                    try reserveGlobal(name)
                    sharedPools[name] = [:]
                case .classDefinition(let declaration): declarations.append(declaration)
                default: break
                }
            }
            for entry in entries {
                guard case .poolVariable(let pool, let name, let constant) = entry else { continue }
                guard let bindings = sharedPools[pool], bindings[name] == nil, bindings.count < 1_000 else {
                    throw SmalltalkInterchange.invalid("Unknown pool, duplicate variable, or full pool \(pool) for \(name).")
                }
                sharedPools[pool]![name] = PoolBinding(kind: constant ? .constant : .variable)
            }
            var changes: [ChangeInfo] = []
            while !declarations.isEmpty {
                var unresolved: [SmalltalkInterchange.ClassDeclaration] = []
                for declaration in declarations {
                    let parent = declaration.superclass
                    guard parent == "nil" || parent.isEmpty || classes[parent] != nil else {
                        unresolved.append(declaration)
                        continue
                    }
                    let stClass = try defineInterchangeClass(declaration)
                    changes.append(interchangeChange(.classDefinition, owner: stClass, source: definitionSource(for: stClass)))
                }
                guard unresolved.count < declarations.count else {
                    throw SmalltalkInterchange.invalid("Unknown or cyclic superclasses for \(unresolved.map(\.name).joined(separator: ", ")).")
                }
                declarations = unresolved
            }
            var methods: [(STClass, MethodSide, Method)] = []
            var selectors: [String: Set<String>] = [:]
            var initializers: Set<String> = []
            for entry in entries {
                switch entry {
                case .method(let owner, let side, let method):
                    guard let stClass = classes[owner] else { throw SmalltalkInterchange.invalid("Unknown method class \(owner).") }
                    let key = side.displayName(for: owner)
                    guard selectors[key, default: []].insert(method.selector).inserted else {
                        throw SmalltalkInterchange.invalid("Repeated method \(key) » \(method.selector).")
                    }
                    methods.append((stClass, side, method))
                    changes.append(interchangeChange(.method, owner: stClass, source: method.source, side: side, selector: method.selector))
                case .initializer(let owner, let variable, let syntax, _):
                    if let variable {
                        guard let binding = sharedPools[owner]?[variable] else {
                            throw SmalltalkInterchange.invalid("Unknown pool variable \(owner) » \(variable).")
                        }
                        guard binding.kind != .initializedConstant else {
                            throw SmalltalkInterchange.invalid("The constant \(owner) » \(variable) is already initialized.")
                        }
                    } else if owner != "Global", classes[owner] == nil, declaredGlobals[owner] == nil {
                        throw SmalltalkInterchange.invalid("Unknown initializer target \(owner).")
                    } else if declaredGlobals[owner] == .initializedConstant {
                        throw SmalltalkInterchange.invalid("The constant \(owner) is already initialized.")
                    }
                    if owner != "Global" || variable != nil {
                        let key = variable.map { "\(owner) \($0)" } ?? owner
                        guard initializers.insert(key).inserted else {
                            throw SmalltalkInterchange.invalid("Repeated initializer for \(key).")
                        }
                    }
                    try validateInterchangeAssignments(BytecodeBody.lower(syntax), in: classes[owner],
                                                       side: .classSide, pool: variable == nil ? nil : owner,
                                                       initializer: true)
                default: break
                }
            }
            for (stClass, side, method) in methods {
                let installed = Set(stClass[side].keys)
                guard installed.union(selectors[side.displayName(for: stClass.name)]!).count <= Self.methodsPerSideLimit else {
                    throw SmalltalkInterchange.invalid("Too many methods in \(side.displayName(for: stClass.name)).")
                }
                try validateInterchangeAssignments(method.body, in: stClass, side: side, locals: Set(method.parameters))
            }
            if shouldRecord { try journal.appendImportedRecords(changes) }
            for (stClass, side, method) in methods { stClass[side][method.selector] = method }
            catalogDirty = true
        } catch {
            globals = previousGlobals
            classes = previousClasses
            sharedPools = previousPools
            declaredGlobals = previousDeclaredGlobals
            catalogDirty = previousCatalog
            throw error
        }
    }

    private func interchangeChange(_ kind: ChangeInfo.Kind, owner: STClass, source: String,
                                   side: MethodSide = .instance, selector: String? = nil) -> ChangeInfo {
        ChangeInfo(id: "", sequence: 0, timestamp: .distantPast, kind: kind, className: owner.name, selector: selector,
                   superclass: kind == .classDefinition ? owner.superclass?.name : nil,
                   fields: kind == .classDefinition ? owner.ownFields : nil, source: source,
                   methodSide: side == .classSide ? side : nil,
                   classFields: kind == .classDefinition ? owner.metaclass.ownFields : nil)
    }

    private func validateInterchangeAssignments(_ body: BytecodeBody, in owner: STClass?, side: MethodSide,
                                                pool: String? = nil, locals: Set<String> = [], initializer: Bool = false) throws {
        let locals = locals.union(body.temporaries)
        for instruction in body.instructions {
            switch instruction.operation {
            case .makeBlock(let arguments, let block):
                try validateInterchangeAssignments(block, in: owner, side: side, pool: pool,
                                                   locals: locals.union(arguments), initializer: initializer)
            case .prepareSend(isSuper: true) where initializer:
                throw SmalltalkError("super is unavailable in an initializer.", at: instruction.position)
            case .load("self") where initializer && owner == nil:
                throw SmalltalkError("self is only available in a class initializer.", at: instruction.position)
            case .store(let name) where !locals.contains(name):
                if ["nil", "true", "false", "self", "super", "thisContext"].contains(name) {
                    throw SmalltalkError("Cannot assign to \(name) in this scope.", at: instruction.position)
                }
                if owner.map({ (side == .instance ? $0.fields : $0.metaclass.fields).contains(name) }) == true { continue }
                var found = owner
                while let scope = found, scope.classVariables[name] == nil { found = scope.superclass }
                if found != nil { continue }
                let pools = pool.map { [$0] } ?? owner?.sharedPools ?? []
                let bindings = pools.compactMap { sharedPools[$0]?[name] }
                let constant = bindings.first?.kind.isConstant
                    ?? (declaredGlobals[name]?.isConstant == true || classes[name] != nil || sharedPools[name] != nil
                        || name == "Transcript" || Self.floatAliases.contains(name))
                if bindings.count > 1 || constant {
                    throw SmalltalkError("Cannot assign to \(name) in this scope.", at: instruction.position)
                }
            default: break
            }
        }
    }

    func supportsIndexedOperation(_ selector: String, on receiver: Value) -> Bool {
        switch (selector, receiver) {
        case ("basicNew:", .classObject(let target)):
            return target === classes["Array"] || target.indexedStorage != nil
        case ("basicSize", .array), ("basicAt:", .array), ("basicAt:put:", .array):
            return true
        case ("basicSize", .object(let object)), ("basicAt:", .object(let object)), ("basicAt:put:", .object(let object)):
            return object.stClass.indexedStorage != nil
        default: return false
        }
    }

    func indexedPrimitive(_ receiver: Value, _ selector: String, _ arguments: [Value]) throws -> Value? {
        guard supportsIndexedOperation(selector, on: receiver) else { return nil }
        if selector == "basicNew:" {
            guard case .classObject(let target) = receiver else { return nil }
            let size = try integer(arguments[0])
            guard (0...Int64(arrayLimit)).contains(size) else { throw SmalltalkError("Invalid indexed instance size.") }
            if target === classes["Array"] { return try array(count: Int(size)) }
            return .object(try object(target, indexedCount: Int(size)))
        }
        switch receiver {
        case .object(let object):
            if selector == "basicSize" { return .integer(Int64(object.indexedFields.count)) }
            let offset = try index(arguments[0], count: object.indexedFields.count)
            if selector == "basicAt:" { return object.indexedFields[offset] }
            let value = arguments[1]
            if object.stClass.indexedStorage == .byte, !Self.isByte(value) {
                throw SmalltalkError("A byte slot requires an integer between 0 and 255.")
            }
            object.indexedFields[offset] = value
            return value
        case .array(let array):
            if selector == "basicSize" { return .integer(Int64(array.elements.count)) }
            let offset = try index(arguments[0], count: array.elements.count)
            if selector == "basicAt:" { return array.elements[offset] }
            array.elements[offset] = arguments[1]
            return arguments[1]
        default: return nil
        }
    }

    static func isByte(_ value: Value) -> Bool {
        if case .integer(let byte) = value { return (0...255).contains(byte) }
        return false
    }
}
