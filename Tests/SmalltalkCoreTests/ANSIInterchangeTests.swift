import Foundation
import Testing
@testable import SmalltalkCore

struct ANSIInterchangeTests {
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
}
