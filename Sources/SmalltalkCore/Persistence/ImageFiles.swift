import Foundation

/// Executable bytecode belongs to the image. Original spelling, comments and method
/// history belong to the immutable .sources archive or the append-only .changes.
struct MethodCode: Codable, Sendable {
    let selector: String
    let parameters: [String]
    let body: BytecodeBody
    let sourceHash: String
    init(_ method: Method) {
        selector = method.selector; parameters = method.parameters; body = method.body
        sourceHash = SystemLibrary.digest(Data(method.source.utf8))
    }
    func validatedMethod(selector expected: String, source: String, fields: [String]) throws -> Method {
        guard expected == selector, source.utf8.count <= 262_144, SystemLibrary.digest(Data(source.utf8)) == sourceHash else {
            throw SmalltalkError("The method source and executable code do not match.")
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
        var methodSide: MethodSide?
        var side: MethodSide { methodSide ?? .instance }
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
        guard url.isFileURL else { throw SmalltalkError("An image must be saved to a local file.") }
        // Validate and size-check before modifying any companion file.
        guard workspace.utf8.count + transcript.utf8.count <= ImageCodec.maxBytes else { throw SmalltalkError("Image is too large.") }
        let library = try SystemLibrary.shared.get()
        let journal = runtime.journal
        let sourcesName = "Smalltalk80-\(library.identifier.prefix(12)).sources"
        let changesURL = url.deletingPathExtension().appendingPathExtension("changes")
        let sourcesURL = url.deletingLastPathComponent().appendingPathComponent(sourcesName)
        try validatePaths(image: url, changes: changesURL, sources: sourcesURL, activeJournal: journal.url)
        let usesActiveJournal = journal.url.map { aliases($0, changesURL) } ?? false
        if usesActiveJournal { try journal.withValidatedFile {} }
        // Save As branches before backfilling sources from a portable image.
        // Those records belong to the destination, even if its write fails.
        let candidate = usesActiveJournal ? journal : SourceJournal(records: journal.records)
        var memory = try ImageCodec.capture(runtime, workspace: workspace, transcript: transcript, includesCode: false)
        // A portable image may have been loaded without a changes journal.
        // Capture its class definitions before attaching the method sources.
        let definitions = Dictionary(uniqueKeysWithValues: library.definitions.map { ($0.name, $0) })
        func depth(_ cls: STClass) -> Int { var n = 0; var c = cls.superclass; while let parent = c { n += 1; c = parent.superclass }; return n }
        for cls in runtime.classes.values.sorted(by: { depth($0) == depth($1) ? $0.name < $1.name : depth($0) < depth($1) }) where !SmalltalkRuntime.builtinNames.contains(cls.name) {
            let base = definitions[cls.name]
            if base?.superclass == cls.superclass?.name && base?.fields == cls.ownFields { continue }
            if !candidate.records.contains(where: { $0.kind == .classDefinition && $0.className == cls.name && $0.superclass == cls.superclass?.name && $0.fields == cls.ownFields }) {
                try candidate.append(kind: .classDefinition, className: cls.name, superclass: cls.superclass?.name, fields: cls.ownFields, source: "\(cls.superclass!.name) subclass: #\(cls.name) instanceVariableNames: '\(cls.ownFields.joined(separator: " "))'")
            }
        }
        var methods: [ImageFileArchive.CodeRecord] = []
        for cls in runtime.classes.values.sorted(by: { $0.name < $1.name }) {
            for side in MethodSide.allCases {
                for method in cls[side].values.sorted(by: { $0.selector < $1.selector }) {
                    var changeID: String?
                    if library.sources[side][cls.name]?[method.selector] != method.source {
                        if let existing = candidate.records.last(where: { $0.kind == .method && $0.className == cls.name && $0.side == side && $0.selector == method.selector && $0.source == method.source }) { changeID = existing.id }
                        else { changeID = try candidate.append(kind: .method, className: cls.name, selector: method.selector, side: side, source: method.source).id }
                    }
                    methods.append(.init(className: cls.name, code: MethodCode(method), changeID: changeID, methodSide: side == .classSide ? side : nil))
                }
            }
        }
        for index in memory.classes.indices {
            memory.classes[index].methods = [:]
            memory.classes[index].classMethods = nil
        }
        let archive = ImageFileArchive(memory: memory, methods: methods, sourcesFile: sourcesName, sourcesID: library.identifier, changesFile: changesURL.lastPathComponent, changesID: candidate.id, checkpoint: candidate.sequence)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(archive)
        guard bytes.count <= ImageCodec.maxBytes else { throw SmalltalkError("Image exceeds the 32 MiB limit.") }
        if FileManager.default.fileExists(atPath: sourcesURL.path) {
            guard try SourceJournal.readBounded(sourcesURL, maximum: 262_144) == library.data else { throw SmalltalkError("Sources archive \(sourcesName) contains different data.") }
        } else { try SourceJournal.createFile(library.data, at: sourcesURL) }
        let createdChangesFile = candidate !== journal
        if createdChangesFile { try candidate.attach(to: changesURL) }
        // The log is durable first; a failed snapshot leaves the previous image
        // and its checkpoint usable. Extra log records remain recoverable.
        do {
            try candidate.withValidatedFile {
                try validatePaths(image: url, changes: changesURL, sources: sourcesURL, activeJournal: journal.url)
                try bytes.write(to: url, options: .atomic)
            }
        } catch {
            // A first save or Save As owns this newly created branch only after
            // the image commits. Remove an unchanged branch on failure so a
            // retry can use the same name, without disturbing the active log or
            // any companion that another writer has since changed.
            if createdChangesFile,
               let expected = try? candidate.data(),
               let actual = try? SourceJournal.readBounded(changesURL, maximum: SourceJournal.maxBytes),
               actual == expected {
                try? FileManager.default.removeItem(at: changesURL)
            }
            throw error
        }
        candidate.savedSequence = candidate.sequence
        runtime.journal = candidate
    }

    private static func validatePaths(image: URL, changes: URL, sources: URL, activeJournal: URL?) throws {
        let paths = [image, changes, sources]
        for first in paths.indices {
            for second in paths.indices where first < second {
                guard !aliases(paths[first], paths[second]) else {
                    throw SmalltalkError("The image, changes log, and sources archive must use different files.")
                }
            }
        }
        if let activeJournal, aliases(image, activeJournal) || aliases(sources, activeJournal) {
            throw SmalltalkError("An image or sources archive cannot replace the active changes log.")
        }
    }

    private static func aliases(_ first: URL, _ second: URL) -> Bool {
        let left = resolvedFileURL(first)
        let right = resolvedFileURL(second)
        let leftPath = left.path.precomposedStringWithCanonicalMapping
        let rightPath = right.path.precomposedStringWithCanonicalMapping
        if leftPath == rightPath { return true }
        let caseSensitive = try? left.deletingLastPathComponent().resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames
        if caseSensitive == false, leftPath.compare(rightPath, options: .caseInsensitive) == .orderedSame { return true }
        if let leftAttributes = try? FileManager.default.attributesOfItem(atPath: first.path),
           let rightAttributes = try? FileManager.default.attributesOfItem(atPath: second.path),
           let leftDevice = leftAttributes[.systemNumber] as? NSNumber,
           let rightDevice = rightAttributes[.systemNumber] as? NSNumber,
           let leftInode = leftAttributes[.systemFileNumber] as? NSNumber,
           let rightInode = rightAttributes[.systemFileNumber] as? NSNumber {
            return leftDevice == rightDevice && leftInode == rightInode
        }
        return false
    }

    private static func resolvedFileURL(_ url: URL, linkDepth: Int = 0) -> URL {
        // Foundation leaves a dangling final symlink unresolved. Its target can
        // still be the companion this save is about to create.
        if linkDepth < 32, let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
            let target = destination.hasPrefix("/") ? URL(fileURLWithPath: destination)
                : url.deletingLastPathComponent().appendingPathComponent(destination)
            return resolvedFileURL(target, linkDepth: linkDepth + 1)
        }
        return url.resolvingSymlinksInPath().standardizedFileURL
    }

