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
    let methods: [String: SelectorMap<String>]
    var classMethods: [String: SelectorMap<String>]?

    subscript(side: MethodSide) -> [String: SelectorMap<String>] { side == .instance ? methods : classMethods ?? [:] }

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
    let methods: [String: SelectorMap<MethodCode>]
    var classMethods: [String: SelectorMap<MethodCode>]?

    subscript(side: MethodSide) -> [String: SelectorMap<MethodCode>] { side == .instance ? methods : classMethods ?? [:] }
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
                guard let stClass = runtime.classes[name], let methodSources = sources[side][name],
                      code.identifierKeys == methodSources.identifierKeys else {
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
            ("Number", .instance, "quo:", "0460eebfd66a76ac33044cd6eb45b74e080d013437bfef9ea395efe637cc8758"),
            ("Number", .instance, "rem:", "d8adbff275e939480bc40380e64ebb7e6ec9d81af8b48108aebba6be6ff6340d"),
            ("ZeroDivide", .instance, "description", "1123eaf8991d61d0f0dd0835652f253930b0aa28f8edb1fa3e6d9aedf5f12038"),
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
            ("Number", .instance, "min:", "5bbe8d98f31963257f1ef0334c9202753cd847ac4bb32eea5e5b7db8bd470c5f"),
            ("Number", .instance, "max:", "22e0f00a6ac2355abe6b247bfd3e9cb9fd1b75ceaaa00b17adb307169708330f"),
            ("Number", .instance, "fractionPart", "95d25d2ef97c7d0b85f414731cfd92efba0e2f38fc0f5274325e4557e61fb37e"),
            ("UnorderedCollection", .instance, "addAll:", "d66068b8901ab028e6768d90a5d92f17b47fdcdacb6d45801d698549e81e083b"),
            ("UnorderedCollection", .instance, "removeAll:", "1abff631dbbb7706dfbbdded0ecca7ab10baf1deda66bece1cb72da0e26e73a0"),
            ("SortedCollection", .instance, "add:", "e1a49c8075be4b6829dd47194053a48284a73fa9b6fa4c66356072240ef28f32"),
            ("SortedCollection", .instance, "addAll:", "dcffdbb8291a1e6d0d66955486460d796f134310655e72245868048595e7b0a4"),
            ("SortedCollection", .instance, "removeAll:", "3281f1b018b515339052ebd68f3ba5e2378b23090e62a7610c5995e26b40477a"),
            ("SortedCollection", .instance, "_sequenceFrom:", "2c5625838d99ad8e5ccdd88fc4a125c81427a2a9d851042cf0221a5e04172d4e"),
            ("SortedCollection", .instance, "_sorted:by:", "f5e2cc574504d55f63e63ab41e9a4f2b4efb74a481c9924fca14a2009bcc6436"),
            ("SortedCollection", .instance, "_insertionIndexOf:", "3664a3924c375d53133b493d114712d52a7b293f220fba6f2be7ee4db64ddf00"),
            ("SortedCollection", .instance, "copyReplaceAll:with:", "cf4403706f7975f89178b3ba27126af2d345addd95591fed085998386e8a8890"),
            ("SortedCollection", .classSide, "withAll:", "a3a34b8b5a7162352af9182ae0508c1fe51420c3424bb8f77ba8527aa045069f"),
            ("CollectionStream", .instance, "_openOn:writing:", "47fdaf4c7e050a542807b95d8e268cdad2ff535a5b55f4f1c652d68965eed271"),
            ("DateAndTime", .instance, "_secondsOf:", "9678ec71d545274a4298e5b28c19650c51203888fba8697f07b7fd0d4d43d79a"),
            ("DateAndTime", .instance, "-", "a8919fbbd832a612bb9193a8681fa6236f7d5b74b23395900bea800628003fa0"),
            ("DateAndTime", .instance, "=", "1ea3d6c5e555b7a5a68d8b2d301adb33c818152db90c48f3cae1316732e39fd6"),
            ("DateAndTime", .instance, "asLocal", "6b41d492c4cdc804559766f82537498ca02e0c6e34f8fe50820b03a09d9d5de2"),
            ("Fraction", .instance, "sqrt", "fc3b3aead2ade1001067870caae4c1dc452003ebe5ea5f9ce72575297133067a"),
            ("ScaledDecimal", .instance, "sqrt", "fc3b3aead2ade1001067870caae4c1dc452003ebe5ea5f9ce72575297133067a"),
            ("Float", .instance, "log:", "58b4458e6a3de5b1406ce2d0972afb0cdc0e052881ffb1550fb534f9d8a1a241"),
            ("Float", .instance, "degreesToRadians", "14d1c26bd3a6cfdbac233c1c959e8b20fe3c9fec7e087b306668cd78720db96e"),
            ("Float", .instance, "radiansToDegrees", "d741857951fc023c9c6470282c6e286c856c2dffa1d0414bba334476397cafaf"),
            ("STScanner", .instance, "readToken", "70caa551966f06d3e39d3f05393516dda8cf92d4facc6dc9efda7d899e370959"),
            ("STCompiler", .instance, "expressionNode", "36ec61e2d292ee1bfbd61d439df6465b3e693a1bd77cb055a3b9455eaf726373"),
            ("Interval", .instance, "at:", "2daeb92537fbe936d9eba788514f05306df5d3219bd93ef83a18ea309672565b"),
            ("Interval", .instance, "do:", "8c6e61ac5b7ddc7a2d0fb5ab80f2d22e3d2ccb64995b24f66156b63cbf16c35d"),
            ("Interval", .instance, "initializeFrom:to:by:", "94e5907b4f2e505485ea4772e499ac063509744fa89399f6b4bd09547550e53a"),
            ("Interval", .instance, "_elementAt:", "44140153b2c5b7f97367ba026f50a994c5ded5c657910e9f7bead5e112643918"),
            ("String", .instance, "atAll:put:", "dd53f6f22da39ec119cd2ca2aaa6768a277ffc7da8548f962a784a9abe3449fa"),
            ("String", .instance, "atAllPut:", "f920caa69425f10f9514140fd8577a677032a85f899c9f1b2f2386e6e2993a7f"),
            ("ByteArray", .instance, "atAll:put:", "a732a713cd71548c376135c4b6d8b97c88e1f4bde8fa1b25489659ef778a690a"),
            ("ByteArray", .instance, "atAllPut:", "1b12b6a11180b2a54e2758536e6ddc9982982ad9df9416de4031c445cf357e5d"),
            ("OrderedCollection", .instance, "atAll:put:", "864a238804d6c1d4b07767b085d267ea9abba319497129619c4aa03a219801a0"),
            ("OrderedCollection", .instance, "atAllPut:", "7fe75273c77903048b5bec9705027b6455d3791e60436031ce86450b5ef67e1f"),
        ]
        let instanceHelpers = [
            "DateAndTime": ["_secondsOf:ifAbsent:"],
            "Interval": ["_elementAt:"],
            "STCompiler": ["cascadeBranch"],
            "SortedCollection": ["_insertionIndexOf:", "_sortElementsFrom:", "_validateSortElement:by:"],
        ]
        for (name, side, selector, hash) in previous {
            guard let owner = runtime.classes[name], let old = owner[side][selector],
                  Self.digest(Data(old.source.utf8)) == hash else { continue }
            let missing = (instanceHelpers[name] ?? []).filter { owner.methods[$0] == nil }
            guard owner.methods.count + missing.count <= SmalltalkRuntime.methodsPerSideLimit else { continue }
            for helper in missing { try installBundledMethod(helper, on: owner) }
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
            ("SortedCollection", "copyReplacing:withObject:", ["c62917f14fa8a77bb5d20b5cd42898f7afb83698508a1aca50271f7c6b483b40"]),
        ]
        for (name, selector, hashes) in inheritedMethods {
            guard let owner = runtime.classes[name], owner.methods[selector] == nil,
                  owner.methods.count < SmalltalkRuntime.methodsPerSideLimit,
                  let inherited = owner.superclass?.lookup(selector)?.0,
                  hashes.contains(Self.digest(Data(inherited.source.utf8))) else { continue }
            if name == "SortedCollection" {
                let missing = ["_insertionIndexOf:", "_validateSortElement:by:"].filter { owner.methods[$0] == nil }
                guard owner.methods.count + missing.count < SmalltalkRuntime.methodsPerSideLimit else { continue }
                for helper in missing { try installBundledMethod(helper, on: owner) }
            }
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
                "a267649a8048e76bc31c92de3d30c3bc43ee598b46c9057c7147d908649a58c1",
                "d8f36c420419a594dd037decee2beaf425730909ddb40c3bd1c72f26452ced42",
                "b5b1bceefac15f4d9a37487ea74bf0dae8e758126ce5bb2bd46bb84fc726537a",
                "e75bb31ac481edf61057381730ae3e143301db8234b00c176cf53129b05c6d5f",
                "9f336f43cf736c3c1a801846376887f192631192f4aadd79164c7f1a2547655e",
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
