import Foundation
import Testing
@testable import SmalltalkCore

struct CompilerTests {
    @Test func unicodeNamesKeepDistinctLocalAndArgumentBindings() async {
        let session = SmalltalkSession()
        let composed = "\u{00E9}"
        let decomposed = "e\u{0301}"
        let sameScope = await session.evaluate("""
            | \(composed) \(decomposed) |
            \(composed) := 11. \(decomposed) := 22.
            Array with: \(composed) with: \(decomposed)
            """)
        #expect(sameScope.error == nil)
        #expect(sameScope.value == "#(11 22)")
        let nested = await session.evaluate("""
            [ :\(composed) | [ :\(decomposed) | Array with: \(composed) with: \(decomposed) ] value: 22 ] value: 11
            """)
        #expect(nested.value == "#(11 22)")
        let parameterAndTemporary = await session.evaluate("""
            [ :\(composed) | | \(decomposed) | \(decomposed) := 22. Array with: \(composed) with: \(decomposed) ] value: 11
            """)
        #expect(parameterAndTemporary.error == nil, "\(parameterAndTemporary.error ?? "")")
        #expect(parameterAndTemporary.value == "#(11 22)")
        #expect(await session.evaluate("| \(composed) \(composed) | 0").error != nil)
    }

    @Test func cascadeBranchesEvaluateMessageChainsAndResetTheReceiver() async throws {
        let session = SmalltalkSession()
        let method = """
            cascadeValues
                | stream |
                stream := ReadStream on: #(3 4).
                ^ Array with: (stream peek; next squared + 2 min: 10)
                    with: (stream peek; next squared; atEnd)
            """
        try #require(await session.compile(method, in: "Counter").error == nil)
        #expect(await session.evaluate("Counter new cascadeValues").value == "#(10 true)")

        let restored = SmalltalkSession()
        _ = try await restored.loadImage(session.imageData())
        #expect(await restored.evaluate("Counter new cascadeValues").value == "#(10 true)")
        #expect(await restored.evaluate("| stream | stream := ReadStream on: #(3). stream peek; next squared").value == "9")
    }

    @Test func unicodeSelectorsKeepTheirDistinctMethodsInBothImageFormats() async throws {
        let session = SmalltalkSession()
        let composed = "\u{00E9}"
        let decomposed = "e\u{0301}"
        let imported = await session.evaluate("""
            Smalltalk interchangeVersion: '1.0'!
            Class named: 'UnicodeSelectorProbe' superclass: 'Object' indexedInstanceVariables: #'none'
                instanceVariableNames: '' classVariableNames: '' sharedPools: '' classInstanceVariableNames: ''!
            UnicodeSelectorProbe method! \(composed) ^ 11!
            UnicodeSelectorProbe method! \(decomposed) ^ 22!
            UnicodeSelectorProbe classMethod! \(composed) ^ 33!
            UnicodeSelectorProbe classMethod! \(decomposed) ^ 44!
            """)
        try #require(imported.error == nil)
        let source = """
            | probe |
            probe := UnicodeSelectorProbe new.
            Array with: probe \(composed) with: (probe perform: #\(decomposed))
                with: UnicodeSelectorProbe \(composed) with: (UnicodeSelectorProbe perform: #\(decomposed))
            """
        #expect(await session.evaluate(source).value == "#(11 22 33 44)")

        let portable = SmalltalkSession()
        let image = try await session.imageData()
        _ = try await portable.loadImage(image)
        #expect(await portable.evaluate(source).value == "#(11 22 33 44)")

        // A legacy portable image could preserve the old dictionary key after
        // a method with a canonically equivalent spelling overwrote the value.
        var legacy = try JSONDecoder().decode(ImageArchive.self, from: image)
        let record = try #require(legacy.classes.firstIndex { $0.name == "UnicodeSelectorProbe" })
        let oldSource = legacy.classes[record].methods.removeValue(forKey: decomposed)
        let oldCode = legacy.executableMethods?["UnicodeSelectorProbe"]?.removeValue(forKey: decomposed)
        legacy.classes[record].methods[composed] = try #require(oldSource)
        legacy.executableMethods?["UnicodeSelectorProbe"]?[composed] = try #require(oldCode)
        let fromLegacy = SmalltalkSession()
        _ = try await fromLegacy.loadImage(JSONEncoder().encode(legacy))
        #expect(await fromLegacy.evaluate("UnicodeSelectorProbe new \(decomposed)").value == "22")
        #expect(await fromLegacy.evaluate("UnicodeSelectorProbe new respondsTo: #\(composed)").value == "false")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Unicode.stimage")
        try await session.saveImage(to: url, workspace: "", transcript: "")
        let native = SmalltalkSession()
        _ = try await native.loadImage(from: url)
        #expect(await native.evaluate(source).value == "#(11 22 33 44)")
    }

