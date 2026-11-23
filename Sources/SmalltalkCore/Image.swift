import Foundation

public struct LoadedImage: Sendable {
    public let evaluation: EvaluationResult
    public let workspace: String
    public let transcript: String
}

// IDs index nodes, never host addresses. Classes use unique names; all other
// reference objects (including lexical scopes) participate in one object table.
struct ImageArchive: Codable {
    var format = "st80-image"
    var version = ImageCodec.version
    var classes: [ImageClass]
    var globals: [String: ImageValue]
    var nodes: [ImageNode]
    var workspace: String
    var transcript: String
    var executableMethods: [String: [String: MethodCode]]?
}

struct ImageClass: Codable {
    var name: String
    var superclass: String?
    var fields: [String]
    var methods: [String: String]
}

enum ImageValue: Codable {
    case integer(Int64), string(String), symbol(String), boolean(Bool), nilValue
    case classObject(String), reference(Int), transcript
}

enum ImageNode: Codable {
    case object(ImageObject), array([ImageValue]), environment(ImageEnvironment), block(ImageBlock)
}

struct ImageObject: Codable {
    var className: String
    var fields: [String: ImageValue]
}

struct ImageEnvironment: Codable {
    var parent: Int?
    var values: [String: ImageValue]
}

struct ImageBlock: Codable {
    var parameters: [String]
    var body: Body
    var environment: Int
    var receiver: ImageValue
    var homeClass: String?
    var isWorkspace: Bool
}

extension SmalltalkSession {
    public func imageData(workspace: String = "", transcript: String = "") async throws -> Data {
        try await worker.submitThrowing { try ImageCodec.encode($0, workspace: workspace, transcript: transcript) }
    }

    public func loadImage(_ data: Data) async throws -> LoadedImage {
        try await worker.submitThrowing { runtime in
            let (replacement, contents) = try ImageCodec.decode(data)
            runtime = replacement
            return contents
        }
    }

    public func saveImage(to url: URL, workspace: String, transcript: String) async throws {
        try await worker.submitThrowing { runtime in
            try ImageFiles.save(runtime, to: url, workspace: workspace, transcript: transcript)
        }
    }

    public func loadImage(from url: URL) async throws -> LoadedImage {
        try await worker.submitThrowing { runtime in
            let (replacement, contents) = try ImageFiles.load(url)
            runtime = replacement
            return contents
        }
    }
}

enum ImageCodec {
    static let version = 4
    static let maxBytes = 32 * 1_024 * 1_024
    static let maxNodes = 40_000

    private enum Pending {
        case object(STObject), array(STArray), environment(Environment), block(STBlock)
    }

    static func encode(_ runtime: SmalltalkRuntime, workspace: String, transcript: String) throws -> Data {
        let archive = try capture(runtime, workspace: workspace, transcript: transcript, includesCode: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(archive)
        guard data.count <= maxBytes else { throw SmalltalkError("Image ist zu groß (maximal 32 MiB).") }
        return data
    }

    static func capture(_ runtime: SmalltalkRuntime, workspace: String, transcript: String, includesCode: Bool) throws -> ImageArchive {
        guard runtime.activeHomes.isEmpty else { throw SmalltalkError("Images können nur zwischen Ausführungen gespeichert werden.") }
        if let error = runtime.projectWindows().error {
            throw SmalltalkError("Image kann nicht gespeichert werden: \(error)")
        }
        var ids: [ObjectIdentifier: Int] = [:]
        var pending: [Pending] = []

        func register(_ object: AnyObject, _ node: Pending) throws -> Int {
            let identity = ObjectIdentifier(object)
            if let id = ids[identity] { return id }
            guard pending.count < maxNodes else { throw SmalltalkError("Zu viele erreichbare Objekte für ein Image (maximal 40.000).") }
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
                nodes.append(.block(ImageBlock(parameters: block.parameters, body: block.body, environment: environment, receiver: try value(block.context.receiver), homeClass: block.context.homeClass?.name, isWorkspace: block.context.isWorkspace)))
            }
            index += 1
        }
        try runtime.validateMVCState(in: pending.compactMap { node in
            if case .object(let object) = node { return object }
            return nil
        })
        let classes = runtime.classes.values.sorted { $0.name < $1.name }.map {
            ImageClass(name: $0.name, superclass: $0.superclass?.name, fields: $0.ownFields, methods: $0.methods.mapValues(\.source))
        }
        let code = includesCode ? runtime.classes.mapValues { $0.methods.mapValues(MethodCode.init) }.filter { !$0.value.isEmpty } : nil
        return ImageArchive(classes: classes, globals: globals, nodes: nodes, workspace: workspace, transcript: transcript, executableMethods: code)
    }