    static func load(_ url: URL) throws -> (SmalltalkRuntime, LoadedImage) {
        let bytes = try SourceJournal.readBounded(url, maximum: ImageCodec.maxBytes)
        struct Header: Decodable { let format: String; let version: Int }
        let header: Header
        do { header = try JSONDecoder().decode(Header.self, from: bytes) }
        catch { throw SmalltalkError("The file is not a valid Smalltalk/80 image.") }
        guard header.format == "st80-image" else { throw SmalltalkError("Unknown image format.") }
        guard header.version == ImageCodec.version else { throw SmalltalkError("Image version \(header.version) is unsupported. Expected version \(ImageCodec.version).") }
        let archive = try JSONDecoder().decode(ImageFileArchive.self, from: bytes)
        guard archive.methods.count <= 131_072, archive.checkpoint >= 0,
              archive.sourcesFile == URL(fileURLWithPath: archive.sourcesFile).lastPathComponent,
              archive.changesFile == url.deletingPathExtension().appendingPathExtension("changes").lastPathComponent else { throw SmalltalkError("Invalid source references in the image. Keep the image and changes file together.") }
        let directory = url.deletingLastPathComponent()
        let sources = try SourceJournal.readBounded(directory.appendingPathComponent(archive.sourcesFile), maximum: 262_144)
        guard SystemLibrary.digest(sources) == archive.sourcesID else { throw SmalltalkError("The sources archive does not match this image.") }
        let base = try LibrarySources.decode(sources)
        let journal = try SourceJournal.read(directory.appendingPathComponent(archive.changesFile))
        guard journal.id == archive.changesID, journal.sequence >= archive.checkpoint else { throw SmalltalkError("The changes log does not match the saved image.") }
        let changes = Dictionary(uniqueKeysWithValues: journal.records.map { ($0.id, $0) })
        var memory = archive.memory
        guard memory.format == "st80-image", memory.version == ImageCodec.version, memory.executableMethods == nil,
              memory.executableClassMethods == nil else { throw SmalltalkError("The image contains invalid object memory.") }
        var code: [MethodSide: [String: [String: MethodCode]]] = [:]
        let records = Dictionary(memory.classes.enumerated().map { ($0.element.name, $0.offset) }, uniquingKeysWith: { first, _ in first })
        guard records.count == memory.classes.count, memory.classes.allSatisfy({ $0.methods.isEmpty && $0[.classSide].isEmpty }) else { throw SmalltalkError("The image file contains duplicate classes or embedded sources.") }
        for record in archive.methods {
            let side = record.side
            guard let index = records[record.className], code[side]?[record.className]?[record.code.selector] == nil else { throw SmalltalkError("The image contains an invalid or duplicate method reference.") }
            let source: String
            if let changeID = record.changeID {
                guard let change = changes[changeID], change.kind == .method, change.sequence <= archive.checkpoint, change.className == record.className, change.side == side, change.selector == record.code.selector else { throw SmalltalkError("The method source is missing from the changes log.") }
                source = change.source
            } else {
                guard let text = base[side][record.className]?[record.code.selector] else { throw SmalltalkError("The method source is missing from the sources archive.") }
                source = text
            }
            guard SystemLibrary.digest(Data(source.utf8)) == record.code.sourceHash else { throw SmalltalkError("The method source and image do not match.") }
            memory.classes[index][side][record.code.selector] = source
            code[side, default: [:]][record.className, default: [:]][record.code.selector] = record.code
        }
        memory.executableMethods = code[.instance] ?? [:]
        memory.executableClassMethods = code[.classSide]
        let (runtime, contents) = try ImageCodec.restore(memory)
        journal.savedSequence = archive.checkpoint; runtime.journal = journal
        return (runtime, LoadedImage(evaluation: runtime.snapshot(), workspace: contents.workspace, transcript: contents.transcript))
    }
}
