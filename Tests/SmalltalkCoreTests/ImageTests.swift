import Foundation
import Testing
@testable import SmalltalkCore

struct ImageTests {
    @Test func unevaluatedBlockCodeRetainsItsRuntimeErrorsAfterRestore() async throws {
        let original = SmalltalkSession()
        let literal = Array(repeating: "1", count: 4_097).joined(separator: " ")
        let compiled = await original.evaluate("deferred := [ #(\(literal)) ]")
        #expect(compiled.error == nil)
        let restored = SmalltalkSession()
        _ = try await restored.loadImage(original.imageData())
        let invoked = await restored.evaluate("deferred value")
        #expect(invoked.error?.contains("4,096") == true)
    }

    private func value(_ source: String, in session: SmalltalkSession) async -> String? {
        let result = await session.evaluate(source)
        #expect(result.error == nil, "\(result.error ?? "")")
        return result.value
    }

    @Test func roundTripPreservesClassesMethodsObjectsAndEditorState() async throws {
        let original = SmalltalkSession()
        let workspace = "\"Ein gespeicherter Workspace 👋\"\nsaved value"
        let transcript = "Greetings from the old session.\n"
        _ = await value("""
        Counter compile: 'value ^ count + 100'.
        Object compile: 'imageMarker ^ 42'.
        Counter subclass: #SpecialCounter instanceVariableNames: 'label'.
        SpecialCounter compile: 'label: aString label := aString'.
        SpecialCounter compile: 'label ^ label'.
        initializations := 0.
        SpecialCounter compile: 'initialize
            initializations := initializations + 1.
            super initialize'.
        saved := SpecialCounter new.
        saved add: 7.
        saved label: 'Cafés 👋'.
        classReference := SpecialCounter
        """, in: original)

        let data = try await original.imageData(workspace: workspace, transcript: transcript)
        _ = await value("saved add: 100", in: original)
        let restarted = SmalltalkSession()
        let loaded = try await restarted.loadImage(data)
        #expect(loaded.workspace == workspace)
        #expect(loaded.transcript == transcript)
        #expect(loaded.evaluation.classes.contains { $0.name == "SpecialCounter" && $0.superclass == "Counter" && $0.fields == ["count", "label"] })
        #expect(await value("saved value", in: restarted) == "107")
        #expect(await value("saved label", in: restarted) == "'Cafés 👋'")
        #expect(await value("saved imageMarker", in: restarted) == "42")
        #expect(await value("saved class == classReference", in: restarted) == "true")
        // Restoring fields must not run initialize or any other Smalltalk code.
        #expect(await value("initializations", in: restarted) == "1")
        #expect(await value("saved class superclass name", in: restarted) == "#Counter")
    }

    @Test func roundTripRetainsAliasingAndCyclesAcrossObjectsAndArrays() async throws {
        let original = SmalltalkSession()
        _ = await value("""
        Object subclass: #Node instanceVariableNames: 'next payload'.
        Node compile: 'next: aNode next := aNode'.
        Node compile: 'next ^ next'.
        Node compile: 'payload: aValue payload := aValue'.
        Node compile: 'payload ^ payload'.
        left := Node new.
        right := Node new.
        left next: right.
        right next: left.
        shared := Array new: 3.
        shared at: 1 put: left.
        shared at: 2 put: left.
        shared at: 3 put: shared.
        alias := shared
        """, in: original)
        let data = try await original.imageData()
        let restarted = SmalltalkSession()
        _ = try await restarted.loadImage(data)
        #expect(await value("alias == shared", in: restarted) == "true")
        #expect(await value("(shared at: 1) == (shared at: 2)", in: restarted) == "true")
        #expect(await value("(shared at: 3) == shared", in: restarted) == "true")
        #expect(await value("left next next == left", in: restarted) == "true")
        #expect(await value("(shared at: 1) payload: 99. (shared at: 2) payload", in: restarted) == "99")
        // A second generation exercises references created by the loader itself.
        let secondGeneration = try await restarted.imageData()
        let third = SmalltalkSession()
        _ = try await third.loadImage(secondGeneration)
        #expect(await value("left next next == left", in: third) == "true")
        #expect(await value("(alias at: 2) payload", in: third) == "99")
    }

