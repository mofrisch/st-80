import Foundation
import Testing
@testable import SmalltalkCore

struct ANSIInterchangeTests {
    @Test func interchangeGlobalsAndPoolEntriesFollowTheirDeclarations() async throws {
        let session = SmalltalkSession()
        let header = "Smalltalk interchangeVersion: '1.0'!\n"
        let global = "Global constant: 'SIFOrderedGlobal'!"
        let globalInitializer = "SIFOrderedGlobal initializer! 17!"
        let pool = "Pool named: 'SIFOrderedPool'!"
        let variable = "SIFOrderedPool variable: 'Item'!"
        let initializer = "SIFOrderedPool initializerFor: 'Item'! 23!"
        for entries in [[globalInitializer, global], [variable, pool], [pool, initializer, variable]] {
            let rejected = await session.evaluate(header + entries.joined(separator: "\n"))
            #expect(rejected.error?.contains("must precede") == true)
        }
        #expect(await session.evaluate("SIFOrderedGlobal").error?.contains("Unknown variable") == true)
        #expect(await session.evaluate("SIFOrderedPool").error?.contains("Unknown variable") == true)

        let valid = await session.evaluate(header + [global, globalInitializer, pool, variable, initializer, """
            Class named: 'SIFOrderedLookup' superclass: 'Object' indexedInstanceVariables: #'none'
                instanceVariableNames: '' classVariableNames: '' sharedPools: 'SIFOrderedPool' classInstanceVariableNames: ''!
            SIFOrderedLookup method! item ^ Item!
            """].joined(separator: "\n"))
        try #require(valid.error == nil)
        #expect(await session.evaluate("Array with: SIFOrderedGlobal with: SIFOrderedLookup new item").value == "#(17 23)")
    }

    @Test func interchangeMethodsAndClassInitializersFollowTheirClassDeclaration() async {
        let session = SmalltalkSession()
        let header = "Smalltalk interchangeVersion: '1.0'!\n"
        let declaration = """
            Class named: 'SIFOrderedDeclaration' superclass: 'Object' indexedInstanceVariables: #'none'
                instanceVariableNames: '' classVariableNames: '' sharedPools: '' classInstanceVariableNames: ''!\n
            """
        let method = "SIFOrderedDeclaration method! answer ^ 77!"
        let classMethod = "SIFOrderedDeclaration classMethod! answer ^ 88!"
        let initializer = "SIFOrderedDeclaration initializer! self answer!"
        for entry in [method, classMethod, initializer] {
            let rejected = await session.evaluate(header + entry + "\n" + declaration)
            #expect(rejected.error?.contains("must precede") == true)
            #expect(await session.evaluate("SIFOrderedDeclaration").error?.contains("Unknown variable") == true)
        }
        let valid = await session.evaluate(header + declaration + [method, classMethod, initializer].joined(separator: "\n"))
        #expect(valid.error == nil)
        #expect(await session.evaluate("SIFOrderedDeclaration new answer").value == "77")
        #expect(await session.evaluate("SIFOrderedDeclaration answer").value == "88")
    }

    @Test func inheritedMethodsResolveGlobalsInTheirDefiningClass() async throws {
        let session = SmalltalkSession()
        let setup = await session.evaluate("""
            Smalltalk interchangeVersion: '1.0'!
            Global variable: 'SIFLexicalValue'!
            SIFLexicalValue initializer! 41!
            Class named: 'SIFLexicalBase' superclass: 'Object' indexedInstanceVariables: #'none'
                instanceVariableNames: '' classVariableNames: '' sharedPools: '' classInstanceVariableNames: ''!
            SIFLexicalBase method! readGlobal ^ [ SIFLexicalValue ] value!
            SIFLexicalBase method! writeGlobal: value [ SIFLexicalValue := value ] value!
            Class named: 'SIFLexicalChild' superclass: 'SIFLexicalBase' indexedInstanceVariables: #'none'
                instanceVariableNames: 'SIFLexicalValue' classVariableNames: '' sharedPools: '' classInstanceVariableNames: ''!
            SIFLexicalChild method! readField ^ SIFLexicalValue!
            SIFLexicalChild method! writeField: value SIFLexicalValue := value!
            """)
        try #require(setup.error == nil)
        let result = await session.evaluate("""
            | child before |
            child := SIFLexicalChild new.
            child writeField: 7.
            before := child readGlobal.
            child writeGlobal: 99.
            Array with: before with: SIFLexicalValue with: child readField
            """)
        #expect(result.value == "#(41 99 7)")
    }

