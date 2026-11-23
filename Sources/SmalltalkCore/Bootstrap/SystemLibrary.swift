import CryptoKit
import Foundation

private final class LibraryBundleToken {}

struct LibrarySources: Codable, Sendable {
    struct Definition: Codable, Sendable {
        let name: String
        let superclass: String
        let fields: [String]
    }

    var version = 1
    let definitions: [Definition]
    let methods: [String: [String: String]]

    static func decode(_ data: Data) throws -> Self {
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.version == 1 else { throw SmalltalkError("Unbekannte Version des Sources-Archivs.") }
        return result
    }
}

struct LibrarySeed: Codable, Sendable {
    var version = 1
    let sourcesID: String
    let methods: [String: [String: MethodCode]]
}

struct SystemLibrary: Sendable {
    let data: Data
    let identifier: String
    let sources: LibrarySources
    let seed: LibrarySeed
    let initialWorld: String
    var definitions: [LibrarySources.Definition] { sources.definitions }
    var methods: [String: [String: String]] { sources.methods }

    static let shared: Result<SystemLibrary, SmalltalkError> = {
        do {
            guard let resources = bundle.resourceURL else { throw SmalltalkError("Framework-Ressourcen fehlen.") }
            let url = resources.appendingPathComponent("Library", isDirectory: true)
            return .success(try SystemLibrary(directory: url))
        } catch {
            return .failure(SmalltalkError("Smalltalk-Startimage konnte nicht geladen werden: \(error.localizedDescription)"))
        }
    }()

    private static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return Bundle(for: LibraryBundleToken.self)
        #endif
    }

    init(directory: URL) throws {
        data = try SourceJournal.readBounded(directory.appendingPathComponent("Smalltalk80.sources"), maximum: 262_144)
        identifier = Self.digest(data)
        sources = try LibrarySources.decode(data)
        let executable = try SourceJournal.readBounded(directory.appendingPathComponent("Kernel.seed.json"), maximum: ImageCodec.maxBytes)
        seed = try JSONDecoder().decode(LibrarySeed.self, from: executable)
        guard seed.version == 1, seed.sourcesID == identifier else { throw SmalltalkError("Startimage und Sources-Archiv passen nicht zusammen.") }
        initialWorld = try String(contentsOf: directory.appendingPathComponent("InitialWorld.st"), encoding: .utf8)
    }

    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func install(in runtime: SmalltalkRuntime) throws {
        for definition in definitions {
            guard let parent = runtime.classes[definition.superclass] else { throw SmalltalkError("System-Oberklasse \(definition.superclass) fehlt.") }
            _ = try runtime.subclass(of: parent, name: definition.name, fields: definition.fields.joined(separator: " "))
        }
        guard Set(seed.methods.keys) == Set(methods.keys) else { throw SmalltalkError("Startimage enthält eine abweichende Methodentabelle.") }
        for (name, code) in seed.methods {
            guard let stClass = runtime.classes[name], let sources = methods[name], Set(code.keys) == Set(sources.keys) else {
                throw SmalltalkError("Klasse \(name) ist im Startimage unvollständig.")
            }
            for (selector, executable) in code {
                guard let source = sources[selector] else { throw SmalltalkError("Systemmethode \(name)>>\(selector) fehlt.") }
                stClass.methods[selector] = try executable.validatedMethod(selector: selector, source: source, fields: stClass.fields)
            }
        }
        try runtime.validateCompilerClasses()
    }
}

extension SmalltalkRuntime {
    func validateCompilerClasses() throws {
        for name in Self.compilerClassNames {
            guard let stClass = classes[name], stClass.superclass === classes["Object"], !stClass.methods.isEmpty else {
                throw SmalltalkError("Compilerklasse \(name) fehlt oder ist ungültig.")
            }
        }
        guard classes["STCompiler"]?.methods["workspace:"] != nil, classes["STCompiler"]?.methods["method:"] != nil else {
            throw SmalltalkError("Einstiegsmethoden des Smalltalk-Compilers fehlen.")
        }
    }
}