    @Test func closuresRetainSharedLexicalBindingsParentsReceiversAndCycles() async throws {
        let original = SmalltalkSession()
        _ = await value("""
        | state cyclic |
        state := 0.
        increment := [ state := state + 1 ].
        read := [ state ].
        makeAdder := [ :base | [ :delta | base := base + delta ] ].
        adder := makeAdder value: 10.
        cyclic := [ cyclic ].
        cycle := cyclic.
        Counter compile: 'reader ^ [ count ]'.
        counter := Counter new.
        counter add: 8.
        counterReader := counter reader
        """, in: original)
        let data = try await original.imageData()
        let restarted = SmalltalkSession()
        _ = try await restarted.loadImage(data)
        #expect(await value("increment value. increment value. read value", in: restarted) == "2")
        #expect(await value("adder value: 5", in: restarted) == "15")
        #expect(await value("adder value: 2", in: restarted) == "17")
        #expect(await value("cycle value == cycle", in: restarted) == "true")
        #expect(await value("counter increment. counterReader value", in: restarted) == "9")
    }

    @Test func restoredBlocksKeepLexicalSuperAndCannotReviveReturnContexts() async throws {
        let original = SmalltalkSession()
        _ = await value("""
        Counter subclass: #ChildCounter instanceVariableNames: ''.
        ChildCounter compile: 'reader ^ [ super value ]'.
        counter := ChildCounter new.
        counter add: 6.
        reader := counter reader.
        escaped := [ ^ 77 ]
        """, in: original)
        let data = try await original.imageData()
        let restarted = SmalltalkSession()
        _ = try await restarted.loadImage(data)
        // Try the return immediately: restored home IDs must not collide with a
        // newly started workspace activation and accidentally become active.
        let invalidReturn = await restarted.evaluate("escaped value")
        #expect(invalidReturn.error?.contains("home context") == true)
        #expect(await value("reader value", in: restarted) == "6")
        #expect(await value("6 * 7", in: restarted) == "42")
    }

    @Test func immediateValuesAndClassReferencesRoundTrip() async throws {
        let original = SmalltalkSession()
        _ = await value("""
        minimum := -9223372036854775808.
        maximum := 9223372036854775807.
        text := 'Cafés 👋 it''s alive'.
        symbol := #'at:put:'.
        yes := true.
        no := false.
        nothing := nil.
        classReference := Counter.
        output := Transcript
        """, in: original)
        let restarted = SmalltalkSession()
        _ = try await restarted.loadImage(original.imageData())
        #expect(await value("minimum", in: restarted) == "-9223372036854775808")
        #expect(await value("maximum", in: restarted) == "9223372036854775807")
        #expect(await value("text", in: restarted) == "'Cafés 👋 it''s alive'")
        #expect(await value("symbol asString", in: restarted) == "'at:put:'")
        #expect(await value("yes and: [ no not ]", in: restarted) == "true")
        #expect(await value("nothing isNil", in: restarted) == "true")
        #expect(await value("classReference == Counter", in: restarted) == "true")
        #expect(await value("output == Transcript", in: restarted) == "true")
    }

    @Test func invalidImagesLeaveTheCurrentSessionUntouched() async throws {
        let current = SmalltalkSession()
        _ = await value("kept := Counter new. kept add: 42", in: current)
        let donor = SmalltalkSession()
        _ = await value("Counter compile: 'imageMethod ^ 123'. alias := Counter new", in: donor)
        let data = try await donor.imageData()
        let decoded = try JSONSerialization.jsonObject(with: data)
        let archive = try #require(decoded as? [String: Any])
        var unsupportedVersion = archive
        unsupportedVersion["version"] = 99
        var wrongFormat = archive
        wrongFormat["format"] = "another-image-format"
        var danglingReference = archive
        var globals = try #require(danglingReference["globals"] as? [String: Any])
        globals["alias"] = ["reference": ["_0": 999_999]]
        danglingReference["globals"] = globals
        let invalidMethod = replacing("imageMethod ^ 123", with: "imageMethod ^ (", in: archive)
        let invalidData = try [unsupportedVersion, wrongFormat, danglingReference, invalidMethod].map {
            try JSONSerialization.data(withJSONObject: $0)
        } + [Data("not an image".utf8)]
        for candidate in invalidData {
            do {
                _ = try await current.loadImage(candidate)
                Issue.record("Loading an invalid image unexpectedly succeeded.")
            } catch { /* The existing runtime is the transaction boundary. */ }
            #expect(await value("kept value", in: current) == "42")
            let missing = await current.evaluate("alias")
            #expect(missing.error != nil)
        }
    }

