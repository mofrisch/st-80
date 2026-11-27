import Foundation

enum ImageCodec {
    static let version = 10
    static let supportedVersions = 6...version
    static let maxBytes = 32 * 1_024 * 1_024
    static let maxNodes = 40_000

    static func encode(_ runtime: SmalltalkRuntime, workspace: String, transcript: String) throws -> Data {
        let archive = try capture(runtime, workspace: workspace, transcript: transcript, includesCode: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(archive)
        guard data.count <= maxBytes else { throw SmalltalkError("Image exceeds the 32 MiB limit.") }
        return data
    }

    static func capture(_ runtime: SmalltalkRuntime, workspace: String, transcript: String, includesCode: Bool) throws -> ImageArchive {
        guard runtime.activeHomes.isEmpty else { throw SmalltalkError("Images can only be saved between evaluations.") }
        if let error = runtime.projectWindows().error {
            throw SmalltalkError("Could not save the image: \(error)")
        }
        var ids: [ObjectIdentifier: Int] = [:]
        var pending: [HeapReference] = []

        func register(_ object: AnyObject, _ node: HeapReference) throws -> Int {
            let identity = ObjectIdentifier(object)
            if let id = ids[identity] { return id }
            guard pending.count < maxNodes else { throw SmalltalkError("An image can contain at most 40,000 reachable objects.") }
            let id = pending.count
            ids[identity] = id
            pending.append(node)
            return id
        }

        func value(_ value: Value) throws -> ImageValue {
            switch value {
            case .integer(let n): return .integer(n)
            case .largeInteger(let n): return .largeInteger(n)
            case .fraction(let value): return .fraction(value)
            case .scaledDecimal(let value): return .scaledDecimal(value)
            case .character(let codePoint): return .character(codePoint)
            case .float(let number): return .float(number)
            case .string(let s): return .string(s)
            case .symbol(let s): return .symbol(s)
            case .boolean(let b): return .boolean(b)
            case .nilValue: return .nilValue
            case .classObject(let c):
                if let owner = c.instanceClass { return .metaclass(owner.name) }
                return .classObject(c.name)
            case .transcript: return .transcript
            case .object(let object): return .reference(try register(object, .object(object)))
            case .array(let array): return .reference(try register(array, .array(array)))
            case .block(let block): return .reference(try register(block, .block(block)))
            }
        }

        func bindings(_ bindings: [String: Value]) throws -> [String: ImageValue] {
            var result: [String: ImageValue] = [:]
            for name in bindings.keys.sorted() { result[name] = try value(bindings[name]!) }
            return result
        }

        let globals = try bindings(runtime.globals)
        let classes = try runtime.classes.values.sorted { $0.name < $1.name }.map { stClass in
            let state = try bindings(stClass.classState)
            let classVariables = try bindings(stClass.classVariables)
            let classFields = stClass.metaclass.ownFields
            return ImageClass(name: stClass.name, superclass: stClass.superclass?.name, fields: stClass.ownFields,
                              methods: stClass.methods.mapValues(\.source),
                              classMethods: stClass.classMethods.isEmpty ? nil : stClass.classMethods.mapValues(\.source),
                              classFields: classFields.isEmpty ? nil : classFields, classState: state.isEmpty ? nil : state,
                              classVariables: classVariables.isEmpty ? nil : classVariables,
                              sharedPools: stClass.sharedPools.isEmpty ? nil : stClass.sharedPools,
                              indexedStorage: stClass.ownIndexedStorage)
        }
        var sharedPools: [String: [String: ImagePoolBinding]] = [:]
        for poolName in runtime.sharedPools.keys.sorted() {
            let pool = runtime.sharedPools[poolName]!
            var encodedPool: [String: ImagePoolBinding] = [:]
            for name in pool.keys.sorted() {
                let binding = pool[name]!
                encodedPool[name] = ImagePoolBinding(value: try value(binding.value), kind: binding.kind)
            }
            sharedPools[poolName] = encodedPool
        }

        var nodes: [ImageNode] = []
        var index = 0
        while index < pending.count {
            switch pending[index] {
            case .object(let object):
                let fields = try bindings(object.fields)
                let indexedFields = object.indexedFields.isEmpty ? nil : try object.indexedFields.map(value)
                nodes.append(.object(ImageObject(className: object.stClass.name, fields: fields, indexedFields: indexedFields)))
            case .array(let array): nodes.append(.array(try array.elements.map(value)))
            case .environment(let environment):
                let parent = try environment.parent.map { try register($0, .environment($0)) }
                nodes.append(.environment(ImageEnvironment(parent: parent, values: try bindings(environment.values))))
            case .block(let block):
                let environment = try register(block.context.environment, .environment(block.context.environment))
                let side = block.context.methodSide
                nodes.append(.block(ImageBlock(parameters: block.parameters, body: block.body, environment: environment,
                                               receiver: try value(block.context.receiver), homeClass: block.context.homeClass?.name,
                                               isWorkspace: block.context.isWorkspace, methodSide: side == .classSide ? side : nil,
                                               initializingPool: block.context.initializingPool)))
            }
            index += 1
        }
        try runtime.validateMVCState(in: pending.compactMap { node in
            if case .object(let object) = node { return object }
            return nil
        })
        let code = includesCode ? runtime.classes.mapValues { $0.methods.mapValues(MethodCode.init) }.filter { !$0.value.isEmpty } : nil
        let classCode = includesCode ? runtime.classes.mapValues { $0.classMethods.mapValues(MethodCode.init) }.filter { !$0.value.isEmpty } : [:]
        return ImageArchive(classes: classes, globals: globals, nodes: nodes, workspace: workspace, transcript: transcript,
                            executableMethods: code, executableClassMethods: classCode.isEmpty ? nil : classCode,
                            declaredGlobals: runtime.declaredGlobals.isEmpty ? nil : runtime.declaredGlobals,
                            sharedPools: sharedPools.isEmpty ? nil : sharedPools)
    }

    static func decode(_ data: Data) throws -> (SmalltalkRuntime, LoadedImage) {
        guard data.count <= maxBytes else { throw SmalltalkError("Image exceeds the 32 MiB limit.") }
        let decoder = try checkedDecoder(for: data)
        let archive: ImageArchive
        do { archive = try decoder.decode(ImageArchive.self, from: data) }
        catch { throw SmalltalkError("The image is corrupt or incomplete: \(error.localizedDescription)") }
        do { return try restore(archive) }
        catch { throw SmalltalkError("Could not load the image: \(error.localizedDescription)") }
    }

    static func checkedDecoder(for data: Data) throws -> JSONDecoder {
        struct Header: Decodable { let format: String; let version: Int }
        let decoder = JSONDecoder()
        let header: Header
        do { header = try decoder.decode(Header.self, from: data) }
        catch { throw SmalltalkError("The file is not a valid Smalltalk/80 image.") }
        guard header.format == "st80-image" else { throw SmalltalkError("Unknown image format. Expected a Smalltalk/80 image.") }
        guard supportedVersions.contains(header.version) else {
            throw SmalltalkError("Image version \(header.version) is unsupported. Supported versions are \(supportedVersions.lowerBound) through \(version).")
        }
        return decoder
    }

    private enum Shell {
        case value(Value), environment(Environment)
    }

    static func restore(_ image: ImageArchive, journal: SourceJournal? = nil) throws -> (SmalltalkRuntime, LoadedImage) {
        guard image.format == "st80-image", supportedVersions.contains(image.version), let executableMethods = image.executableMethods else {
            throw invalid("The executable method store is missing or incompatible.")
        }
        guard image.classes.count <= SmalltalkRuntime.classLimit, image.globals.count <= 1_152 + SmalltalkRuntime.floatAliases.count,
              image.nodes.count <= maxNodes else { throw invalid("Size limits exceeded.") }
        // No bootstrap, user code, initialize messages or block execution on load.
        let runtime = SmalltalkRuntime(bootstrap: false)
        // The shells are not reachable from globals until the entire graph has
        // been connected and validated. The fresh heap still enforces its hard
        // allocation budget while collection is suspended.
        try runtime.memory.withCollectionSuspended {
            try restoreGraph(image, executableMethods: executableMethods, into: runtime)
        }
        if let journal { runtime.journal = journal }
        let evaluation = runtime.snapshot()
        if let error = evaluation.windowProjectionError { throw SmalltalkError(error) }
        return (runtime, LoadedImage(evaluation: evaluation, workspace: image.workspace, transcript: image.transcript))
    }

    private static func restoreGraph(_ image: ImageArchive, executableMethods: [String: [String: MethodCode]], into runtime: SmalltalkRuntime) throws {
        let supportsANSIStorage = image.version >= 10
        var records: [String: ImageClass] = [:]
        for record in image.classes {
            guard supportsANSIStorage || record.classVariables == nil && record.sharedPools == nil && record.indexedStorage == nil else {
                throw invalid("ANSI class metadata requires image version 10.")
            }
            guard records.updateValue(record, forKey: record.name) == nil else { throw invalid("Duplicate class \(record.name).") }
        }
        let declaredGlobals = image.declaredGlobals ?? [:]
        let sharedPools = image.sharedPools ?? [:]
        guard supportsANSIStorage || image.declaredGlobals == nil && image.sharedPools == nil else {
            throw invalid("ANSI global and pool metadata requires image version 10.")
        }
        try validateNames(Array(declaredGlobals.keys))
        try validateNames(Array(sharedPools.keys))
        guard declaredGlobals.keys.allSatisfy({
            image.globals[$0] != nil && records[$0] == nil && runtime.globals[$0] == nil && sharedPools[$0] == nil
        }) else { throw invalid("Invalid declared global binding.") }
        // Class layouts require declared pools. Fill their values after all object shells exist.
        for (name, pool) in sharedPools {
            guard case .nilValue? = image.globals[name], records[name] == nil, runtime.globals[name] == nil,
                  pool.count <= 1_000 else {
                throw invalid("Invalid pool binding for \(name).")
            }
            try validateNames(Array(pool.keys))
            runtime.sharedPools[name] = pool.mapValues { PoolBinding(kind: $0.kind) }
            runtime.globals[name] = .nilValue
        }
        for builtin in runtime.classes.values {
            if records[builtin.name] == nil, SmalltalkRuntime.additiveBuiltinNames.contains(builtin.name) { continue }
            guard let record = records[builtin.name], record.classFields?.isEmpty != false,
                  record.classVariables?.isEmpty != false, record.sharedPools?.isEmpty != false, record.indexedStorage == nil else {
                throw invalid("Built-in class \(builtin.name) is missing or has an invalid layout.")
            }
            let newLayout = record.superclass == builtin.superclass?.name && record.fields == builtin.ownFields
            let oldSequenceLayout = image.version < 8 && ["Array", "String", "Symbol"].contains(builtin.name)
                && record.superclass == "Object" && record.fields.isEmpty
            let oldCollectionHierarchy = image.version < 9 && builtin.name == "SequenceableCollection"
                && record.superclass == "Object" && record.fields.isEmpty
            guard newLayout || oldSequenceLayout || oldCollectionHierarchy else {
                throw invalid("Built-in class \(builtin.name) has an invalid layout.")
            }
        }
        var remaining = image.classes.filter { !SmalltalkRuntime.builtinNames.contains($0.name) }
        while !remaining.isEmpty {
            let previous = remaining.count
            var unresolved: [ImageClass] = []
            for record in remaining {
                guard supportsANSIStorage || record.superclass != nil else { throw invalid("Superclass is missing.") }
                if let parentName = record.superclass, runtime.classes[parentName] == nil {
                    unresolved.append(record)
                    continue
                }
                let parent = record.superclass.flatMap { runtime.classes[$0] }
                let stClass = try runtime.subclass(of: parent, name: record.name, fields: record.fields.joined(separator: " "),
                                                   classFields: record.classFields ?? [],
                                                   classVariables: record.classVariables?.keys.sorted() ?? [],
                                                   pools: record.sharedPools ?? [], indexedStorage: record.indexedStorage,
                                                   ansi: supportsANSIStorage)
                guard stClass.ownFields == record.fields else { throw invalid("Invalid instance variables.") }
            }
            remaining = unresolved
            guard remaining.count < previous else { throw invalid("The class hierarchy contains a cycle or an unknown superclass.") }
        }
        for side in MethodSide.allCases {
            let executable = side == .instance ? executableMethods : image.executableClassMethods ?? [:]
            guard Set(executable.keys) == Set(image.classes.filter { !$0[side].isEmpty }.map(\.name)) else {
                throw invalid("The executable methods do not match the class table.")
            }
            for record in image.classes {
                let code = executable[record.name] ?? [:]
                let sources = record[side]
                guard sources.count <= SmalltalkRuntime.methodsPerSideLimit, let stClass = runtime.classes[record.name],
                      Set(code.keys) == Set(sources.keys) else { throw invalid("Invalid method table.") }
                for (selector, source) in sources {
                    guard let methodCode = code[selector] else { throw invalid("Executable method is missing.") }
                    stClass[side][selector] = try methodCode.validatedMethod(selector: selector, source: source)
                }
            }
        }
        try runtime.validateCompilerClasses()
        if records["ScaledDecimal"] == nil { try runtime.upgradeCompilerForScaledDecimals() }
        if records["Exception"] == nil { try runtime.installExceptionProtocol() }
        var addedClasses: Set<String> = []
        var missingClasses = image.version < 9 ? SmalltalkRuntime.shippedCollectionNames : []
        // Version 9 images can predate these classes. Preserve existing
        // bindings, including small libraries authored under the same names.
        for names in [SmalltalkRuntime.shippedDictionaryNames, SmalltalkRuntime.shippedStreamNames,
                      SmalltalkRuntime.shippedFileStreamNames, SmalltalkRuntime.shippedDateTimeNames,
                      SmalltalkRuntime.shippedNotificationNames] {
            if names.allSatisfy({ records[$0] == nil && image.globals[$0] == nil }) {
                missingClasses.formUnion(names)
            }
        }
        if !missingClasses.isEmpty {
            let library = try SystemLibrary.shared.get()
            if image.version < 8 { try library.installANSIProtocols(in: runtime) }
            addedClasses = try library.installANSIClasses(missingClasses, in: runtime)
        }
        if image.version < 10 { try SystemLibrary.shared.get().upgradeANSIBehavior(in: runtime) }
        let library = try? SystemLibrary.shared.get()
        let refreshBrowserOrganization = try library?.upgradeBrowserOrganization(in: runtime, classesAdded: !addedClasses.isEmpty) ?? false
        guard runtime.classes["UIBinding"]?.lookup("reconcileMount:") != nil else {
            throw invalid("The image is missing UIBinding>>reconcileMount:. Start a fresh session.")
        }

        // Allocate first, connect second: this preserves identity and cycles.
        var shells: [Shell] = []
        var placeholderEnvironment: Environment?
        for node in image.nodes {
            switch node {
            case .object(let record):
                guard let stClass = runtime.classes[record.className],
                      stClass === runtime.classes["String"] || SmalltalkRuntime.heapBuiltinNames.contains(stClass.name)
                        || !SmalltalkRuntime.builtinNames.contains(stClass.name),
                      Set(record.fields.keys) == Set(stClass.fields),
                      record.indexedFields == nil || supportsANSIStorage && stClass.indexedStorage != nil else {
                    throw invalid("Invalid object layout.")
                }
                let object = try runtime.object(stClass, indexedCount: record.indexedFields?.count ?? 0)
                shells.append(.value(.object(object)))
            case .array(let values):
                shells.append(.value(try runtime.array(count: values.count)))
            case .environment:
                shells.append(.environment(try runtime.environment()))
            case .block(let record):
                try record.body.validate(parameters: record.parameters)
                if placeholderEnvironment == nil { placeholderEnvironment = try runtime.environment() }
                let context = Context(environment: placeholderEnvironment!, receiver: .nilValue, homeClass: nil, homeID: 0, isWorkspace: false)
                shells.append(.value(.block(try runtime.block(parameters: record.parameters, body: record.body, context: context))))
            }
        }

        func shell(_ id: Int) throws -> Shell {
            guard shells.indices.contains(id) else { throw invalid("Invalid object reference \(id).") }
            return shells[id]
        }
        func environment(_ id: Int) throws -> Environment {
            guard case .environment(let environment) = try shell(id) else { throw invalid("Expected a reference to a lexical context.") }
            return environment
        }
        func value(_ record: ImageValue) throws -> Value {
            switch record {
            case .integer(let n): return .integer(n)
            case .largeInteger(let n): return runtime.integerValue(n)
            case .fraction(let value): return .fraction(value)
            case .scaledDecimal(let value): return .scaledDecimal(value)
            case .character(let codePoint):
                guard Unicode.Scalar(codePoint) != nil else { throw invalid("Invalid character code point.") }
                return .character(codePoint)
            case .float(let number):
                guard number.isFinite else { throw invalid("Invalid floating-point number.") }
                return .float(number)
            case .string(let s): return .string(s)
            case .symbol(let s): return .symbol(s)
            case .boolean(let b): return .boolean(b)
            case .nilValue: return .nilValue
            case .transcript: return .transcript
            case .classObject(let name):
                guard let stClass = runtime.classes[name] else { throw invalid("Unknown class reference \(name).") }
                return .classObject(stClass)
            case .metaclass(let name):
                guard let stClass = runtime.classes[name] else { throw invalid("Unknown metaclass owner \(name).") }
                return .classObject(stClass.metaclass)
            case .reference(let id):
                guard case .value(let value) = try shell(id) else { throw invalid("A lexical context cannot be used as a Smalltalk value.") }
                return value
            }
        }

        // Parent links must form lexical trees, even though scope VALUES may cycle.
        var checked: Set<Int> = []
        for (id, node) in image.nodes.enumerated() {
            guard case .environment = node else { continue }
            var path: Set<Int> = []
            var current: Int? = id
            while let id = current, !checked.contains(id) {
                guard path.insert(id).inserted, image.nodes.indices.contains(id), case .environment(let record) = image.nodes[id] else { throw invalid("Invalid or cyclic context chain.") }
                current = record.parent
            }
            checked.formUnion(path)
        }

        for (id, node) in image.nodes.enumerated() {
            switch (node, shells[id]) {
            case (.object(let record), .value(.object(let object))):
                object.fields = try record.fields.mapValues(value)
                if let indexedFields = record.indexedFields {
                    let elements = try indexedFields.map(value)
                    guard object.stClass.indexedStorage != .byte || elements.allSatisfy(SmalltalkRuntime.isByte) else {
                        throw invalid("Invalid byte-indexed object contents.")
                    }
                    object.indexedFields = elements
                }
                if refreshBrowserOrganization, runtime.isUIClass(object.stClass, named: "BrowserOrganization"),
                   object.fields["systemProtocols"] != nil {
                    object.fields["systemProtocols"] = .nilValue
                }
                if object.stClass === runtime.classes["String"] {
                    guard case .string(let text)? = object.fields["_contents"], text.utf8.count <= 65_536 else {
                        throw invalid("Invalid mutable string contents.")
                    }
                }
            case (.array(let values), .value(.array(let array))): array.elements = try values.map(value)
            case (.environment(let record), .environment(let scope)):
                try validateNames(Array(record.values.keys))
                scope.parent = try record.parent.map(environment)
                scope.values = try record.values.mapValues(value)
            case (.block(let record), .value(.block(let block))):
                let homeClass = try record.homeClass.map { name in
                    guard let stClass = runtime.classes[name] else { throw invalid("Unknown home class.") }
                    return stClass
                }
                let side = record.methodSide ?? .instance
                let receiver = try value(record.receiver)
                if side == .classSide {
                    guard case .classObject(let target) = receiver, let homeClass, !record.isWorkspace else { throw invalid("Invalid class method context.") }
                    var ancestor: STClass? = target
                    while let current = ancestor, current !== homeClass { ancestor = current.superclass }
                    guard ancestor != nil else { throw invalid("Invalid class method home class.") }
                }
                if let pool = record.initializingPool {
                    guard supportsANSIStorage, runtime.sharedPools[pool] != nil, homeClass == nil,
                          runtime.isNil(receiver), !record.isWorkspace, side == .instance else {
                        throw invalid("Invalid pool initializer context.")
                    }
                }
                block.context = Context(environment: try environment(record.environment), receiver: receiver, homeClass: homeClass,
                                        homeID: 0, isWorkspace: record.isWorkspace, methodSide: side,
                                        initializingPool: record.initializingPool)
            default: throw invalid("The object table is inconsistent.")
            }
        }
        for record in image.classes {
            let stClass = runtime.classes[record.name]!
            let state = record.classState ?? [:]
            guard Set(state.keys) == Set(stClass.classState.keys) else { throw invalid("Invalid class instance variables for \(record.name).") }
            stClass.classState = try state.mapValues(value)
            stClass.classVariables = try (record.classVariables ?? [:]).mapValues(value)
        }
        for (name, pool) in sharedPools {
            runtime.sharedPools[name] = try pool.mapValues { binding in
                PoolBinding(value: try value(binding.value), kind: binding.kind)
            }
        }
        var globals = try image.globals.mapValues(value)
        for name in SmalltalkRuntime.additiveBuiltinNames.union(addedClasses) where records[name] == nil && globals[name] == nil {
            if let stClass = runtime.classes[name] { globals[name] = .classObject(stClass) }
        }
        for name in SmalltalkRuntime.floatAliases where globals[name] == nil { globals[name] = globals["Float"] }
        for name in runtime.classes.keys {
            if name == "Transcript" {
                guard case .transcript? = globals[name] else { throw invalid("Transcript is missing.") }
            } else {
                guard case .classObject(let stClass)? = globals[name], stClass === runtime.classes[name] else { throw invalid("Class binding \(name) is missing.") }
            }
        }
        guard Set(globals.keys).isDisjoint(with: ["nil", "true", "false", "self", "super", "thisContext"]) else { throw invalid("Reserved global variable.") }
        runtime.globals = globals
        runtime.declaredGlobals = declaredGlobals
        guard case .object(let desktop)? = globals["Desktop"], runtime.isUIClass(desktop.stClass, named: "DesktopManager"),
              case .object(let model)? = desktop.fields["model"], runtime.isUIClass(model.stClass, named: "DesktopModel") else {
            throw invalid("The image has no valid window manager.")
        }
        try runtime.validateMVCState()
        runtime.catalogDirty = refreshBrowserOrganization
        runtime.recordingChanges = true
    }

    private static func validateNames(_ names: [String]) throws {
        guard CodeValidator.validNames(names) else { throw invalid("Invalid variable names.") }
    }

    private static func invalid(_ message: String) -> SmalltalkError { SmalltalkError(message) }
}