    @Test func invalidBindingsAreRejectedBeforeInstallingOrInitializingAnything() async {
        let session = SmalltalkSession()
        let invalidMethod = await session.evaluate("""
            Smalltalk interchangeVersion: '1.0'!
            Class named: 'SIFUnbound' superclass: 'Object' indexedInstanceVariables: #'none'
                instanceVariableNames: '' classVariableNames: '' sharedPools: '' classInstanceVariableNames: ''!
            SIFUnbound method! missing ^ [ UnknownMethodBinding ] value!
            """)
        #expect(invalidMethod.error?.contains("Unknown variable: UnknownMethodBinding") == true)
        #expect(await session.evaluate("SIFUnbound").error?.contains("Unknown variable") == true)

        let declarations = """
            Smalltalk interchangeVersion: '1.0'!
            Global variable: 'SIFBindingRetry'!
            SIFBindingRetry initializer! 17!
            """
        let invalidAssignment = await session.evaluate(declarations + "\nGlobal initializer! UndeclaredInitializerTarget := 42!")
        #expect(invalidAssignment.error?.contains("Unknown variable: UndeclaredInitializerTarget") == true)
        #expect(await session.evaluate("SIFBindingRetry").error?.contains("Unknown variable") == true)
        #expect(await session.evaluate(declarations).error == nil)
        #expect(await session.evaluate("SIFBindingRetry").value == "17")
    }

    @Test func interchangeConstructionRemainsIndependentOfInitializeAfterImageLoad() async throws {
        let session = SmalltalkSession()
        let imported = await session.evaluate("""
            Smalltalk interchangeVersion: '1.0'!
            Class named: 'SIFConstructorProbe' superclass: 'Object' indexedInstanceVariables: #'none'
                instanceVariableNames: 'slot' classVariableNames: '' sharedPools: '' classInstanceVariableNames: ''!
            SIFConstructorProbe method! initialize slot := 10!
            SIFConstructorProbe method! slot ^ slot!
            """)
        try #require(imported.error == nil)
        #expect(await session.evaluate("SIFConstructorProbe new slot").value == "nil")

        let image = try await session.imageData()
        let restored = SmalltalkSession()
        _ = try await restored.loadImage(image)
        #expect(await restored.evaluate("SIFConstructorProbe new slot").value == "nil")
        #expect(await restored.evaluate("SIFConstructorProbe new initialize; slot").value == "10")

        var archive = try JSONDecoder().decode(ImageArchive.self, from: image)
        let index = try #require(archive.classes.firstIndex { $0.name == "SIFConstructorProbe" })
        archive.classes[index].usesANSIAllocation = nil
        _ = try await restored.loadImage(JSONEncoder().encode(archive))
        #expect(await restored.evaluate("SIFConstructorProbe new slot").value == "10")
    }

    @Test func rootClassesReportTheClassPrimitivesTheyCanPerform() async {
        let session = SmalltalkSession()
        let imported = await session.evaluate("""
            Smalltalk interchangeVersion: '1.0'!
            Class named: 'SIFReflectionRoot' superclass: 'nil' indexedInstanceVariables: #'none'
                instanceVariableNames: '' classVariableNames: '' sharedPools: '' classInstanceVariableNames: ''!
            Class named: 'SIFReflectionChild' superclass: 'SIFReflectionRoot' indexedInstanceVariables: #'none'
                instanceVariableNames: '' classVariableNames: '' sharedPools: '' classInstanceVariableNames: ''!
            """)
        #expect(imported.error == nil)
        let result = await session.evaluate("""
            Array with: (SIFReflectionRoot respondsTo: #new) with: (SIFReflectionRoot perform: #new) class
                with: (SIFReflectionChild respondsTo: #superclass) with: (SIFReflectionChild perform: #superclass)
            """)
        #expect(result.value == "#(true SIFReflectionRoot true SIFReflectionRoot)")
        #expect(await session.evaluate("SIFReflectionRoot respondsTo: #uninstalledMethod").value == "false")
    }

    @Test func importsFileAndRunsInitializersAfterInstallingMethods() async throws {
        let session = SmalltalkSession()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("program.st")
        try """
            "A comment may precede the header"
            Smalltalk interchangeVersion: '1.0'!
            "A standalone comment chunk"!
            Global variable: 'SIFOrder'!
            Global constant: 'SIFMessage'!
            Class named: 'SIFGreeter' superclass: 'Object'
                indexedInstanceVariables: #'none' instanceVariableNames: ''
                classVariableNames: 'Shared' sharedPools: '' classInstanceVariableNames: 'State'!
            Annotation key: 'comment' value: 'Hello!!'!
            SIFOrder initializer! OrderedCollection new!
            SIFMessage initializer! 'Hello!!'!
            SIFGreeter initializer! Shared := self initialShared. State := Shared + 1. SIFOrder add: #class!
            Global initializer! SIFOrder add: #program!
            SIFGreeter classMethod! initialShared ^ 41!
            SIFGreeter classMethod! state ^ State!
            SIFGreeter method! message ^ SIFMessage!
            SIFGreeter method! shared ^ Shared!
            """.write(to: file, atomically: true, encoding: .utf8)

        let imported = try await session.importInterchange(from: file)
        try #require(imported.error == nil, "\(imported.error ?? "")")
        #expect(imported.changes.contains { $0.className == "SIFGreeter" && $0.selector == "message" })
        let result = await session.evaluate("""
            Array with: SIFGreeter new message with: SIFGreeter new shared
                with: SIFGreeter state with: SIFOrder asArray
            """)
        #expect(result.value == "#('Hello!' 41 42 #(#class #program))")
        #expect(await session.evaluate("SIFMessage := 'modified'").error?.contains("cannot be reassigned") == true)
    }

