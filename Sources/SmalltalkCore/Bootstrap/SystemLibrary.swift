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
    var classMethods: [String: [String: String]]?

    subscript(side: MethodSide) -> [String: [String: String]] { side == .instance ? methods : classMethods ?? [:] }

    static func decode(_ data: Data) throws -> Self {
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.version == 1 else { throw SmalltalkError("Unsupported sources archive version.") }
        return result
    }
}

struct LibrarySeed: Codable, Sendable {
    static let currentVersion = 2
    var version = Self.currentVersion
    let sourcesID: String
    let methods: [String: [String: MethodCode]]
    var classMethods: [String: [String: MethodCode]]?

    subscript(side: MethodSide) -> [String: [String: MethodCode]] { side == .instance ? methods : classMethods ?? [:] }
}

struct SystemLibrary: Sendable {
    let data: Data
    let identifier: String
    let sources: LibrarySources
    let seed: LibrarySeed
    let initialWorld: String
    var definitions: [LibrarySources.Definition] { sources.definitions }

    static let shared: Result<SystemLibrary, SmalltalkError> = {
        do {
            guard let resources = bundle.resourceURL else { throw SmalltalkError("Framework resources are missing.") }
            let url = resources.appendingPathComponent("Library", isDirectory: true)
            return .success(try SystemLibrary(directory: url))
        } catch {
            return .failure(SmalltalkError("Could not load the Smalltalk boot image: \(error.localizedDescription)"))
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
        let decoder = JSONDecoder()
        struct Header: Decodable { let version: Int }
        let version = try decoder.decode(Header.self, from: executable).version
        guard version == LibrarySeed.currentVersion else { throw SmalltalkError("Unsupported Smalltalk boot image version.") }
        seed = try decoder.decode(LibrarySeed.self, from: executable)
        guard seed.sourcesID == identifier else { throw SmalltalkError("The boot image and sources archive do not match.") }
        initialWorld = try String(contentsOf: directory.appendingPathComponent("InitialWorld.st"), encoding: .utf8)
    }

    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func bundledClass(_ name: String, in runtime: SmalltalkRuntime) throws -> STClass {
        guard let definition = definitions.first(where: { $0.name == name }),
              let parent = runtime.classes[definition.superclass] else {
            throw SmalltalkError("The bundled class \(name) is missing.")
        }
        let target = STClass(name, superclass: parent, fields: definition.fields)
        for side in MethodSide.allCases {
            for (selector, code) in seed[side][name] ?? [:] {
                guard let source = sources[side][name]?[selector] else {
                    throw SmalltalkError("The bundled source for \(name)>>\(selector) is missing.")
                }
                target[side][selector] = try code.validatedMethod(selector: selector, source: source,
                                                                  fields: target.fields(for: side))
            }
        }
        return target
    }

    func install(in runtime: SmalltalkRuntime) throws {
        for definition in definitions {
            guard let parent = runtime.classes[definition.superclass] else { throw SmalltalkError("System superclass \(definition.superclass) is missing.") }
            _ = try runtime.subclass(of: parent, name: definition.name, fields: definition.fields.joined(separator: " "))
        }
        for side in MethodSide.allCases {
            guard Set(seed[side].keys) == Set(sources[side].keys) else { throw SmalltalkError("The boot image contains a different method table.") }
            for (name, code) in seed[side] {
                guard let stClass = runtime.classes[name], let methodSources = sources[side][name], Set(code.keys) == Set(methodSources.keys) else {
                    throw SmalltalkError("Method table for \(side.displayName(for: name)) is incomplete in the boot image.")
                }
                for (selector, executable) in code {
                    guard let source = methodSources[selector] else { throw SmalltalkError("System method \(name)>>\(selector) is missing.") }
                    stClass[side][selector] = try executable.validatedMethod(selector: selector, source: source, fields: stClass.fields(for: side))
                }
            }
        }
        try runtime.validateCompilerClasses()
    }
}

extension SmalltalkRuntime {
    func validateCompilerClasses() throws {
        for name in Self.compilerClassNames {
            guard let stClass = classes[name], stClass.superclass === classes["Object"], !stClass.methods.isEmpty else {
                throw SmalltalkError("Compiler class \(name) is missing or invalid.")
            }
        }
        guard classes["STCompiler"]?.methods["workspace:"] != nil, classes["STCompiler"]?.methods["method:"] != nil else {
            throw SmalltalkError("The Smalltalk compiler's entry methods are missing.")
        }
    }
}
