import Foundation

/// Developer entry point for rebuilding the shipped seed with the Smalltalk
/// compiler already present in the previous seed.
public enum SmalltalkBootstrap {
    public static func rebuild(in directory: URL, checkOnly: Bool = false) throws {
        try rebuild(in: directory, checkOnly: checkOnly, progress: { _ in })
    }

    public static func rebuild(in directory: URL, checkOnly: Bool, progress: (String) -> Void) throws {
        progress("Loading the boot image and system sources …")
        let oldLibrary = try SystemLibrary(directory: directory)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "st" && $0.lastPathComponent.first?.isNumber == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let sources = try files.map { try String(contentsOf: $0, encoding: .utf8) }
        let compiler = SmalltalkRuntime(bootstrap: false)
        try oldLibrary.install(in: compiler)

        // The previous compiler builds a transition generation. The resulting
        // compiler then builds itself twice to verify a stable executable.
        progress("[1/3] Compiling the system sources with the previous compiler …")
        let transition = try compilerFor(build(sources, using: compiler))
        progress("[2/3] Compiling the system sources with the new compiler …")
        let final = try build(sources, using: transition)
        let rebuilt = try compilerFor(final)
        let artifacts = try encode(final)
        progress("[3/3] Checking that the bootstrap is reproducible …")
        let repeated = try encode(build(sources, using: rebuilt))
        guard artifacts.0 == repeated.0, artifacts.1 == repeated.1 else {
            throw SmalltalkError("The new Smalltalk compiler produces different code when it rebuilds itself.")
        }
        progress("Running InitialWorld.st …")
        _ = try rebuilt.evaluate(oldLibrary.initialWorld)
        if let error = rebuilt.projectWindows().error { throw SmalltalkError(error) }

        let sourcesURL = directory.appendingPathComponent("Smalltalk80.sources")
        let seedURL = directory.appendingPathComponent("Kernel.seed.json")
        if checkOnly {
            progress("Checking the sources archive and boot image …")
            guard try Data(contentsOf: sourcesURL) == artifacts.0, try Data(contentsOf: seedURL) == artifacts.1 else {
                throw SmalltalkError("The boot image or sources archive is out of date. Run the bootstrap again.")
            }
        } else {
            progress("Writing the sources archive and boot image …")
            try artifacts.0.write(to: sourcesURL, options: .atomic)
            try artifacts.1.write(to: seedURL, options: .atomic)
        }
    }

    private struct Build {
        let sources: LibrarySources
        let methods: [MethodSide: [String: [String: Method]]]
    }

    private static func compilerFor(_ build: Build) throws -> SmalltalkRuntime {
        let runtime = SmalltalkRuntime(bootstrap: false)
        for definition in build.sources.definitions {
            guard let parent = runtime.classes[definition.superclass] else {
                throw SmalltalkError("System superclass \(definition.superclass) is missing.")
            }
            _ = try runtime.subclass(of: parent, name: definition.name, fields: definition.fields.joined(separator: " "))
        }
        for (side, tables) in build.methods {
            for (name, methods) in tables { runtime.classes[name]?[side] = methods }
        }
        try runtime.validateCompilerClasses()
        return runtime
    }

    private static func build(_ scripts: [String], using compiler: SmalltalkRuntime) throws -> Build {
        let classes = SmalltalkRuntime(bootstrap: false)
        var definitions: [LibrarySources.Definition] = []
        var methods: [MethodSide: [String: [String: Method]]] = [:]
        for script in scripts {
            let body = try compiler.compileWorkspace(script)
            guard body.temporaries.isEmpty else { throw SmalltalkError("System sources cannot declare workspace variables.") }
            for expression in body.expressions {
                guard case .send(let receiver, let selector, let arguments) = expression.kind,
                      case .variable(let name) = receiver.kind, let stClass = classes.classes[name] else {
                    throw SmalltalkError("Invalid declaration in the system sources.")
                }
                switch selector {
                case "subclass:instanceVariableNames:":
                    guard arguments.count == 2, case .literal(.symbol(let child)) = arguments[0].kind,
                          case .literal(.string(let fields)) = arguments[1].kind else {
                        throw SmalltalkError("Invalid class declaration for \(name).")
                    }
                    let newClass = try classes.subclass(of: stClass, name: child, fields: fields)
                    definitions.append(.init(name: child, superclass: name, fields: newClass.ownFields))
                case "compile:", "compileClass:":
                    guard arguments.count == 1, case .literal(.string(let source)) = arguments[0].kind else {
                        throw SmalltalkError("Invalid method declaration for \(name).")
                    }
                    let side: MethodSide = selector == "compile:" ? .instance : .classSide
                    let method = try compiler.compileMethod(source, fields: stClass.fields(for: side))
                    guard methods[side, default: [:]][name, default: [:]].updateValue(method, forKey: method.selector) == nil else {
                        throw SmalltalkError("Duplicate system method \(side.displayName(for: name))>>\(method.selector).")
                    }
                default:
                    throw SmalltalkError("System sources can only declare classes and methods.")
                }
            }
        }
        let sources = methods.mapValues { $0.mapValues { $0.mapValues(\.source) } }
        return Build(sources: LibrarySources(definitions: definitions, methods: sources[.instance] ?? [:], classMethods: sources[.classSide]), methods: methods)
    }

    private static func encode(_ build: Build) throws -> (Data, Data) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let sources = try encoder.encode(build.sources)
        let code = build.methods.mapValues { $0.mapValues { $0.mapValues(MethodCode.init) } }
        let seed = LibrarySeed(sourcesID: SystemLibrary.digest(sources), methods: code[.instance] ?? [:], classMethods: code[.classSide])
        return (sources, try encoder.encode(seed))
    }
}