    @Test func resolvesSharedClassVariablesAndPoolBindingsLexically() async throws {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            Smalltalk interchangeVersion: '1.0'!
            Pool named: 'SIFPool'!
            SIFPool constant: 'Rate'!
            SIFPool variable: 'Runs'!
            SIFPool initializerFor: 'Rate'! 2!
            SIFPool initializerFor: 'Runs'! Rate + 1!
            Class named: 'SIFBase' superclass: 'Object' indexedInstanceVariables: #'none'
                instanceVariableNames: '' classVariableNames: 'Shared' sharedPools: 'SIFPool' classInstanceVariableNames: ''!
            SIFBase classMethod! configure Shared := Rate!
            SIFBase method! tick Runs := Runs + Shared. ^ Runs!
            SIFBase method! shared: value Shared := value!
            """)
        try #require(result.error == nil, "\(result.error ?? "")")
        let child = await session.evaluate("""
            SIFBase subclass: #SIFChild instanceVariableNames: '' classVariableNames: ''
                poolDictionaries: 'SIFPool' category: 'Tests'.
            SIFChild compileClass: 'shared ^ Shared'.
            SIFChild configure.
            """)
        try #require(child.error == nil, "\(child.error ?? "")")
        let values = await session.evaluate("""
            first := SIFChild new tick.
            SIFBase new shared: 7.
            Array with: first with: SIFChild shared with: SIFBase new tick
            """)
        #expect(values.value == "#(5 7 12)")
    }

    @Test func installsDeclarationsFromAllFilesBeforeInitializingInFileOrder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.st")
        let second = directory.appendingPathComponent("second.st")
        try """
            Smalltalk interchangeVersion: '1.0'!
            Global constant: 'SIFSaved'!
            SIFSaved initializer! SIFLater!
            """.write(to: first, atomically: true, encoding: .utf8)
        try """
            Smalltalk interchangeVersion: '1.0'!
            Global variable: 'SIFLater'!
            SIFLater initializer! 7!
            """.write(to: second, atomically: true, encoding: .utf8)
        let session = SmalltalkSession()
        try #require(try await session.importInterchange(from: [first, second]).error == nil)
        #expect(await session.evaluate("Array with: SIFSaved with: SIFLater").value == "#(nil 7)")
        let repeated = await session.evaluate("""
            Smalltalk interchangeVersion: '1.0'!
            SIFSaved initializer! 42!
            """)
        #expect(repeated.error?.contains("already initialized") == true)
        #expect(await session.evaluate("SIFSaved").value == "nil")
    }

    @Test func rejectsInvalidFilesAndConstantWritesBeforeInstallingDefinitions() async throws {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            Smalltalk interchangeVersion: '1.0'!
            Global constant: 'SIFNeverInstalled'!
            Global initializer! [ SIFNeverInstalled := 42 ] value!
            """)
        #expect(result.error?.contains("Cannot assign to SIFNeverInstalled") == true)
        #expect(await session.evaluate("SIFNeverInstalled").error?.contains("Unknown variable") == true)

        let unsupported = await session.evaluate("Smalltalk interchangeVersion: '2.0'!")
        #expect(unsupported.error?.contains("Unsupported interchange version") == true)

