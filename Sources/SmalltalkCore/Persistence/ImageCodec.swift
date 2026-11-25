import Foundation

enum ImageCodec {
    static let version = 6
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
            case .string(let s): return .string(s)
            case .symbol(let s): return .symbol(s)
            case .boolean(let b): return .boolean(b)
            case .nilValue: return .nilValue
            case .classObject(let c): return .classObject(c.name)
            case .transcript: return .transcript
            case .object(let object): return .reference(try register(object, .object(object)))
            case .array(let array): return .reference(try register(array, .array(array)))
            case .block(let block): return .reference(try register(block, .block(block)))
            }
        }

        var globals: [String: ImageValue] = [:]
        for name in runtime.globals.keys.sorted() { globals[name] = try value(runtime.globals[name]!) }
        var nodes: [ImageNode] = []
        var index = 0
        while index < pending.count {
            switch pending[index] {
            case .object(let object):
                var fields: [String: ImageValue] = [:]
                for name in object.fields.keys.sorted() { fields[name] = try value(object.fields[name]!) }
                nodes.append(.object(ImageObject(className: object.stClass.name, fields: fields)))
            case .array(let array): nodes.append(.array(try array.elements.map(value)))
            case .environment(let environment):
                let parent = try environment.parent.map { try register($0, .environment($0)) }
                var values: [String: ImageValue] = [:]
                for name in environment.values.keys.sorted() { values[name] = try value(environment.values[name]!) }
                nodes.append(.environment(ImageEnvironment(parent: parent, values: values)))
            case .block(let block):
                let environment = try register(block.context.environment, .environment(block.context.environment))
                let side = block.context.methodSide
                nodes.append(.block(ImageBlock(parameters: block.parameters, body: block.body, environment: environment, receiver: try value(block.context.receiver), homeClass: block.context.homeClass?.name, isWorkspace: block.context.isWorkspace, methodSide: side == .classSide ? side : nil)))
            }
            index += 1
        }
        try runtime.validateMVCState(in: pending.compactMap { node in
            if case .object(let object) = node { return object }
            return nil
        })
        let classes = runtime.classes.values.sorted { $0.name < $1.name }.map {
            ImageClass(name: $0.name, superclass: $0.superclass?.name, fields: $0.ownFields, methods: $0.methods.mapValues(\.source), classMethods: $0.classMethods.isEmpty ? nil : $0.classMethods.mapValues(\.source))
        }
        let code = includesCode ? runtime.classes.mapValues { $0.methods.mapValues(MethodCode.init) }.filter { !$0.value.isEmpty } : nil
        let classCode = includesCode ? runtime.classes.mapValues { $0.classMethods.mapValues(MethodCode.init) }.filter { !$0.value.isEmpty } : [:]
        return ImageArchive(classes: classes, globals: globals, nodes: nodes, workspace: workspace, transcript: transcript, executableMethods: code, executableClassMethods: classCode.isEmpty ? nil : classCode)
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
        guard header.version == ImageCodec.version else { throw SmalltalkError("Image version \(header.version) is unsupported. Expected version \(ImageCodec.version).") }
        return decoder
    }

    private enum Shell {
        case value(Value), environment(Environment)
    }

    static func restore(_ image: ImageArchive, journal: SourceJournal? = nil) throws -> (SmalltalkRuntime, LoadedImage) {
        guard image.format == "st80-image", image.version == ImageCodec.version, let executableMethods = image.executableMethods else {
            throw invalid("The executable method store is missing or incompatible.")
        }
        guard image.classes.count <= 128, image.globals.count <= 1_152, image.nodes.count <= maxNodes else { throw invalid("Size limits exceeded.") }
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
        var records: [String: ImageClass] = [:]
        for record in image.classes {
            guard records.updateValue(record, forKey: record.name) == nil else { throw invalid("Duplicate class \(record.name).") }
        }
        for builtin in runtime.classes.values {
            guard let record = records[builtin.name], record.superclass == builtin.superclass?.name, record.fields == builtin.ownFields else {
                throw invalid("Built-in class \(builtin.name) is missing or has an invalid layout.")
            }
        }
        var remaining = image.classes.filter { !SmalltalkRuntime.builtinNames.contains($0.name) }
        while !remaining.isEmpty {
            let previous = remaining.count
            var unresolved: [ImageClass] = []
            for record in remaining {
                guard let parentName = record.superclass else { throw invalid("Superclass is missing.") }
                if let parent = runtime.classes[parentName] {
                    _ = try runtime.subclass(of: parent, name: record.name, fields: record.fields.joined(separator: " "))
                    guard runtime.classes[record.name]?.ownFields == record.fields else { throw invalid("Invalid instance variables.") }
                } else { unresolved.append(record) }
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
                guard sources.count <= 512, let stClass = runtime.classes[record.name],
                      Set(code.keys) == Set(sources.keys) else { throw invalid("Invalid method table.") }
                for (selector, source) in sources {
                    guard let methodCode = code[selector] else { throw invalid("Executable method is missing.") }
                    stClass[side][selector] = try methodCode.validatedMethod(selector: selector, source: source, fields: stClass.fields(for: side))
                }
            }
        }
        try runtime.validateCompilerClasses()
        guard runtime.classes["UIBinding"]?.lookup("reconcileMount:") != nil else {
            throw invalid("The image is missing UIBinding>>reconcileMount:. Start a fresh session.")
        }

        // Allocate first, connect second: this preserves identity and cycles.
        var shells: [Shell] = []
        var placeholderEnvironment: Environment?
        for node in image.nodes {
            switch node {
            case .object(let record):
                guard let stClass = runtime.classes[record.className], stClass.name == "Object" || !SmalltalkRuntime.builtinNames.contains(stClass.name), Set(record.fields.keys) == Set(stClass.fields) else { throw invalid("Invalid object layout.") }
                let object = try runtime.object(stClass)
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
            case .string(let s): return .string(s)
            case .symbol(let s): return .symbol(s)
            case .boolean(let b): return .boolean(b)
            case .nilValue: return .nilValue
            case .transcript: return .transcript
            case .classObject(let name):
                guard let stClass = runtime.classes[name] else { throw invalid("Unknown class reference \(name).") }
                return .classObject(stClass)
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
            case (.object(let record), .value(.object(let object))): object.fields = try record.fields.mapValues(value)
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
                block.context = Context(environment: try environment(record.environment), receiver: receiver, homeClass: homeClass, homeID: 0, isWorkspace: record.isWorkspace, methodSide: side)
            default: throw invalid("The object table is inconsistent.")
            }
        }
        let globals = try image.globals.mapValues(value)
        for name in runtime.classes.keys {
            if name == "Transcript" {
                guard case .transcript? = globals[name] else { throw invalid("Transcript is missing.") }
            } else {
                guard case .classObject(let stClass)? = globals[name], stClass === runtime.classes[name] else { throw invalid("Class binding \(name) is missing.") }
            }
        }
        guard Set(globals.keys).isDisjoint(with: ["nil", "true", "false", "self", "super", "thisContext"]) else { throw invalid("Reserved global variable.") }
        runtime.globals = globals
        guard case .object(let desktop)? = globals["Desktop"], runtime.isUIClass(desktop.stClass, named: "DesktopManager"),
              case .object(let model)? = desktop.fields["model"], runtime.isUIClass(model.stClass, named: "DesktopModel") else {
            throw invalid("The image has no valid window manager.")
        }
        try runtime.validateMVCState()
        runtime.catalogDirty = false
        runtime.recordingChanges = true
    }

    private static func validateNames(_ names: [String]) throws {
        guard CodeValidator.validNames(names) else { throw invalid("Invalid variable names.") }
    }

    private static func invalid(_ message: String) -> SmalltalkError { SmalltalkError(message) }
}
