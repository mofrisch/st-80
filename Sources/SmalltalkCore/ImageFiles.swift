import Foundation

/// Executable ASTs belong to the image. Original spelling, comments and method
/// history belong to the immutable .sources archive or the append-only .changes.
struct MethodCode: Codable, Sendable {
    let selector: String
    let parameters: [String]
    let body: Body
    let sourceHash: String
    init(_ method: Method) {
        selector = method.selector; parameters = method.parameters; body = method.body
        sourceHash = SystemLibrary.digest(Data(method.source.utf8))
    }
    func validatedMethod(selector expected: String, source: String, fields: [String]) throws -> Method {
        guard expected == selector, source.utf8.count <= 262_144, SystemLibrary.digest(Data(source.utf8)) == sourceHash else {
            throw SmalltalkError("Methodenquelle und ausführbarer Code passen nicht zusammen.")
        }
        let method = Method(selector: selector, parameters: parameters, body: body, source: source)
        try CodeValidator.check(method, fields: fields)
        return method
    }
}

struct ImageFileArchive: Codable {
    struct CodeRecord: Codable {
        let className: String
        let code: MethodCode
        /// nil denotes the matching class/selector in the base sources archive.
        let changeID: String?
    }
    var format = "st80-image"
    var version = ImageCodec.version
    let memory: ImageArchive
    let methods: [CodeRecord]
    let sourcesFile: String
    let sourcesID: String
    let changesFile: String
    let changesID: String
    let checkpoint: Int64
}

enum ImageFiles {
    static func save(_ runtime: SmalltalkRuntime, to url: URL, workspace: String, transcript: String) throws {
        guard url.isFileURL else { throw SmalltalkError("Ein Image muss lokal gespeichert werden.") }
        // Validate and size-check before modifying any companion file.
        guard workspace.utf8.count + transcript.utf8.count <= ImageCodec.maxBytes else { throw SmalltalkError("Image ist zu groß.") }
        var memory = try ImageCodec.capture(runtime, workspace: workspace, transcript: transcript, includesCode: false)
        let library = try SystemLibrary.shared.get()
        let journal = runtime.journal
        // A portable image may have been loaded without a changes journal.
        // Capture its class definitions before attaching the method sources.
        let definitions = Dictionary(uniqueKeysWithValues: library.definitions.map { ($0.name, $0) })
        func depth(_ cls: STClass) -> Int { var n = 0; var c = cls.superclass; while let parent = c { n += 1; c = parent.superclass }; return n }
        for cls in runtime.classes.values.sorted(by: { depth($0) == depth($1) ? $0.name < $1.name : depth($0) < depth($1) }) where !SmalltalkRuntime.builtinNames.contains(cls.name) {
            let base = definitions[cls.name]
            if base?.superclass == cls.superclass?.name && base?.fields == cls.ownFields { continue }
            if !journal.records.contains(where: { $0.kind == .classDefinition && $0.className == cls.name && $0.superclass == cls.superclass?.name && $0.fields == cls.ownFields }) {
                try journal.append(kind: .classDefinition, className: cls.name, superclass: cls.superclass?.name, fields: cls.ownFields, source: "\(cls.superclass!.name) subclass: #\(cls.name) instanceVariableNames: '\(cls.ownFields.joined(separator: " "))'")
            }
        }
        var methods: [ImageFileArchive.CodeRecord] = []
        for cls in runtime.classes.values.sorted(by: { $0.name < $1.name }) {
            for method in cls.methods.values.sorted(by: { $0.selector < $1.selector }) {
                var changeID: String?
                if library.methods[cls.name]?[method.selector] != method.source {
                    if let existing = journal.records.last(where: { $0.kind == .method && $0.className == cls.name && $0.selector == method.selector && $0.source == method.source }) { changeID = existing.id }
                    else { changeID = try journal.append(kind: .method, className: cls.name, selector: method.selector, source: method.source).id }
                }
                methods.append(.init(className: cls.name, code: MethodCode(method), changeID: changeID))
            }
        }
        for index in memory.classes.indices { memory.classes[index].methods = [:] }
        let sourcesName = "Smalltalk80-\(library.identifier.prefix(12)).sources"
        let changesURL = url.deletingPathExtension().appendingPathExtension("changes")
        let candidate: SourceJournal
        if journal.url?.standardizedFileURL == changesURL.standardizedFileURL { candidate = journal }
        else { candidate = SourceJournal(records: journal.records) }
        let archive = ImageFileArchive(memory: memory, methods: methods, sourcesFile: sourcesName, sourcesID: library.identifier, changesFile: changesURL.lastPathComponent, changesID: candidate.id, checkpoint: candidate.sequence)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(archive)
        guard bytes.count <= ImageCodec.maxBytes else { throw SmalltalkError("Image ist zu groß (maximal 32 MiB).") }
        let sourcesURL = url.deletingLastPathComponent().appendingPathComponent(sourcesName)
        if FileManager.default.fileExists(atPath: sourcesURL.path) {
            guard try SourceJournal.readBounded(sourcesURL, maximum: 262_144) == library.data else { throw SmalltalkError("Das Quellenarchiv \(sourcesName) enthält andere Daten.") }
        } else { try SourceJournal.createFile(library.data, at: sourcesURL) }
        if candidate !== journal { try candidate.attach(to: changesURL) }
        else if candidate.url == nil { try candidate.attach(to: changesURL) }
        // The log is durable first; a failed snapshot leaves the previous image
        // and its checkpoint usable. Extra log records remain recoverable.
        try bytes.write(to: url, options: .atomic)
        candidate.savedSequence = candidate.sequence
        runtime.journal = candidate
    }