        let invalidSuper = await session.evaluate("""
            Smalltalk interchangeVersion: '1.0'!
            Class named: 'SIFInvalidInitializer' superclass: 'Object' indexedInstanceVariables: #'none'
                instanceVariableNames: '' classVariableNames: '' sharedPools: '' classInstanceVariableNames: ''!
            SIFInvalidInitializer initializer! [ super class ] value!
            """)
        #expect(invalidSuper.error?.contains("super is unavailable") == true)
        #expect(await session.evaluate("SIFInvalidInitializer").error?.contains("Unknown variable") == true)

        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".st")
        try "SIFNonInterchange := 42".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try await session.importInterchange(from: file).error?.contains("missing its !") == true)
        #expect(await session.evaluate("SIFNonInterchange").error?.contains("Unknown variable") == true)
    }

    @Test func versionHeaderRequiresAnInterchangeElement() async throws {
        let session = SmalltalkSession()
        let header = "Smalltalk interchangeVersion: '1.0'!"
        let empty = await session.evaluate(header)
        #expect(empty.error?.contains("at least one interchange element") == true)

        let whitespace = await session.evaluate(header + "\n  !\n")
        #expect(whitespace.error?.contains("at least one interchange element") == true)

        let annotation = await session.evaluate(header + "\nAnnotation key: 'note' value: 'example'!")
        #expect(annotation.error?.contains("annotation must follow an interchange element") == true)

        let comment = await session.evaluate(header + "\n\"A standalone interchange comment\"!")
        #expect(comment.error == nil)
        #expect(comment.value == "nil")

        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".st")
        defer { try? FileManager.default.removeItem(at: file) }
        try header.write(to: file, atomically: true, encoding: .utf8)
        let imported = try await session.importInterchange(from: file)
        #expect(imported.error?.contains("at least one interchange element") == true)
    }

    @Test func indexableClassesSupportNamedFieldsByteBoundsAndZeroBasedAllocationSize() async throws {
        let session = SmalltalkSession()
        let imported = await session.evaluate("""
            Smalltalk interchangeVersion: '1.0'!
            Class named: 'SIFVector' superclass: 'Object' indexedInstanceVariables: #'object'
                instanceVariableNames: 'label' classVariableNames: '' sharedPools: '' classInstanceVariableNames: ''!
            SIFVector classMethod! slots: size ^ self basicNew: size!
            SIFVector method! label: value label := value!
            SIFVector method! label ^ label!
            SIFVector method! slot: index ^ self basicAt: index!
            SIFVector method! slot: index put: value ^ self basicAt: index put: value!
            SIFVector method! capacity ^ self basicSize!
            Class named: 'SIFByteVector' superclass: 'Object' indexedInstanceVariables: #'byte'
                instanceVariableNames: '' classVariableNames: '' sharedPools: '' classInstanceVariableNames: ''!
            SIFByteVector classMethod! slots: size ^ self basicNew: size!
            SIFByteVector method! slot: index ^ self basicAt: index!
            SIFByteVector method! slot: index put: value ^ self basicAt: index put: value!
            """)
        try #require(imported.error == nil, "\(imported.error ?? "")")
        let values = await session.evaluate("""
            SIFVector subclass: #SIFVectorChild instanceVariableNames: 'extra'.
            sifVector := SIFVectorChild slots: 2.
            sifVector label: 'v'; slot: 2 put: 'value'.
            sifBytes := SIFByteVector slots: 2.
            sifBytes slot: 2 put: 255.
            Array with: sifVector class with: (sifVector copy slot: 2)
                with: (Array with: sifVector capacity with: sifVector label with: (sifVector slot: 1))
                with: (Array with: (sifBytes slot: 1) with: (sifBytes slot: 2))
            """)
        #expect(values.value == "#(SIFVectorChild 'value' #(2 'v' nil) #(0 255))")
        #expect(await session.evaluate("sifBytes slot: 2 put: 256").error?.contains("byte slot") == true)
        #expect(await session.evaluate("sifVector slot: 0").error != nil)
        #expect(await session.evaluate("(SIFVector slots: 0) capacity").value == "0")
        #expect(await session.evaluate("Array with: (sifVector respondsTo: #basicSize) with: (sifVector perform: #basicSize)").value == "#(true 2)")
    }

    @Test func exportsClassDefinitionAndMethodsForRoundTrip() async throws {
        let session = SmalltalkSession()
        let created = await session.evaluate("""
            Object subclass: #SIFExportProbe instanceVariableNames: 'label' classVariableNames: 'Shared'
                poolDictionaries: '' category: 'Tests'.
            SIFExportProbe compile: 'label ^ label'.
            SIFExportProbe compile: 'label: value label := value. ^ self'.
            SIFExportProbe compileClass: 'shared ^ Shared'.
            SIFExportProbe compileClass: 'shared: value Shared := value'.
            SIFExportProbe shared: 7.
            """)
        try #require(created.error == nil, "\(created.error ?? "")")

        let exported = try await session.worker.submitThrowing { runtime in
            try SmalltalkInterchange.export(classes: ["SIFExportProbe"], from: runtime)
        }
        #expect(exported.contains("Smalltalk interchangeVersion: '1.0'!"))
        #expect(exported.contains("classVariableNames: 'Shared'"))
        #expect(exported.contains("SIFExportProbe method!"))
        #expect(exported.contains("SIFExportProbe classMethod!"))

        let other = SmalltalkSession()
        let imported = await other.evaluate(exported)
        try #require(imported.error == nil, "\(imported.error ?? "")")
        let values = await other.evaluate("""
            SIFExportProbe shared: 11.
            probe := SIFExportProbe new label: 'hi'.
            Array with: probe label with: SIFExportProbe shared
            """)
        #expect(values.value == "#('hi' 11)")
    }
}