    @Test func floatLiteralRangeIsCheckedBeforeRounding() async {
        let session = SmalltalkSession()
        for source in ["1.7976931348623158e308", "-1.7976931348623158d308", "1.7976931348623158q308"] {
            #expect(await session.evaluate(source).error?.contains("supported range") == true)
        }
        #expect(await session.evaluate("1.7976931348623157e308 = Float fmax").value == "true")
        let maximum = await session.evaluate("Float fmax asFraction")
        if let digits = maximum.value {
            #expect(await session.evaluate(digits + ".0 = Float fmax").value == "true")
        } else {
            Issue.record("The exact integer value of Float fmax is unavailable.")
        }
    }

    @Test func quotedCarriageReturnCanBeFollowedByLineFeed() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("$\r\n codePoint")
        #expect(result.error == nil)
        #expect(result.value == "13")
    }

    @Test func ansiLiteralAndStatementRules() async {
        let session = SmalltalkSession()
        #expect(await session.evaluate("#(nil true false #nil #true)").value == "#(nil true false #nil #true)")
        #expect(await session.evaluate("#($A $é)").value == "#($A $é)")
        #expect(await session.evaluate("$A asLowercase codePoint").value == "97")
        #expect(await session.evaluate("('é' at: 1) class == Character").value == "true")
        #expect(await session.evaluate("(Character codePoint: 65) == $A").value == "true")
        #expect(await session.evaluate("'e\u{301}' size").value == "2")
        #expect(await session.evaluate("16rFF + 2r101").value == "260")
        #expect(await session.evaluate("-16r8000000000000000").value == "-9223372036854775808")
        #expect(await session.evaluate("2r2").error?.contains("Invalid digits") == true)
        #expect(await session.evaluate("1. 25").value == "25")
        #expect(await session.evaluate("1.25").value == "1.25")
        #expect(await session.evaluate("1.25d2 + 2").value == "127.0")
        #expect(await session.evaluate("2 * -1.25q2").value == "-250.0")
        #expect(await session.evaluate("1.0e309").error?.contains("supported range") == true)
        #expect(await session.evaluate("FloatE precision + FloatD precision + FloatQ precision").value == "159")
        #expect(await session.evaluate("12s").value == "12s0")
        #expect(await session.evaluate("1.2s0").error?.contains("scaled decimal literal") == true)
        #expect(await session.evaluate("1s1025").error?.contains("scaled decimal literal") == true)
        #expect(await session.evaluate("1s / 0s").error?.contains("Division by zero") == true)
        #expect(await session.compile("badReturn ^ 42. 7", in: "Counter").error?.contains("last statement") == true)
        #expect(await session.compile("nestedReturn ^ (^ 42)", in: "Counter").error != nil)
        #expect(await session.evaluate("true | false").value == "true")
        #expect(await session.evaluate("#| == #'|'").value == "true")
        #expect(await session.evaluate("|| 42").value == "42")
        #expect(await session.evaluate("[ :arg || temp | temp := arg + 1. temp ] value: 41").value == "42")
        #expect(await session.compile("|| arg ^ arg + 1", in: "Counter").error == nil)
        #expect(await session.evaluate("Counter new || 41").value == "42")
    }

    @Test func ansiCharacterAndFloatValuesAndLiteralsSurviveImageLoad() async throws {
        let session = SmalltalkSession()
        #expect(await session.evaluate("marker := $é. reading := 1.25e2").error == nil)
        #expect(await session.compile("measure ^ #($é 1.25e2)", in: "Counter").error == nil)
        let restored = SmalltalkSession()
        _ = try await restored.loadImage(session.imageData())
        #expect(await restored.evaluate("marker codePoint").value == "233")
        #expect(await restored.evaluate("reading + 2").value == "127.0")
        #expect(await restored.evaluate("Counter new measure").value == "#($é 125.0)")
    }

    @Test func largeIntegersAndFractionsSurviveAnImageRoundTrip() async throws {
        let session = SmalltalkSession()
        #expect(await session.compile("largeValue ^ 1000000000000000000000001", in: "Counter").error == nil)
        #expect(await session.evaluate("large := Counter new largeValue. ratio := large / 3").error == nil)
        let image = try await session.imageData()
        let restored = SmalltalkSession()
        _ = try await restored.loadImage(image)
        #expect(await restored.evaluate("large = Counter new largeValue").value == "true")
        #expect(await restored.evaluate("ratio denominator").value == "3")
        #expect(await restored.evaluate("ratio * 3").value == "1000000000000000000000001")
    }

    @Test func scaledDecimalValuesAndBytecodeRetainTheirScaleAfterImageLoad() async throws {
        let session = SmalltalkSession()
        #expect(await session.compile("price ^ #(-12.30s 7s4)", in: "Counter").error == nil)
        #expect(await session.evaluate("storedPrice := 12345678901234567890.500s. getPrice := [ 3.1400s ]").error == nil)
        let restored = SmalltalkSession()
        _ = try await restored.loadImage(session.imageData())
        #expect(await restored.evaluate("Counter new price").value == "#(-12.30s2 7.0000s4)")
        #expect(await restored.evaluate("storedPrice").value == "12345678901234567890.500s3")
        #expect(await restored.evaluate("getPrice value").value == "3.1400s4")
    }

    @Test func ansiArgumentsAreConstantAndLocalsCanShadow() async {
        let session = SmalltalkSession()
        #expect(await session.evaluate("| Counter | Counter := 42. Counter").value == "42")
        #expect(await session.compile("shadow | count | count := 42. ^ count", in: "Counter").error == nil)
        #expect(await session.evaluate("Counter new shadow").value == "42")
        #expect(await session.compile("assign: Arg ^ [ Arg := 1 ] value", in: "Counter").error?.contains("Argument Arg") == true)
        #expect(await session.evaluate("[ :arg | arg := 42 ] value: 0").error?.contains("Argument arg") == true)
        #expect(await session.evaluate("[ :arg | [ | arg | arg := 42 ] value ] value: 0").value == "42")
    }

    @Test func thisContextIsAnOrdinaryIdentifier() async throws {
        let session = SmalltalkSession()
        let imported = await session.evaluate("""
            Smalltalk interchangeVersion: '1.0'!
            Global constant: 'thisContext'!
            thisContext initializer! 7!
            """)
        try #require(imported.error == nil, "\(imported.error ?? "")")
        #expect(await session.evaluate("| thisContext | thisContext := 42. thisContext").value == "42")
        #expect(await session.evaluate("[ :thisContext | thisContext + 1 ] value: 41").value == "42")
        #expect(await session.compile("echo: thisContext ^ thisContext", in: "Counter").error == nil)
        #expect(await session.evaluate("Counter new echo: 42").value == "42")
        #expect(await session.evaluate("thisContext").value == "7")
        #expect(await session.evaluate("| self | self").error != nil)

        let restored = SmalltalkSession()
        _ = try await restored.loadImage(session.imageData())
        #expect(await restored.evaluate("Array with: thisContext with: (Counter new echo: 42)").value == "#(7 42)")
    }

    @Test func stockCompilerInASavedImageCanDeclareThisContextAfterUpgrade() async throws {
        let session = SmalltalkSession()
        let oldMethod = """
            validateNames: names
                names do: [ :name |
                    (#('self' 'super' 'true' 'false' 'nil' 'thisContext') includes: name) ifTrue: [
                        self fail: 'A pseudo-variable cannot be declared.' ] ].
                1 to: names size do: [ :index |
                    1 to: index - 1 do: [ :earlier |
                        (names at: index) = (names at: earlier) ifTrue: [
                            self fail: 'Duplicate variable declaration.' ] ] ]
            """
        try #require(await session.compile(oldMethod, in: "STCompiler").error == nil)
        #expect(await session.evaluate("| thisContext | thisContext := 42. thisContext").error != nil)

        let restored = SmalltalkSession()
        _ = try await restored.loadImage(session.imageData())
        #expect(await restored.evaluate("| thisContext | thisContext := 42. thisContext").value == "42")
    }

    @Test func aLiveScannerEditChangesWorkspaceAndMethodCompilationAndSurvivesReload() async throws {
        let session = SmalltalkSession()
        let scanner = """
        source: input
            | source |
            source := input.
            source = '6 * 7' ifTrue: [ source := '73' ].
            source = 'answer ^ 1' ifTrue: [ source := 'answer ^ 99' ].
            characters := source characters
        """
        let changed = await session.compile(scanner, in: "STScanner")
        #expect(changed.executionError == nil)
        #expect(await session.evaluate("6 * 7").value == "73")
        #expect(await session.compile("answer ^ 1", in: "Counter").executionError == nil)
        #expect(await session.evaluate("Counter new answer").value == "99")

        let restored = SmalltalkSession()
        _ = try await restored.loadImage(session.imageData())
        #expect(await restored.evaluate("6 * 7").value == "73")
        #expect(await restored.evaluate("Counter new answer").value == "99")
        #expect(await restored.evaluate("Counter compile: 'answer ^ 1'. Counter new answer").value == "99")
    }

    @Test func sourceHighlightingRecoversFromPartialInputAndReturnsUTF16Ranges() async {
        let session = SmalltalkSession()
        let comment = "\"💡\r\ncomment\""
        let symbol = "#'e\u{301}'"
        let unfinished = "'unterminated 💡"
        let source = "\(comment) café := \(symbol). 💥 # 9223372036854775809 1.20s3 ^ self \(unfinished)"
        let highlights = await session.sourceHighlights(source)
        let nativeText = source as NSString

        #expect(highlights.map(\.kind) == [.comment, .language, .literal, .language, .language, .language, .language, .literal])
        #expect(highlights.map { nativeText.substring(with: NSRange($0.range)) }
                == [comment, ":=", symbol, "9223372036854775809", "1.20s3", "^", "self", unfinished])

        let openComment = "\"open comment 💡"
        let commentHighlights = await session.sourceHighlights(openComment)
        #expect(commentHighlights == [SourceHighlight(kind: .comment, range: 0..<openComment.utf16.count)])
        #expect(await session.evaluate(openComment).executionError?.contains("Unterminated comment") == true)
        #expect(await session.evaluate(unfinished).executionError?.contains("Unterminated string") == true)
    }

    @Test func sourceHighlightingFollowsTheLiveImageScanner() async {
        let session = SmalltalkSession()
        let initial = await session.sourceHighlights("42")
        #expect(initial.map(\.kind) == [.language])
        let change = await session.compile("token: kind value: value ^ self highlight: #comment", in: "STSourceScanner")
        #expect(change.executionError == nil)
        let updated = await session.sourceHighlights("42")
        #expect(updated.map(\.kind) == [.comment])
        #expect(await session.evaluate("6 * 7").value == "42")
    }

    @Test func malformedCompilerOutputCannotReplaceAnInstalledMethod() async {
        let session = SmalltalkSession()
        #expect(await session.compile("answer ^ 42", in: "Counter").executionError == nil)
        #expect(await session.compile("method: source ^ #(wrong)", in: "STCompiler").executionError == nil)
        let attempted = await session.compile("answer ^ 99", in: "Counter")
        #expect(attempted.executionError?.contains("syntax tree") == true)
        #expect(await session.evaluate("Counter new answer").value == "42")
    }

    @Test func mixedLineEndingsAndUnicodeKeepTheirPositionsAcrossAnImageRoundTrip() async throws {
        let session = SmalltalkSession()
        let comment = "\"Café 🛠\""
        let source = "lineProbe\r\n    \(comment)\r    ^ missingLineProbe\n"
        let compiled = await session.compile(source, in: "Counter")
        try #require(compiled.executionError == nil)
        let original = await session.evaluate("Counter new lineProbe")
        #expect(original.executionError == "Line 3, column 7: Unknown variable: missingLineProbe")

        let reopened = try await session.loadImage(session.imageData())
        let counter = try #require(reopened.evaluation.classes.first { $0.name == "Counter" })
        let method = try #require(counter.methods.first { $0.selector == "lineProbe" })
        #expect(method.source.utf8.elementsEqual(source.utf8))
        let highlights = await session.sourceHighlights(method.source)
        let nativeSource = method.source as NSString
        let substrings = highlights.map { nativeSource.substring(with: NSRange($0.range)) }
        #expect(substrings == [comment, "^"])
        let restored = await session.evaluate("Counter new lineProbe")
        #expect(restored.executionError == original.executionError)
    }

    @Test func imageLoadRejectsUnsupportedVersionsBeforeReplacingTheSession() async throws {
        let session = SmalltalkSession()
        _ = await session.evaluate("kept := 42")
        let supported = ImageCodec.supportedVersions
        for version in [supported.lowerBound - 1, supported.upperBound + 1] {
            let header = Data(#"{"format":"st80-image","version":\#(version)}"#.utf8)
            do {
                _ = try await session.loadImage(header)
                Issue.record("An unsupported image version unexpectedly loaded.")
            } catch {
                #expect(error.localizedDescription == "Image version \(version) is unsupported. Supported versions are \(supported.lowerBound) through \(supported.upperBound).")
            }
        }
        #expect(await session.evaluate("kept").value == "42")
    }
}
