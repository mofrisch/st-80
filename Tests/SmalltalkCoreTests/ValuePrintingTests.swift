import Testing
@testable import SmalltalkCore

struct ValuePrintingTests {
    private func graph(_ value: Value, levels: Int, width: Int, in runtime: SmalltalkRuntime) throws -> Value {
        var value = value
        for _ in 0..<levels { value = try runtime.array(Array(repeating: value, count: width)) }
        return value
    }

    @Test func ordinaryValuesKeepTheirExistingRepresentation() throws {
        let runtime = SmalltalkRuntime(bootstrap: false)
        #expect(runtime.printValue(.integer(.min)) == "-9223372036854775808")
        #expect(runtime.printValue(.string("it's Café 👩🏽‍💻")) == "'it''s Café 👩🏽‍💻'")
        #expect(runtime.printValue(.symbol("answer:")) == "#answer:")
        #expect(runtime.printValue(.boolean(true)) == "true")
        #expect(runtime.printValue(.nilValue) == "nil")
        #expect(runtime.printValue(.transcript) == "Transcript")
        let nested = try runtime.array([.integer(1), runtime.array([.string("two"), .boolean(false)])])
        #expect(runtime.printValue(nested) == "#(1 #('two' false))")

        let owner = STClass("PrintingOwner", superclass: runtime.classes["Object"], fields: ["payload"])
        let object = try runtime.object(owner)
        object.fields["payload"] = .integer(42)
        #expect(runtime.printValue(.object(object)) == "a PrintingOwner (payload: 42)")
    }

    @Test func collectionPrefixesAndTheDepthLimitRemainCompatible() throws {
        let runtime = SmalltalkRuntime(bootstrap: false)
        let array = try runtime.array((0..<33).map { .integer(Int64($0)) })
        let prefix = (0..<32).map(String.init).joined(separator: " ")
        #expect(runtime.printValue(array) == "#(\(prefix) …)")
        let deep = try graph(.integer(1), levels: 5, width: 1, in: runtime)
        #expect(runtime.printValue(deep) == "#(#(#(#(#(…)))))")

        let fields = (0..<9).map { "field\($0)" }
        let owner = STClass("ManyFields", superclass: runtime.classes["Object"], fields: fields)
        let object = try runtime.object(owner)
        let shown = fields.prefix(8).map { "\($0): nil" }.joined(separator: ", ")
        #expect(runtime.printValue(.object(object)) == "a ManyFields (\(shown))")
    }

    @Test func sharedBranchesAndSharedStringLeavesHaveOneOutputBudget() throws {
        let runtime = SmalltalkRuntime(bootstrap: false)
        // Five reachable arrays used to expand into 137 MB of preview text.
        let repeated = try graph(.integer(1), levels: 5, width: 32, in: runtime)
        let printed = runtime.printValue(repeated)
        #expect(printed.utf8.count <= ValuePrinter.maximumBytes)
        #expect(printed.hasSuffix("…"))

        let leaf = Value.string(String(repeating: "quote'👩🏽‍💻", count: 40))
        let sharedStrings = try graph(leaf, levels: 3, width: 16, in: runtime)
        let strings = runtime.printValue(sharedStrings)
        #expect(strings.utf8.count <= ValuePrinter.maximumBytes)
        #expect(strings.hasSuffix("…"))
    }

    @Test func largeStringsAreEscapedAndTruncatedWithoutBreakingUnicode() {
        let runtime = SmalltalkRuntime(bootstrap: false)
        let text = String(repeating: "é'🦊", count: 50_000)
        let printed = runtime.printValue(.string(text))
        #expect(printed.hasPrefix("'é''🦊"))
        #expect(printed.hasSuffix("…"))
        #expect(printed.utf8.count <= ValuePrinter.maximumBytes)
        #expect(String(decoding: printed.utf8, as: UTF8.self) == printed)

        // A single grapheme can itself exceed the budget. Scalar iteration
        // must stay bounded and discard that unfinished grapheme on truncation.
        let enormousCharacter = "e" + String(repeating: "\u{301}", count: 100_000)
        var accents = ValuePrinter(maximumBytes: 64)
        #expect(accents.print(.string(enormousCharacter)) == "'…")
        var emoji = ValuePrinter(maximumBytes: 12)
        #expect(emoji.print(.string("👩🏽‍💻👩🏽‍💻")) == "'…")
    }

    @Test func traversalWorkIsBoundedSeparatelyFromTextSizeAndHandlesCycles() throws {
        let runtime = SmalltalkRuntime(bootstrap: false)
        let repeated = try graph(.integer(1), levels: 4, width: 2, in: runtime)
        var printer = ValuePrinter(maximumValues: 8)
        let preview = printer.print(repeated)
        #expect(printer.remainingValues == 0)
        #expect(preview.hasSuffix("…"))
        #expect(preview.utf8.count < 128)

        let cycle = try runtime.array([.nilValue])
        guard case .array(let array) = cycle else { Issue.record("Expected an array."); return }
        array.elements[0] = cycle
        #expect(runtime.printValue(cycle) == "#(#(#(#(#(…)))))")
    }

    @Test func bindingAliasesShareOneSnapshotBudgetWithoutHidingLaterScalarValues() throws {
        let runtime = SmalltalkRuntime(bootstrap: false)
        let shared = try graph(.integer(1), levels: 5, width: 32, in: runtime)
        for index in 0..<1_000 { runtime.globals["binding\(index)"] = shared }
        runtime.globals["zzanswer"] = .integer(42)

        let bindings = runtime.bindingInfos()
        #expect(bindings.count == 1_001)
        #expect(bindings.map(\.name) == bindings.map(\.name).sorted())
        #expect(bindings.reduce(0) { $0 + $1.value.utf8.count } <= ValuePrinter.allBindingsBytes)
        #expect(bindings.allSatisfy { !$0.value.isEmpty && $0.value.utf8.count <= ValuePrinter.bindingBytes })
        #expect(bindings.last?.name == "zzanswer")
        #expect(bindings.last?.value == "42")
    }

    @Test func smalltalkEvaluationAndSubsequentSnapshotsKeepSharedPreviewsSmall() async throws {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            printed := 1.
            4 timesRepeat: [ printed := (Array new: 32) collect: [ :unused | printed ] ].
            nil
            """)
        #expect(result.error == nil)
        #expect(result.value == "nil")
        let binding = try #require(result.bindings.first { $0.name == "printed" })
        #expect(binding.value.utf8.count <= ValuePrinter.bindingBytes)
        #expect(binding.value.hasSuffix("…"))
        let subsequent = await session.evaluate("6 * 7")
        #expect(subsequent.error == nil)
        #expect(subsequent.value == "42")
        #expect(subsequent.bindings.reduce(0) { $0 + $1.value.utf8.count } <= ValuePrinter.allBindingsBytes)
    }
}