    @Test func invalidBytecodeInMethodsAndBlocksRejectsTheImageBeforeReplacement() async throws {
        let current = SmalltalkSession()
        #expect(await value("kept := 42", in: current) == "42")
        let donor = SmalltalkSession()
        #expect(await value("Counter compile: 'imageMethod ^ 123'. escaped := [ 7 ]. 123", in: donor) == "123")
        let data = try await donor.imageData()
        let archive = try JSONDecoder().decode(ImageArchive.self, from: data)
        let position = SourcePosition(line: 1, column: 1)
        let invalid = BytecodeBody(temporaries: [], instructions: [
            BytecodeInstruction(operation: .pop, position: position),
            BytecodeInstruction(operation: .finish, position: position),
        ])

        var badMethod = archive
        let method = Method(selector: "imageMethod", parameters: [], body: invalid, source: "imageMethod ^ 123")
        badMethod.executableMethods?["Counter"]?["imageMethod"] = MethodCode(method)

        var badBlock = archive
        guard case .reference(let blockID)? = archive.globals["escaped"], archive.nodes.indices.contains(blockID),
              case .block(var block) = archive.nodes[blockID] else {
            Issue.record("The saved closure is missing from the image.")
            return
        }
        block.body = invalid
        badBlock.nodes[blockID] = .block(block)

        for candidate in [badMethod, badBlock] {
            let bytes = try JSONEncoder().encode(candidate)
            await #expect(throws: SmalltalkError.self) {
                _ = try await current.loadImage(bytes)
            }
            #expect(await value("kept", in: current) == "42")
        }
    }

    @Test func fileRoundTripAndFailedWritePreserveSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("st80-image-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Saved.stimage")
        let original = SmalltalkSession()
        _ = await value("saved := Counter new. saved add: 12", in: original)
        try await original.saveImage(to: url, workspace: "saved value", transcript: "Saved.\n")
        let firstBytes = try Data(contentsOf: url)
        let restarted = SmalltalkSession()
        let loaded = try await restarted.loadImage(from: url)
        #expect(loaded.workspace == "saved value")
        #expect(loaded.transcript == "Saved.\n")
        #expect(await value("saved value", in: restarted) == "12")
        do {
            try await original.saveImage(to: directory.appendingPathComponent("missing/Failed.stimage"), workspace: "", transcript: "")
            Issue.record("Saving into a nonexistent directory unexpectedly succeeded.")
        } catch { }
        do {
            try await original.saveImage(to: url, workspace: String(repeating: "x", count: ImageCodec.maxBytes + 1), transcript: "")
            Issue.record("Saving an oversized image unexpectedly succeeded.")
        } catch { }
        // A failed export to the SAME destination must leave its old bytes intact.
        #expect(try Data(contentsOf: url) == firstBytes)
        #expect(await value("saved value", in: original) == "12")
    }

    @Test func invalidLexicalParentsAndClassLayoutsRejectTransactionally() async throws {
        let current = SmalltalkSession()
        _ = await value("kept := Counter new. kept add: 42", in: current)
        let donor = SmalltalkSession()
        _ = await value("""
        | recursive |
        recursive := [ recursive ].
        callable := recursive.
        Object subclass: #GraphNode instanceVariableNames: 'next'.
        GraphNode compile: 'next: aNode next := aNode'.
        node := GraphNode new.
        node next: node
        """, in: donor)
        let data = try await donor.imageData()
        let archive = try JSONDecoder().decode(ImageArchive.self, from: data)
        let environmentID = try #require(archive.nodes.firstIndex {
            if case .environment = $0 { return true }
            return false
        })
        var parentCycle = archive
        if case .environment(var environment) = parentCycle.nodes[environmentID] {
            environment.parent = environmentID
            parentCycle.nodes[environmentID] = .environment(environment)
        }
        var badLayout = archive
        let objectClass = try #require(badLayout.classes.firstIndex { $0.name == "Object" })
        badLayout.classes[objectClass].fields = ["unsupported"]
        // This fails only after shells and their cyclic values have been wired.
        var missingClassBinding = archive
        missingClassBinding.globals.removeValue(forKey: "Counter")
        for candidate in [parentCycle, badLayout, missingClassBinding] {
            do {
                _ = try await current.loadImage(JSONEncoder().encode(candidate))
                Issue.record("Loading a structurally invalid graph unexpectedly succeeded.")
            } catch { }
            #expect(await value("kept value", in: current) == "42")
            let donorBinding = await current.evaluate("callable")
            #expect(donorBinding.error != nil)
        }
    }

    private func replacing(_ old: String, with new: String, in value: Any) -> Any {
        if let string = value as? String { return string == old ? new : string }
        if let dictionary = value as? [String: Any] { return dictionary.mapValues { replacing(old, with: new, in: $0) } }
        if let array = value as? [Any] { return array.map { replacing(old, with: new, in: $0) } }
        return value
    }
}
