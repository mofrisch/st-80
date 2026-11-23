import Foundation

/// Developer entry point for rebuilding the shipped seed with the Smalltalk
/// compiler already present in the previous seed.
public enum SmalltalkBootstrap {
    public static func rebuild(in directory: URL, checkOnly: Bool = false) throws {
        try rebuild(in: directory, checkOnly: checkOnly, progress: { _ in })
    }

    public static func rebuild(in directory: URL, checkOnly: Bool, progress: (String) -> Void) throws {
        progress("Startimage und Systemquellen laden …")
        let oldLibrary = try SystemLibrary(directory: directory)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "st" && $0.lastPathComponent.first?.isNumber == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let sources = try files.map { try String(contentsOf: $0, encoding: .utf8) }
        let compiler = SmalltalkRuntime(bootstrap: false)
        try oldLibrary.install(in: compiler)

        // The previous compiler builds a transition generation. The resulting
        // compiler then builds itself twice to verify a stable executable.
        progress("[1/3] Systemquellen mit dem bisherigen Compiler übersetzen …")
        let transition = try compilerFor(build(sources, using: compiler))
        progress("[2/3] Systemquellen mit dem neuen Compiler übersetzen …")
        let final = try build(sources, using: transition)
        let rebuilt = try compilerFor(final)
        let artifacts = try encode(final)
        progress("[3/3] Reproduzierbarkeit des Selbstbaus prüfen …")
        let repeated = try encode(build(sources, using: rebuilt))
        guard artifacts.0 == repeated.0, artifacts.1 == repeated.1 else {
            throw SmalltalkError("Der neu gebaute Smalltalk-Compiler erzeugt beim Selbstbau abweichenden Code.")
        }
        progress("InitialWorld.st ausführen …")
        _ = try rebuilt.evaluate(oldLibrary.initialWorld)
        if let error = rebuilt.projectWindows().error { throw SmalltalkError(error) }

        let sourcesURL = directory.appendingPathComponent("Smalltalk80.sources")
        let seedURL = directory.appendingPathComponent("Kernel.seed.json")
        if checkOnly {
            progress("Quellenarchiv und Startimage vergleichen …")
            guard try Data(contentsOf: sourcesURL) == artifacts.0, try Data(contentsOf: seedURL) == artifacts.1 else {
                throw SmalltalkError("Startimage oder Sources-Archiv sind veraltet. Starte den Bootstrap-Build erneut.")
            }
        } else {
            progress("Quellenarchiv und Startimage schreiben …")
            try artifacts.0.write(to: sourcesURL, options: .atomic)
            try artifacts.1.write(to: seedURL, options: .atomic)
        }
    }

    private struct Build {
        let sources: LibrarySources
        let methods: [String: [String: Method]]
    }

    private static func compilerFor(_ build: Build) throws -> SmalltalkRuntime {
        let runtime = SmalltalkRuntime(bootstrap: false)
        for definition in build.sources.definitions {
            guard let parent = runtime.classes[definition.superclass] else {
                throw SmalltalkError("System-Oberklasse \(definition.superclass) fehlt.")
            }
            let stClass = try runtime.subclass(of: parent, name: definition.name, fields: definition.fields.joined(separator: " "))
            stClass.methods = build.methods[definition.name] ?? [:]
        }
        for (name, methods) in build.methods where SmalltalkRuntime.builtinNames.contains(name) {
            runtime.classes[name]?.methods = methods
        }
        try runtime.validateCompilerClasses()
        return runtime
    }

    private static func build(_ scripts: [String], using compiler: SmalltalkRuntime) throws -> Build {
        let classes = SmalltalkRuntime(bootstrap: false)
        var definitions: [LibrarySources.Definition] = []
        var methods: [String: [String: Method]] = [:]
        for script in scripts {
            let body = try compiler.compileWorkspace(script)
            guard body.temporaries.isEmpty else { throw SmalltalkError("Systemquellen dürfen keine Workspace-Variablen deklarieren.") }
            for expression in body.expressions {
                guard case .send(let receiver, let selector, let arguments) = expression.kind,
                      case .variable(let name) = receiver.kind, let stClass = classes.classes[name] else {
                    throw SmalltalkError("Ungültige Deklaration in den Systemquellen.")
                }
                switch selector {
                case "subclass:instanceVariableNames:":
                    guard arguments.count == 2, case .literal(.symbol(let child)) = arguments[0].kind,
                          case .literal(.string(let fields)) = arguments[1].kind else {
                        throw SmalltalkError("Ungültige Klassendeklaration für \(name).")
                    }
                    let newClass = try classes.subclass(of: stClass, name: child, fields: fields)
                    definitions.append(.init(name: child, superclass: name, fields: newClass.ownFields))
                case "compile:":
                    guard arguments.count == 1, case .literal(.string(let source)) = arguments[0].kind else {
                        throw SmalltalkError("Ungültige Methodendeklaration für \(name).")
                    }
                    let method = try compiler.compileMethod(source, fields: stClass.fields)
                    guard methods[name, default: [:]].updateValue(method, forKey: method.selector) == nil else {
                        throw SmalltalkError("Doppelte Systemmethode \(name)>>\(method.selector).")
                    }
                default:
                    throw SmalltalkError("Systemquellen dürfen nur Klassen und Methoden deklarieren.")
                }
            }
        }
        return Build(sources: LibrarySources(definitions: definitions, methods: methods.mapValues { $0.mapValues(\.source) }), methods: methods)
    }

    private static func encode(_ build: Build) throws -> (Data, Data) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let sources = try encoder.encode(build.sources)
        let seed = LibrarySeed(sourcesID: SystemLibrary.digest(sources), methods: build.methods.mapValues { $0.mapValues(MethodCode.init) })
        return (sources, try encoder.encode(seed))
    }
}
