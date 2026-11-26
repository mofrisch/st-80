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
            try backfillMethods(on: target)
        }
    }

    func installANSICollections(_ names: Set<String>, in runtime: SmalltalkRuntime) throws -> Set<String> {
        var added: Set<String> = []
        for definition in definitions where names.contains(definition.name) {
            guard runtime.classes[definition.name] == nil else { continue }
            guard let superclass = runtime.classes[definition.superclass] else {
                throw SmalltalkError("Missing superclass \(definition.superclass) for \(definition.name).")
            }
            let target = try runtime.subclass(of: superclass, name: definition.name, fields: definition.fields.joined(separator: " "))
            try backfillMethods(on: target)
            added.insert(definition.name)
        }
        try backfillMethods(on: runtime.classes["Collection"]!)
        return added
    }

    private func backfillMethods(on target: STClass) throws {
        for side in MethodSide.allCases {
            let methods = seed[side][target.name] ?? [:]
            for (selector, code) in methods.sorted(by: { $0.key < $1.key }) where target[side][selector] == nil {
                guard target[side].count < SmalltalkRuntime.methodsPerSideLimit else { break }
                guard let source = sources[side][target.name]?[selector] else {
                    throw SmalltalkError("Missing bundled source for \(side.displayName(for: target.name))>>\(selector).")
                }
                target[side][selector] = try code.validatedMethod(selector: selector, source: source)
            }
        }
    }

    /// Update shipped browser code only. Per-image protocol assignments are
    /// merged by Smalltalk the next time that browser's catalog is used.
    func upgradeBrowserProtocols(in runtime: SmalltalkRuntime) throws -> Bool {
        let name = "BrowserOrganization"
        let shippedLookupHashes: Set<String> = [
            "674b0cce59f3f6c8cd8f55cd14d06bb99f37075a1566e1da2b8e00f22de4fc67",
            "4de254a1fef0e16569546ce5d1d69210996fca43e9acae7376744d4a03cc3123",
        ]
        guard let target = runtime.classes[name],
              let previous = target.methods["protocolsOf:side:"],
              shippedLookupHashes.contains(Self.digest(Data(previous.source.utf8))) else {
            return false
        }
        let defaults: [(MethodSide, String, Set<String>)] = [
            (.instance, "shippedProtocols", [
                "97dae8e50970465556c668dc41ef4c1254051edbed61bf9e87f6f1650aaf65d9",
                "809f589b0eb5d68b77d58170a7c5b7877bb1f42aabc1ba2cc5971e610cf50664",
                "3f96d04fe9b1bc6217026ac6fbf14e9862321ebb8a59610d9d6c4fe86b0a17f8",
                "1198c24ac571e6f29f761121d6f07bf4ce67f09c8c262f038bb512a5b13729ac",
                "7ea8d999df67b9777d1c79ae510d3f93677423a2b8407699d2d534c376349576",
                "7fa293e8a83174d786a7453a592a3e45123750cda2b8b8f291375f2779bd18ab",
                "cc354ef0e71fc134f9f19929c4a44403584e9ebcc7dbd9085efa9bcb0716b8c3",
            ]),
            (.instance, "shippedClassSideProtocols", [
                "7b2f2950f5dc051c01fdcd0afcdde26c8505606a3c1f370ad2c6910c5eff398c",
                "a57049aae45eec58838977d232ca38087f17d6cadfc40092e4a23df2e68a9a13",
                "b47e4912fcc451571d5cef706f0cc72fdf9e8d9a4642a4e2e6813c2c680df201",
            ]),
            (.classSide, "shippedClassCategories", [
                "94b28fa4e197128a9942bda803c88b225ff4b73c86eb419a706c4b06c8dc4b1e",
                "45dba024b3d32946974fd979d5c048df2d6902dffc037ce038e6a30303b1d4ff",
                "8c81a5a21932001fa86c5ecb219bb36046bc083a3f9d0c58a1e468f957b630e1",
                "d6f01cc25cefa6821ba8f6df8155881ce9448539865f2469d944a22fea670818",
                "1fb93f9ae4e52958193acf210246958977090fde93fb71a743809d4a03c13362",
                "e0bc5333d08db3e3d27d006ea23e374351a5e468cc5be4023e1ce012b8bb3421",
                "386c630d15d0ef4cfee1ef93fc238c610b3cca4774c91a15d9c80e5f7efdc3ef",
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