    static func load(_ url: URL) throws -> (SmalltalkRuntime, LoadedImage) {
        let bytes = try SourceJournal.readBounded(url, maximum: ImageCodec.maxBytes)
        struct Header: Decodable { let format: String; let version: Int }
        let header: Header
        do { header = try JSONDecoder().decode(Header.self, from: bytes) }
        catch { throw SmalltalkError("Die Datei ist kein gültiges Smalltalk/80-Image.") }
        guard header.format == "st80-image" else { throw SmalltalkError("Unbekanntes Image-Format.") }
        guard header.version == ImageCodec.version else { throw SmalltalkError("Image-Version \(header.version) wird nicht unterstützt (erwartet: \(ImageCodec.version)).") }
        let archive = try JSONDecoder().decode(ImageFileArchive.self, from: bytes)
        guard archive.methods.count <= 65_536, archive.checkpoint >= 0,
              archive.sourcesFile == URL(fileURLWithPath: archive.sourcesFile).lastPathComponent,
              archive.changesFile == url.deletingPathExtension().appendingPathExtension("changes").lastPathComponent else { throw SmalltalkError("Ungültige Quellenverweise im Image; Image und Changes müssen zusammenbleiben.") }
        let directory = url.deletingLastPathComponent()
        let sources = try SourceJournal.readBounded(directory.appendingPathComponent(archive.sourcesFile), maximum: 262_144)
        guard SystemLibrary.digest(sources) == archive.sourcesID else { throw SmalltalkError("Das Quellenarchiv passt nicht zu diesem Image.") }
        let baseMethods = try LibrarySources.decode(sources).methods
        let journal = try SourceJournal.read(directory.appendingPathComponent(archive.changesFile))
        guard journal.id == archive.changesID, journal.sequence >= archive.checkpoint else { throw SmalltalkError("Das Changes-Protokoll passt nicht zum gespeicherten Image-Stand.") }
        let changes = Dictionary(uniqueKeysWithValues: journal.records.map { ($0.id, $0) })
        var memory = archive.memory
        guard memory.format == "st80-image", memory.version == ImageCodec.version, memory.executableMethods == nil else { throw SmalltalkError("Ungültiger Objektspeicher im Image.") }
        var code: [String: [String: MethodCode]] = [:]
        let records = Dictionary(memory.classes.enumerated().map { ($0.element.name, $0.offset) }, uniquingKeysWith: { first, _ in first })
        guard records.count == memory.classes.count, memory.classes.allSatisfy({ $0.methods.isEmpty }) else { throw SmalltalkError("Doppelte Klassen oder eingebettete Quellen im Datei-Image.") }
        for record in archive.methods {
            guard let index = records[record.className], code[record.className]?[record.code.selector] == nil else { throw SmalltalkError("Ungültiger oder doppelter Methodenverweis im Image.") }
            let source: String
            if let changeID = record.changeID {
                guard let change = changes[changeID], change.kind == .method, change.sequence <= archive.checkpoint, change.className == record.className, change.selector == record.code.selector else { throw SmalltalkError("Methodenquelle fehlt im Changes-Protokoll.") }
                source = change.source
            } else {
                guard let text = baseMethods[record.className]?[record.code.selector] else { throw SmalltalkError("Methodenquelle fehlt im Quellenarchiv.") }
                source = text
            }
            guard SystemLibrary.digest(Data(source.utf8)) == record.code.sourceHash else { throw SmalltalkError("Methodenquelle und Image passen nicht zusammen.") }
            memory.classes[index].methods[record.code.selector] = source
            code[record.className, default: [:]][record.code.selector] = record.code
        }
        memory.executableMethods = code
        let (runtime, contents) = try ImageCodec.restore(memory)
        journal.savedSequence = archive.checkpoint; runtime.journal = journal
        return (runtime, LoadedImage(evaluation: runtime.snapshot(), workspace: contents.workspace, transcript: contents.transcript))
    }
}