    static func decode(_ data: Data) throws -> (SmalltalkRuntime, LoadedImage) {
        guard data.count <= maxBytes else { throw SmalltalkError("Image ist zu groß (maximal 32 MiB).") }
        struct Header: Decodable { let format: String; let version: Int }
        let decoder = JSONDecoder()
        let header: Header
        do { header = try decoder.decode(Header.self, from: data) }
        catch { throw SmalltalkError("Die Datei ist kein gültiges Smalltalk/80-Image.") }
        guard header.format == "st80-image" else { throw SmalltalkError("Unbekanntes Image-Format. Erwartet wird ein Smalltalk/80-Image.") }
        guard header.version == ImageCodec.version else { throw SmalltalkError("Image-Version \(header.version) wird nicht unterstützt (erwartet: \(ImageCodec.version)).") }
        let archive: ImageArchive
        do { archive = try decoder.decode(ImageArchive.self, from: data) }
        catch { throw SmalltalkError("Das Image ist beschädigt oder unvollständig: \(error.localizedDescription)") }
        do { return try restore(archive) }
        catch { throw SmalltalkError("Das Image konnte nicht geladen werden: \(error.localizedDescription)") }
    }

    private enum Shell {
        case value(Value), environment(Environment)
    }

    static func restore(_ image: ImageArchive) throws -> (SmalltalkRuntime, LoadedImage) {
        guard image.format == "st80-image", image.version == ImageCodec.version, let executableMethods = image.executableMethods else {
            throw invalid("Der ausführbare Methodenspeicher fehlt oder ist inkompatibel.")
        }
        guard image.classes.count <= 128, image.globals.count <= 1_152, image.nodes.count <= maxNodes else { throw invalid("Größenlimits überschritten.") }
        // No bootstrap, user code, initialize messages or block execution on load.
        let runtime = SmalltalkRuntime(bootstrap: false)
        var records: [String: ImageClass] = [:]
        for record in image.classes {
            guard records.updateValue(record, forKey: record.name) == nil else { throw invalid("Doppelte Klasse \(record.name).") }
        }
        for builtin in runtime.classes.values {
            guard let record = records[builtin.name], record.superclass == builtin.superclass?.name, record.fields == builtin.ownFields else {
                throw invalid("Basisklasse \(builtin.name) fehlt oder hat ein ungültiges Layout.")
            }
        }
        var remaining = image.classes.filter { !SmalltalkRuntime.builtinNames.contains($0.name) }
        while !remaining.isEmpty {
            let previous = remaining.count
            var unresolved: [ImageClass] = []
            for record in remaining {
                guard let parentName = record.superclass else { throw invalid("Oberklasse fehlt.") }
                if let parent = runtime.classes[parentName] {
                    _ = try runtime.subclass(of: parent, name: record.name, fields: record.fields.joined(separator: " "))
                    guard runtime.classes[record.name]?.ownFields == record.fields else { throw invalid("Ungültige Instanzvariablen.") }
                } else { unresolved.append(record) }
            }
            remaining = unresolved
            guard remaining.count < previous else { throw invalid("Klassenhierarchie enthält einen Zyklus oder eine unbekannte Oberklasse.") }
        }
        guard Set(executableMethods.keys) == Set(image.classes.filter { !$0.methods.isEmpty }.map(\.name)) else {
            throw invalid("Die ausführbaren Methoden passen nicht zur Klassentabelle.")
        }
        for record in image.classes {
            let code = executableMethods[record.name] ?? [:]
            guard record.methods.count <= 512, let stClass = runtime.classes[record.name],
                  Set(code.keys) == Set(record.methods.keys) else { throw invalid("Ungültige Methodentabelle.") }
            for (selector, source) in record.methods {
                guard let executable = code[selector] else { throw invalid("Ausführbare Methode fehlt.") }
                stClass.methods[selector] = try executable.validatedMethod(selector: selector, source: source, fields: stClass.fields)
            }
        }
        try runtime.validateCompilerClasses()

        // Allocate first, connect second: this preserves identity and cycles.
        var shells: [Shell] = []
        for node in image.nodes {
            switch node {
            case .object(let record):
                guard let stClass = runtime.classes[record.className], stClass.name == "Object" || !SmalltalkRuntime.builtinNames.contains(stClass.name), Set(record.fields.keys) == Set(stClass.fields) else { throw invalid("Ungültiges Objektlayout.") }
                try runtime.checkAllocation()
                let object = STObject(stClass)
                runtime.objects.append(object)
                shells.append(.value(.object(object)))
            case .array(let values):
                shells.append(.value(try runtime.array(Array(repeating: .nilValue, count: values.count))))
            case .environment:
                shells.append(.environment(try runtime.environment()))
            case .block(let record):
                try validateNames(record.parameters)
                guard Set(record.parameters).isDisjoint(with: record.body.temporaries) else { throw invalid("Doppelte Blockvariable.") }
                try CodeValidator.check(record.body)
                let context = Context(environment: Environment(), receiver: .nilValue, homeClass: nil, homeID: 0, isWorkspace: false)
                shells.append(.value(.block(STBlock(parameters: record.parameters, body: record.body, context: context))))
            }
        }

        func shell(_ id: Int) throws -> Shell {
            guard shells.indices.contains(id) else { throw invalid("Ungültige Objektreferenz \(id).") }
            return shells[id]
        }
        func environment(_ id: Int) throws -> Environment {
            guard case .environment(let environment) = try shell(id) else { throw invalid("Referenz auf einen lexikalischen Kontext erwartet.") }
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
                guard let stClass = runtime.classes[name] else { throw invalid("Unbekannte Klassenreferenz \(name).") }
                return .classObject(stClass)
            case .reference(let id):
                guard case .value(let value) = try shell(id) else { throw invalid("Lexikalischer Kontext ist kein Sprachwert.") }
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
                guard path.insert(id).inserted, image.nodes.indices.contains(id), case .environment(let record) = image.nodes[id] else { throw invalid("Ungültige oder zyklische Kontextverkettung.") }
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
                    guard let stClass = runtime.classes[name] else { throw invalid("Unbekannte Heimklasse.") }
                    return stClass
                }
                block.context = Context(environment: try environment(record.environment), receiver: try value(record.receiver), homeClass: homeClass, homeID: 0, isWorkspace: record.isWorkspace)
            default: throw invalid("Objekttabelle ist inkonsistent.")
            }
        }
        let globals = try image.globals.mapValues(value)
        for name in runtime.classes.keys {
            if name == "Transcript" {
                guard case .transcript? = globals[name] else { throw invalid("Transcript fehlt.") }
            } else {
                guard case .classObject(let stClass)? = globals[name], stClass === runtime.classes[name] else { throw invalid("Klassenbindung \(name) fehlt.") }
            }
        }
        guard Set(globals.keys).isDisjoint(with: ["nil", "true", "false", "self", "super", "thisContext"]) else { throw invalid("Reservierte globale Variable.") }
        runtime.globals = globals
        guard case .object(let desktop)? = globals["Desktop"], runtime.isUIClass(desktop.stClass, named: "DesktopManager"),
              case .object(let model)? = desktop.fields["model"], runtime.isUIClass(model.stClass, named: "DesktopModel") else {
            throw invalid("Das Image enthält keine gültige Fensterverwaltung.")
        }
        try runtime.validateMVCState()
        if let error = runtime.projectWindows().error {
            throw SmalltalkError(error)
        }
        runtime.catalogDirty = false
        runtime.recordingChanges = true
        let contents = LoadedImage(evaluation: runtime.snapshot(), workspace: image.workspace, transcript: image.transcript)
        return (runtime, contents)
    }

    private static func validateNames(_ names: [String]) throws {
        guard CodeValidator.validNames(names) else { throw invalid("Ungültige Variablennamen.") }
    }

    private static func invalid(_ message: String) -> SmalltalkError { SmalltalkError(message) }
}
