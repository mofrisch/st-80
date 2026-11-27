import Foundation
import Testing
@testable import SmalltalkCore

struct ANSIBindingImageTests {
    @Test(arguments: [false, true])
    func savedImagesUpgradeShippedIntervalCopyAndKeepCustomOverrides(custom: Bool) async throws {
        let session = SmalltalkSession()
        let data = try await session.worker.submitThrowing { runtime in
            let interval = try #require(runtime.classes["Interval"])
            if custom {
                try runtime.compile("copyFrom: first to: last ^ #(77)", in: interval)
            } else {
                interval.methods.removeValue(forKey: "copyFrom:to:")
            }
            let stream = try #require(runtime.classes["CollectionStream"])
            try runtime.compile("""
                _sliceFrom: start to: stop
                    | slice |
                    slice := self _sequence copyFrom: start to: stop.
                    buffer isNil ifTrue: [ ^ slice ].
                    ^ backing copyReplaceFrom: 1 to: backing size with: slice
                """, in: stream)
            return try ImageCodec.encode(runtime, workspace: "", transcript: "")
        }
        let restored = SmalltalkSession()
        _ = try await restored.loadImage(data)
        let result = await restored.evaluate("[ (1 to: 3) copyFrom: 4 to: 1 ] on: Error do: [ :error | #invalidIndex ]")
        #expect(result.value == (custom ? "#(77)" : "#invalidIndex"))
        #expect(await restored.evaluate("(ReadStream on: (1 to: 0)) contents").value == "#()")
    }

    @Test func legacyImagesUpgradeShippedBehaviorAndRetainCustomMethods() async throws {
        let session = SmalltalkSession()
        let data = try await session.worker.submitThrowing { runtime in
            let number = try #require(runtime.classes["Number"])
            let float = try #require(runtime.classes["Float"])
            _ = try runtime.compile("roundTo: factor\n    ^ (self / factor) rounded * factor", in: number)
            number.methods.removeValue(forKey: "_coerceRoundingFactor:")
            _ = try runtime.compile("log: factor ^ 77", in: float)
            var archive = try ImageCodec.capture(runtime, workspace: "", transcript: "", includesCode: true)
            archive.version = 9
            return try JSONEncoder().encode(archive)
        }
        let restored = SmalltalkSession()
        _ = try await restored.loadImage(data)
        #expect(await restored.evaluate("(3.4 roundTo: 1) class").value == "Float")
        #expect(await restored.evaluate("10.0 log: 10").value == "77")
    }

    @Test(arguments: [false, true])
    func interchangeStateSurvivesImageLoad(native: Bool) async throws {
        let original = try await sessionWithInterchangeState()
        _ = await original.collectGarbage()
        let restored = SmalltalkSession()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("st80-ansi-image-\(UUID())")
        defer { if native { try? FileManager.default.removeItem(at: directory) } }
        if native {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let image = directory.appendingPathComponent("Interchange.stimage")
            try await original.saveImage(to: image, workspace: "", transcript: "")
            _ = try await restored.loadImage(from: image)
        } else {
            _ = try await restored.loadImage(original.imageData())
        }
        _ = await restored.collectGarbage()

        let indexed = await restored.evaluate("""
            Array with: ImageIndexed superclass isNil
                with: ((imageIndexed basicAt: 1) == imageIndexed)
                with: (imageIndexed basicAt: 2)
                with: imageIndexed label
            """)
        #expect(indexed.error == nil)
        #expect(indexed.value == "#(true true #(73) 'named slot')")

        let shared = await restored.evaluate("""
            Array with: (imageIndexed readShared == ImageIndexed readShared)
                with: imageIndexed readShared
                with: imageIndexed readPool
                with: imageIndexed incrementPool
            """)
        #expect(shared.error == nil)
        #expect(shared.value == "#(true #(42) #(31) 8)")

        let globalAndBytes = await restored.evaluate("""
            Array with: ImageSavedConstant with: imageOctets basicSize
                with: (imageOctets basicAt: 1) with: (imageOctets basicAt: 2)
            """)
        #expect(globalAndBytes.error == nil)
        #expect(globalAndBytes.value == "#(37 2 0 255)")
        #expect(await restored.evaluate("ImageSavedConstant := 0").error?.contains("ImageSavedConstant") == true)
        let reinitialization = await restored.evaluate("""
            Smalltalk interchangeVersion: '1.0'!
            ImageSavedConstant initializer! 0!
            """)
        #expect(reinitialization.error?.contains("already initialized") == true)

        let poolConstant = await restored.evaluate("""
            ImageIndexed compile: 'changePool PoolAnchor := 0'.
            imageIndexed changePool
            """)
        #expect(poolConstant.error?.contains("PoolAnchor") == true)
        #expect(await restored.evaluate("imageIndexed readPool").value == "#(31)")
    }

