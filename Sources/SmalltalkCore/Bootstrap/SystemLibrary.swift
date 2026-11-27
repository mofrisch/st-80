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
        for (name, side, selector, hash) in previous {
            guard let owner = runtime.classes[name], let old = owner[side][selector],
                  Self.digest(Data(old.source.utf8)) == hash else { continue }
            if name == "Number", owner.methods["_coerceRoundingFactor:"] == nil {
                guard owner.methods.count < SmalltalkRuntime.methodsPerSideLimit else { continue }
                try installBundledMethod("_coerceRoundingFactor:", on: owner)
            }
            try installBundledMethod(selector, on: owner, side: side)
        }
    }

    /// Update stock library and compiler methods in already-saved images.
    func upgradeCurrentANSIBehavior(in runtime: SmalltalkRuntime) throws {
        let previous: [(String, MethodSide, String, String)] = [
            ("CollectionStream", .instance, "_sliceFrom:to:", "33a5793e7590a90a2f8ec120cfa8fc770f97c37b124be13af8e8f26188f0c7b7"),
            ("CollectionStream", .instance, "_sliceFrom:to:", "c09dbe48941617162c969c9452383bfee82a27871d74c761827db874247405a5"),
            ("ReadStream", .instance, "nextLine", "3e8c7e8bdfd2d1692d1c2a1f79971d78c662dd78387403c0fa7ebd48c15bbd2e"),
            ("STCompiler", .instance, "validateNames:", "952c549838c500573b424f1fc3ac1725f263502cd9a4f0a4ca33481e5dc8681f"),
            ("STScanner", .instance, "isBinary:", "8f9b611482286a44c54c29eed24f711b6115fc10b9ed36b63c837ec9bd4a5017"),
            ("STSourceScanner", .instance, "token:value:", "8dd1c8d42cecd567393b843510c0d0bdd72a513886917e7d7712701c5087b189"),
            ("Integer", .instance, "sqrt", "fc3b3aead2ade1001067870caae4c1dc452003ebe5ea5f9ce72575297133067a"),
            ("Array", .instance, "replaceFrom:to:with:", "defc5b01df6b6da8c341cc8ec587b625284afe50df265bbb856b55b41f8ca5eb"),
            ("Array", .instance, "replaceFrom:to:withObject:", "766d1f192d67d2efcdd737638d2f32634dd24bfb3f3cc61e1d9d9649479e38a6"),
            ("OrderedCollection", .instance, "replaceFrom:to:with:", "defc5b01df6b6da8c341cc8ec587b625284afe50df265bbb856b55b41f8ca5eb"),
            ("ByteArray", .instance, "replaceFrom:to:with:", "defc5b01df6b6da8c341cc8ec587b625284afe50df265bbb856b55b41f8ca5eb"),
            ("Transcript", .instance, "nextPutAll:", "0eaed9f2c0e56e6f86b9aaabd2bbb0dc325e7a33ba0d9b7751acfc9d4d04fd29"),
            ("TestRunner", .classSide, "testSelectorsFor:", "2093debff5e3ffedfe588bc9688be5b118f3119a3f9eb8baab44ed8ee572fd28"),
            ("Number", .instance, "rem:", "7a356c2f5573e14e1557e2e1e6fd5ec253fbdaccf10e79386d5bbc3ed1942a97"),
            ("Number", .instance, "roundTo:", "f245fe0e103a14c660d6e21c6f4b3222befca1092edb73f830a3e3aa68296711"),
            ("Number", .instance, "truncateTo:", "abc6135990bbd35aa81141d701a53a5e305248eb16649127c522f66cca214026"),
            ("Number", .instance, "raisedTo:", "67114c7c826e053b19d5ce1ccb6aba5b26f57c6f3e8f01bd044ae7b21b237cac"),
            ("Number", .instance, "raisedToInteger:", "81d1db4ef753cbaa4525e987ec62ad18e09db8acb91a811c88823eb080ee14b6"),
            ("OrderedCollection", .instance, "addAll:", "57f1bf2ed434e62e1dc22662b23045698771ee96425e9aad98bf965bf6de4e28"),
            ("OrderedCollection", .instance, "removeAll:", "d66b1840b7900aac9facc7e4b99b13f84790ed3476343232734b48ee60298caf"),
            ("String", .instance, "atAll:put:", "6ed74358cb7c72d434eb6cc3df262c2a449de276d12521b905f1686c9de00954"),
            ("String", .instance, "atAllPut:", "4d4f484b05b3b071d0eee1a925db67d8d640e1ed7e59072b466d2da8181ec598"),
            ("Duration", .instance, "_secondsOf:", "9f7d920d97330a07d9ff63df65185a990eafd8ceb2d63f10636fb25b52e58c96"),
            ("Duration", .instance, "/", "f1c4bf951f38eccca9d465ae114d3879e8d92ec58df3cfea7b1e57df415d014a"),
            ("Duration", .instance, "=", "a690af101e6d3a6d45defab3931f2ade64d66af182f3f655ecd5372c56be5c6a"),
            ("DateAndTime", .instance, "offset:", "804db7eb2ad7ea7aebefac3af6e4e8b34fae3f789095dc82abc164b31602ed8f"),
            ("DateAndTime", .instance, "+", "62fc6c7629d86fd78c436d4bba23ac255fcebd799fd0ad217ab0c79a51936236"),
            ("DateAndTime", .instance, "-", "627a46ca33508edfea4f8393bbbe18b421d0a8cd6d9bcc9cb6abb74f97701a22"),
            ("DateAndTime", .classSide, "_year:ordinal:hour:minute:second:offset:", "617ffbb0646bbf82ca7c4276a3bb8c88a3ca375703e445bcfad9383e12ab1887"),
            ("DateAndTime", .classSide, "_checkOffset:", "2bce3d4c335cf3836f93bf627c8afa5bb469289138db61885846813df057ab7f"),
        ]
        for (name, side, selector, hash) in previous {
            guard let owner = runtime.classes[name], let old = owner[side][selector],
                  Self.digest(Data(old.source.utf8)) == hash else { continue }
            if name == "Duration" || name == "DateAndTime" {
                let helper = "_secondsOf:ifAbsent:"
                guard let duration = runtime.classes["Duration"] else { continue }
                if duration.classMethods[helper] == nil {
                    guard duration.classMethods.count < SmalltalkRuntime.methodsPerSideLimit else { continue }
                    try installBundledMethod(helper, on: duration, side: .classSide)
                }
            }
            try installBundledMethod(selector, on: owner, side: side)
        }

        let inheritedMethods: [(String, String, Set<String>)] = [
            ("Interval", "copyFrom:to:", ["baddcf954fc8c10aad26b65fafc4d3141e77688e3c8b0e00e157d864716dc1f7"]),
            ("ByteArray", "copyReplaceAll:with:", ["704bc9c20c595beb78f7cbb0e6411458f0f7188d08a3cb9d981d775b9a53b778"]),
            ("ByteArray", "copyReplacing:withObject:", ["c62917f14fa8a77bb5d20b5cd42898f7afb83698508a1aca50271f7c6b483b40"]),
            ("SortedCollection", "copyReplaceAll:with:", ["704bc9c20c595beb78f7cbb0e6411458f0f7188d08a3cb9d981d775b9a53b778"]),
        ]
        for (name, selector, hashes) in inheritedMethods {
            guard let owner = runtime.classes[name], owner.methods[selector] == nil,
                  owner.methods.count < SmalltalkRuntime.methodsPerSideLimit,
                  let inherited = owner.superclass?.lookup(selector)?.0,
                  hashes.contains(Self.digest(Data(inherited.source.utf8))) else { continue }
            try installBundledMethod(selector, on: owner)
        }
    }

    private func installBundledMethod(_ selector: String, on owner: STClass, side: MethodSide = .instance) throws {
        guard let code = seed[side][owner.name]?[selector], let source = sources[side][owner.name]?[selector] else {
            throw SmalltalkError("Missing bundled ANSI method \(owner.name)»\(selector).")
        }
        owner[side][selector] = try code.validatedMethod(selector: selector, source: source)
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
                "0b2f94eddeb68f29c68c1123fe637f81a71cd6f7971874f9fdc64e8049944eeb",
                "2dc4596961268fbbda4353352e1c00d5981c79405df3cf56e7928b9a7ede4ead",
                "75ed1f3d16104189da608725c97fef2ebe14043c0e0b82330456cc5182adcba2",
            ]),
            (.instance, "shippedClassSideProtocols", [
                "7b2f2950f5dc051c01fdcd0afcdde26c8505606a3c1f370ad2c6910c5eff398c",
                "a57049aae45eec58838977d232ca38087f17d6cadfc40092e4a23df2e68a9a13",
                "b47e4912fcc451571d5cef706f0cc72fdf9e8d9a4642a4e2e6813c2c680df201",
                "b7974c43ae3dd01bbbbcbc727dab84713023b8ee1a57e63894caa2243cf53765",
                "1fa6f5c515c4deea0d6f1347dbd94a2b6067ab009919c6256dde5695e2f50b5b",
                "b72abb7b5d7c66fedb31fdf1aaebe7cc851cb8ca3921ccd4da53a48f76c7a898",
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
                "fc67946a0c407b98e6bca7b54a5b7de684c6658cef3d8c99c5fe972e727bb03c",
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
