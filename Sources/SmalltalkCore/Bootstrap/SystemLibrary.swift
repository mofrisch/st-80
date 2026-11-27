import CryptoKit
import Foundation

private final class LibraryBundleToken {}

struct LibrarySources: Codable, Sendable {
    static let maxBytes = 1_048_576

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
        data = try SourceJournal.readBounded(directory.appendingPathComponent("Smalltalk80.sources"), maximum: LibrarySources.maxBytes)
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

    func installANSIClasses(_ names: Set<String>, in runtime: SmalltalkRuntime) throws -> Set<String> {
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
        let nonCollectionNames = SmalltalkRuntime.shippedDateTimeNames.union(SmalltalkRuntime.shippedNotificationNames)
        if !names.isSubset(of: nonCollectionNames) {
            try backfillMethods(on: runtime.classes["Collection"]!)
        }
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

    /// Apply ANSI fixes to previous shipped implementations, retaining methods
    /// whose owners changed their source in the image.
    func upgradeANSIBehavior(in runtime: SmalltalkRuntime) throws {
        let previous: [(String, MethodSide, String, String)] = [
            ("Number", .instance, "roundTo:", "cff8084078c35d4e8ad7f05394caaee5cb3f0f68b7fbf1df399101254b6756fc"),
            ("Number", .instance, "truncateTo:", "fb48538a48c844cb22069037bb6c932d53b12bf6906beb8299230b29d9168348"),
            ("Float", .instance, "log:", "157de5c473c332c4353a5c8583f594c12f041c32b1ed41d69726bdad9a28bd7d"),
            ("Float", .instance, "floorLog:", "0239951c85db5e024921a60e0ae2943b21d5bd91142ffd6aa8c4daaf1d036051"),
            ("SequenceableCollection", .instance, "indexOfSubCollection:startingAt:ifAbsent:", "93b7313d2973e689bc724bc5bed5fe23509439b89f42bb1132ea1ca8aca7030b"),
            ("SequenceableCollection", .instance, "copyReplaceAll:with:", "74d8c3839c765f33276e436f23d079187f2fca6b95ef6bf573c97203308177c6"),
            ("WriteStream", .instance, "nextPutAll:", "6e79e850dc0f072a275e35899f18f591bd49848d0183d35935922ccc1b8d5e23"),
            ("ReadWriteStream", .instance, "nextPutAll:", "6e79e850dc0f072a275e35899f18f591bd49848d0183d35935922ccc1b8d5e23"),
            ("WriteFileStream", .instance, "nextPutAll:", "e284b35e8e85205e0742622a4770d0f247686aec32f5bfa147096a14f6294276"),
            ("ApplicationMenu", .classSide, "fileMenu", "a2f6fc0bf846041b0151c6cb2293f6fe3749b38bc2377b69418af861cd087a2f"),
        ]
        func install(_ selector: String, on owner: STClass, side: MethodSide) throws {
            guard let code = seed[side][owner.name]?[selector], let source = sources[side][owner.name]?[selector] else {
                throw SmalltalkError("Missing bundled ANSI method \(owner.name)»\(selector).")
            }
            owner[side][selector] = try code.validatedMethod(selector: selector, source: source)
        }
        for (name, side, selector, hash) in previous {
            guard let owner = runtime.classes[name], let old = owner[side][selector],
                  Self.digest(Data(old.source.utf8)) == hash else { continue }
            if name == "Number", owner.methods["_coerceRoundingFactor:"] == nil {
                guard owner.methods.count < SmalltalkRuntime.methodsPerSideLimit else { continue }
                try install("_coerceRoundingFactor:", on: owner, side: .instance)
            }
            try install(selector, on: owner, side: side)
        }
    }

    /// Update shipped browser code only. Smalltalk merges the defaults the
    /// next time that the browser's catalog is used.
    func upgradeBrowserOrganization(in runtime: SmalltalkRuntime, classesAdded: Bool) throws -> Bool {
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
                "653ab4efb336295ac621f4148d18c8514eee3a4c1bbbaa4494e4d8b653bed335",
                "71d48031db4dc35c95db45ac06fb70d52359900c1fd9cbb3043998fc6c2c4180",
                "c78aa3118354a6a154dd054e2f9eac77d18efd675f2542e748cfa762fc695f64",
                "8b97cd52d95fcb53aaff65d8bfe1846c2daca64e5b9385ff08d5cdb7912f591e",
                "fd4eca47479b562f9bd4515d5cc5f52ee9b365181cf1e6da3d27427ce67a1f56",
            ]),
            (.instance, "shippedClassSideProtocols", [
                "7b2f2950f5dc051c01fdcd0afcdde26c8505606a3c1f370ad2c6910c5eff398c",
                "a57049aae45eec58838977d232ca38087f17d6cadfc40092e4a23df2e68a9a13",
                "b47e4912fcc451571d5cef706f0cc72fdf9e8d9a4642a4e2e6813c2c680df201",
                "b7974c43ae3dd01bbbbcbc727dab84713023b8ee1a57e63894caa2243cf53765",
                "1fa6f5c515c4deea0d6f1347dbd94a2b6067ab009919c6256dde5695e2f50b5b",
            ]),
            (.classSide, "shippedClassCategories", [
                "94b28fa4e197128a9942bda803c88b225ff4b73c86eb419a706c4b06c8dc4b1e",
                "45dba024b3d32946974fd979d5c048df2d6902dffc037ce038e6a30303b1d4ff",
                "8c81a5a21932001fa86c5ecb219bb36046bc083a3f9d0c58a1e468f957b630e1",
                "d6f01cc25cefa6821ba8f6df8155881ce9448539865f2469d944a22fea670818",
                "1fb93f9ae4e52958193acf210246958977090fde93fb71a743809d4a03c13362",
                "e0bc5333d08db3e3d27d006ea23e374351a5e468cc5be4023e1ce012b8bb3421",
                "386c630d15d0ef4cfee1ef93fc238c610b3cca4774c91a15d9c80e5f7efdc3ef",
                "e1980acc550da5ca0237e0eac5c268fd24cb6f1226190fba9946133a2aef6f2c",
                "8f14c680d8411bf47e591c778eb7b66fad36e7493fc9bee2484710a6998bf2dc",
                "b2d934eaaf2b7476f68f04841e4b81db411ed9f5bbc5e24de5fa6f69f91fab7a",
                "3075b28152eee65ef6d3c9ded49fa3e892aa0dce8c08cb00ea79086c85bef9fe",
                "3203391bd3d543d8c6634184658cf5c3157a0c578436a9e6ed97ba76b6219a9b",
            ]),
        ]
        var refresh = classesAdded
        for (side, selector, hashes) in defaults {
            if let method = target[side][selector], hashes.contains(Self.digest(Data(method.source.utf8))) {
                try install(selector, side: side, on: target)
                refresh = true
            }
        }
        guard refresh else { return false }
        for selector in ["shippedClassSideProtocols", "fileShippedProtocolsOf:side:into:", "classNames:inCategory:"] {
            if target.methods[selector] == nil { try install(selector, side: .instance, on: target) }
        }
        let catalogMethods = [
            ("BrowserOrganization", "categoryOf:", "40851d09b4019a31318a7b955d4043754931af7da7ce25e1af7e206da10f549a"),
            ("BrowserOrganization", "classCategories", "d5674dfea3a9fc64f919d5fb85669a89e99bed540b2e67c61f0d186cc1fd4d14"),
            ("BrowserOrganization", "refreshShippedProtocols", "95225c9639971dd27259bedc112f082faf1ecddf13a64a134e667568e8521aa4"),
            ("BrowserGrouping", "defineDefaults:", "0d430fcdeca2dec92ec0f69cc725f873bd75414e7fa84aba1e9cf9c3ad29eda0"),
            ("BrowserWindow", "refreshClasses", "b69bb6deef882fe035dc2b12268babe197aedf892af83dc89f84fee68765c50b"),
        ]
        for (className, selector, hash) in catalogMethods {
            guard let owner = runtime.classes[className] else { continue }
            if let method = owner.methods[selector], Self.digest(Data(method.source.utf8)) != hash { continue }
            try install(selector, side: .instance, on: owner)
        }
        try install("protocolsOf:side:", side: .instance, on: target)
        return true

        func install(_ selector: String, side: MethodSide, on target: STClass) throws {
            let name = target.name
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