    @Test func outOfRangeByteInImageLeavesCurrentSessionUntouched() async throws {
        let original = try await sessionWithInterchangeState()
        var archive = try JSONDecoder().decode(ImageArchive.self, from: await original.imageData())
        guard case .reference(let id)? = archive.globals["imageOctets"],
              archive.nodes.indices.contains(id),
              case .object(var object) = archive.nodes[id] else {
            Issue.record("Missing byte-indexed instance in the saved image.")
            return
        }
        object.indexedFields = [.integer(256)]
        archive.nodes[id] = .object(object)

        let restored = SmalltalkSession()
        #expect(await restored.evaluate("kept := 42").error == nil)
        let damaged = try JSONEncoder().encode(archive)
        await #expect(throws: SmalltalkError.self) { try await restored.loadImage(damaged) }
        #expect(await restored.evaluate("kept").value == "42")
    }

    private func sessionWithInterchangeState() async throws -> SmalltalkSession {
        let session = SmalltalkSession()
        let setup = await session.evaluate("""
            Smalltalk interchangeVersion: '1.0'!
            Global constant: 'ImageSavedConstant'!
            Global variable: 'imageIndexed'!
            Global variable: 'imageOctets'!
            Pool named: 'ImageSavedPool'!
            ImageSavedPool constant: 'PoolAnchor'!
            ImageSavedPool variable: 'PoolReader'!
            ImageSavedPool variable: 'PoolCount'!
            Class named: 'ImageIndexed' superclass: 'nil' indexedInstanceVariables: #'object'
                instanceVariableNames: 'label' classVariableNames: 'SharedAnchor'
                sharedPools: 'ImageSavedPool' classInstanceVariableNames: ''!
            Class named: 'ImageIndexedChild' superclass: 'ImageIndexed' indexedInstanceVariables: #'none'
                instanceVariableNames: '' classVariableNames: '' sharedPools: '' classInstanceVariableNames: ''!
            Class named: 'ImageOctets' superclass: 'Object' indexedInstanceVariables: #'byte'
                instanceVariableNames: '' classVariableNames: '' sharedPools: '' classInstanceVariableNames: ''!
            ImageIndexed method!
            label: text label := text!
            ImageIndexed method!
            label ^ label!
            ImageIndexed method!
            readShared ^ SharedAnchor!
            ImageIndexed classMethod!
            readShared ^ SharedAnchor!
            ImageIndexed method!
            readPool ^ PoolReader value!
            ImageIndexed method!
            incrementPool PoolCount := PoolCount + 1. ^ PoolCount!
            ImageIndexed initializer!
            SharedAnchor := Array with: 42!
            ImageSavedPool initializerFor: 'PoolAnchor'!
            Array with: 31!
            ImageSavedPool initializerFor: 'PoolReader'!
            [ PoolAnchor ]!
            ImageSavedPool initializerFor: 'PoolCount'!
            7!
            ImageSavedConstant initializer!
            37!
            Global initializer!
            imageIndexed := ImageIndexedChild basicNew: 2.
            imageIndexed label: 'named slot'.
            imageIndexed basicAt: 1 put: imageIndexed.
            imageIndexed basicAt: 2 put: (Array with: 73).
            imageOctets := ImageOctets basicNew: 2.
            imageOctets basicAt: 2 put: 255!
            """)
        try #require(setup.error == nil, "\(setup.error ?? "")")
        return session
    }
}
