import CryptoKit
import Foundation

private final class LibraryBundleToken {}

struct LibrarySources: Codable, Sendable {
    struct Definition: Codable, Sendable {
        let name: String
        let superclass: String
        let fields: [String]
        var classFields: [String]? = nil
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
        let target = STClass(name, superclass: parent, fields: definition.fields, classFields: definition.classFields ?? [])
        for side in MethodSide.allCases {
            for (selector, code) in seed[side][name] ?? [:] {
                guard let source = sources[side][name]?[selector] else {
                    throw SmalltalkError("The bundled source for \(name)>>\(selector) is missing.")
                }
                target[side][selector] = try code.validatedMethod(selector: selector, source: source)
            }
        }
        return target
    }

    func install(in runtime: SmalltalkRuntime) throws {
        for definition in definitions {
            guard let parent = runtime.classes[definition.superclass] else { throw SmalltalkError("System superclass \(definition.superclass) is missing.") }
            _ = try runtime.subclass(of: parent, name: definition.name, fields: definition.fields.joined(separator: " "),
                                     classFields: definition.classFields ?? [])
        }
        for side in MethodSide.allCases {
            guard Set(seed[side].keys) == Set(sources[side].keys) else { throw SmalltalkError("The boot image contains a different method table.") }
            for (name, code) in seed[side] {
                guard let stClass = runtime.classes[name], let methodSources = sources[side][name], Set(code.keys) == Set(methodSources.keys) else {
                    throw SmalltalkError("Method table for \(side.displayName(for: name)) is incomplete in the boot image.")
                }
                for (selector, executable) in code {
                    guard let source = methodSources[selector] else { throw SmalltalkError("System method \(name)>>\(selector) is missing.") }
                    stClass[side][selector] = try executable.validatedMethod(selector: selector, source: source)
                }
            }
        }
        try runtime.validateCompilerClasses()
    }

    /// Earlier images retain their own method tables. Backfill the new protocols
    /// while preserving installed versions of existing methods.
    func installANSIProtocols(in runtime: SmalltalkRuntime) throws {
        let libraryClasses = [
            "Object", "Number", "Integer", "Fraction", "Float", "ScaledDecimal", "Exception", "ExceptionSet",
            "MessageNotUnderstood", "ZeroDivide", "SequenceableCollection", "Array", "Interval", "String", "Symbol", "Transcript",
        ]
        for name in libraryClasses {
            guard let target = runtime.classes[name] else { throw SmalltalkError("Missing ANSI class \(name).") }
            for side in MethodSide.allCases {
                let methods = seed[side][name] ?? [:]
                for (selector, code) in methods.sorted(by: { $0.key < $1.key }) where target[side][selector] == nil {
                    guard target[side].count < SmalltalkRuntime.methodsPerSideLimit else { break }
                    guard let source = sources[side][name]?[selector] else {
                        throw SmalltalkError("Missing bundled source for \(side.displayName(for: name))>>\(selector).")
                    }
                    target[side][selector] = try code.validatedMethod(selector: selector, source: source)
                }
            }
        }
    }

    /// Update shipped browser code only. Per-image protocol assignments are
    /// merged by Smalltalk the next time that browser's catalog is used.
    func upgradeBrowserProtocols(in runtime: SmalltalkRuntime) throws -> Bool {
        let name = "BrowserOrganization"
        guard let target = runtime.classes[name],
              let previous = target.methods["protocolsOf:side:"],
              Self.digest(Data(previous.source.utf8)) == "674b0cce59f3f6c8cd8f55cd14d06bb99f37075a1566e1da2b8e00f22de4fc67" else {
            return false
        }
        let defaults: [(MethodSide, String, Set<String>)] = [
            (.instance, "shippedProtocols", [
                "97dae8e50970465556c668dc41ef4c1254051edbed61bf9e87f6f1650aaf65d9",
                "809f589b0eb5d68b77d58170a7c5b7877bb1f42aabc1ba2cc5971e610cf50664",
                "3f96d04fe9b1bc6217026ac6fbf14e9862321ebb8a59610d9d6c4fe86b0a17f8",
                "1198c24ac571e6f29f761121d6f07bf4ce67f09c8c262f038bb512a5b13729ac",
            ]),
            (.classSide, "shippedClassCategories", [
                "94b28fa4e197128a9942bda803c88b225ff4b73c86eb419a706c4b06c8dc4b1e",
                "45dba024b3d32946974fd979d5c048df2d6902dffc037ce038e6a30303b1d4ff",
                "8c81a5a21932001fa86c5ecb219bb36046bc083a3f9d0c58a1e468f957b630e1",
                "d6f01cc25cefa6821ba8f6df8155881ce9448539865f2469d944a22fea670818",
            ]),
        ]
        for (side, selector, hashes) in defaults {
            if let method = target[side][selector], hashes.contains(Self.digest(Data(method.source.utf8))) {
                try install(selector, side: side)
            }
        }
        for selector in ["shippedClassSideProtocols", "refreshShippedProtocols", "fileShippedProtocolsOf:side:into:"] {
            if target.methods[selector] == nil { try install(selector, side: .instance) }
        }
        try install("protocolsOf:side:", side: .instance)
        return true

        func install(_ selector: String, side: MethodSide) throws {
            guard let code = seed[side][name]?[selector], let source = sources[side][name]?[selector] else {
                throw SmalltalkError("Missing bundled browser method \(selector).")
            }
            target[side][selector] = try code.validatedMethod(selector: selector, source: source)
        }
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
