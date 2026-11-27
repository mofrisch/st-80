import Foundation
import Testing
@testable import SmalltalkCore

struct ANSIExceptionAndFileTests {
    @Test func dateComparisonAndSubtractionAcceptAForwardingDate() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | date earlier same later results |
            Object subclass: #ANSIForwardingDate instanceVariableNames: 'subject'.
            ANSIForwardingDate compile: 'subject: aDate subject := aDate'.
            ANSIForwardingDate compile: 'doesNotUnderstand: failure
                ^ subject perform: failure selector withArguments: failure arguments'.
            ANSIForwardingDate compile: '= other ^ subject = other'.
            ANSIForwardingDate compile: 'hash ^ subject hash'.
            date := DateAndTime year: 2024 day: 61 hour: 6 minute: 30 second: (1 / 2)
                offset: (Duration seconds: 7200).
            earlier := date - (Duration seconds: 75).
            same := ANSIForwardingDate new subject: date; yourself.
            later := ANSIForwardingDate new subject: date + (Duration seconds: 5); yourself.
            results := Array with: (date = same) with: (same = date)
                with: (date < later) with: (date - later) asSeconds.
            ANSIForwardingDate compile: 'asUTC ^ self'.
            same subject: earlier asUTC.
            Array with: results with: (date - same) asSeconds with: (date > same)
                with: (date = 17)
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(#(true true true -5) 75 true false)")
    }

    @Test func replacementExceptionCanImplementTheDescriptionProtocolDirectly() async {
        let session = SmalltalkSession()
        let setup = await session.evaluate("""
            Object subclass: #AuditExceptionDescription instanceVariableNames: ''.
            AuditExceptionDescription compile: 'description ^ ''Replacement'' '.
            AuditExceptionDescription compile: 'defaultAction ^ 17'.
            AuditExceptionDescription compile: 'isResumable ^ true'.
            AuditExceptionDescription compile: 'messageText ^ ''Replacement'' '.
            AuditExceptionDescription compile: 'tag ^ 40'.
            Object subclass: #AuditReplacementSelector instanceVariableNames: ''.
            AuditReplacementSelector compile: 'handles: exception ^ exception class == AuditExceptionDescription'.
            """)
        #expect(setup.error == nil)
        let defaultResult = await session.evaluate("""
            [ 1 + Error signal ] on: Error do: [ :exception |
                exception resignalAs: AuditExceptionDescription new ]
            """)
        #expect(defaultResult.error == nil)
        #expect(defaultResult.value == "18")

        let handled = await session.evaluate("""
            [
                [
                    [ 1 + Error signal ] on: Error do: [ :exception |
                        exception resignalAs: AuditExceptionDescription new ]
                ] on: AuditReplacementSelector new do: [ :exception |
                    (exception isNested and: [ exception respondsTo: #resume: ])
                        ifFalse: [ self error: 'Missing exception control protocol' ].
                    exception resume: exception outer + 1 ]
            ] on: AuditReplacementSelector new do: [ :exception | exception resume: exception tag ]
            """)
        #expect(handled.error == nil)
        #expect(handled.value == "42")
    }

    @Test func anExceptionSelectorCanForwardTheHandlesMessage() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            Object subclass: #AuditForwardingErrorSelector instanceVariableNames: ''.
            AuditForwardingErrorSelector compile: 'doesNotUnderstand: message
                message selector == #handles: ifTrue: [ ^ Error handles: message arguments first ].
                ^ super doesNotUnderstand: message'.
            [ Error signal: 'Forwarded' ] on: AuditForwardingErrorSelector new do: [ :exception |
                exception messageText ]
            """)
        #expect(result.error == nil)
        #expect(result.value == "'Forwarded'")
    }

    @Test func passFromAnOuterHandlerUsesTheOriginalSignalingEnvironment() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | passed directOuter |
            Notification subclass: #AuditEnvironmentNotice instanceVariableNames: ''.
            Notification subclass: #AuditEnvironmentProbe instanceVariableNames: ''.
            AuditEnvironmentProbe compile: 'defaultAction ^ AuditEnvironmentNotice signal'.
            passed := [
                [
                    [ AuditEnvironmentProbe signal ] on: AuditEnvironmentNotice do: [ :notice | notice resume: 31 ]
                ] on: AuditEnvironmentProbe do: [ :exception | exception resume: exception outer ]
            ] on: AuditEnvironmentProbe do: [ :exception | exception pass ].
            directOuter := [
                [ AuditEnvironmentProbe signal ] on: AuditEnvironmentNotice do: [ :notice | notice resume: 31 ]
            ] on: AuditEnvironmentProbe do: [ :exception | exception resume: exception outer ].
            Array with: passed with: directOuter
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(31 nil)")
    }

    @Test(arguments: ["outer", "pass"])
    func nonresumableExceptionUsesTheOriginalSignalingEnvironment(selector: String) async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            Notification subclass: #AuditOuterNotice instanceVariableNames: ''.
            Error subclass: #AuditNonresumableError instanceVariableNames: ''.
            AuditNonresumableError compile: 'defaultAction
                ^ self error: (AuditOuterNotice signal isNil
                    ifTrue: [ ''notification not handled'' ]
                    ifFalse: [ ''notification handled in signaling environment'' ])'.
            [
                [ AuditNonresumableError signal ] on: AuditOuterNotice do: [ :notice | notice resume: 31 ]
            ] on: AuditNonresumableError do: [ :exception | exception \(selector) ]
            """)
        #expect(result.executionError?.contains("notification handled in signaling environment") == true)
    }

    @Test func structuralExceptionControlsTakePrecedenceWhileHandlingAReplacement() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | replacement answer |
            Object subclass: #AuditShadowingDescription instanceVariableNames: ''.
            AuditShadowingDescription compile: 'description ^ ''Replacement'' '.
            AuditShadowingDescription compile: 'defaultAction ^ 17'.
            AuditShadowingDescription compile: 'isResumable ^ true'.
            AuditShadowingDescription compile: 'messageText ^ nil'.
            AuditShadowingDescription compile: 'tag ^ nil'.
            AuditShadowingDescription compile: 'resume: ignored ^ #ordinaryMethod'.
            Object subclass: #AuditShadowingSelector instanceVariableNames: ''.
            AuditShadowingSelector compile: 'handles: exception ^ exception class == AuditShadowingDescription'.
            replacement := AuditShadowingDescription new.
            answer := [
                [ 1 + Error signal ] on: Error do: [ :exception | exception resignalAs: replacement ]
            ] on: AuditShadowingSelector new do: [ :exception |
                (exception == replacement and: [ exception respondsTo: #resume: ])
                    ifFalse: [ self error: 'Missing active exception identity or protocol' ].
                exception resume: 42 ].
            Array with: answer with: (replacement resume: 0)
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(43 #ordinaryMethod)")
    }

    @Test func durationsCompareAndCalculateWithForwardedDurationOperands() async throws {
        let session = try await sessionWithForwardedDuration()
        let result = await session.evaluate("""
            | duration half proxy zero comparisons arithmetic |
            duration := Duration seconds: (3 / 2).
            half := Duration seconds: (1 / 2).
            proxy := AuditForwardedDuration new seconds: (1 / 2); yourself.
            zero := AuditForwardedDuration new seconds: 0; yourself.
            comparisons := Array with: (half = proxy) with: (proxy = half)
                with: (duration > proxy) with: (half <= proxy).
            arithmetic := Array with: (duration + proxy) asSeconds with: (duration - proxy) asSeconds
                with: (duration / proxy) with: (duration / 2) asSeconds.
            Array with: comparisons with: arithmetic
                with: (proxy hash = half hash)
                with: ([ duration / zero ] on: ZeroDivide do: [ :exception | exception dividend ])
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(#(true true true true) #(2 1 3 3/4) true 3/2)")
    }

    @Test func dateArithmeticAndOffsetsAcceptForwardedDurations() async throws {
        let session = try await sessionWithForwardedDuration()
        let result = await session.evaluate("""
            | instant half offset adjusted constructed |
            instant := DateAndTime year: 2024 day: 2 hour: 0 minute: 1 second: (1 / 4).
            half := AuditForwardedDuration new seconds: (1 / 2); yourself.
            offset := AuditForwardedDuration new seconds: 2; yourself.
            adjusted := instant offset: offset.
            constructed := DateAndTime year: 2024 month: 1 day: 2 hour: 0 minute: 1 second: (9 / 4) offset: offset.
            Array with: (instant + half) second with: (instant - half) second
                with: (adjusted offset = offset) with: (constructed asUTC = instant)
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(3/4 239/4 true true)")
    }

    @Test func durationEqualityHandlesAbsentSecondsAndPassesUnrelatedExceptions() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | amount broken |
            Object subclass: #AuditInvalidDuration instanceVariableNames: ''.
            AuditInvalidDuration compile: 'asSeconds ^ ''wrong type'' '.
            Object subclass: #AuditBrokenDuration instanceVariableNames: ''.
            AuditBrokenDuration compile: 'asSeconds ^ self auditMissingConversion'.
            amount := Duration zero.
            broken := AuditBrokenDuration new.
            Array with: (amount = Object new) with: (amount = AuditInvalidDuration new)
                with: ([ amount = broken ] on: MessageNotUnderstood do: [ :exception | exception message selector ])
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(false false #auditMissingConversion)")
    }

    private func sessionWithForwardedDuration() async throws -> SmalltalkSession {
        let session = SmalltalkSession()
        let setup = await session.evaluate("""
            Object subclass: #AuditForwardedDuration instanceVariableNames: 'length'.
            AuditForwardedDuration compile: 'seconds: amount length := amount'.
            AuditForwardedDuration compile: 'doesNotUnderstand: message
                ^ (Duration seconds: length) perform: message selector withArguments: message arguments'.
            AuditForwardedDuration compile: '= other ^ (Duration seconds: length) = other'.
            AuditForwardedDuration compile: 'hash ^ (Duration seconds: length) hash'.
            AuditForwardedDuration compile: 'printString ^ (Duration seconds: length) printString'.
            """)
        try #require(setup.error == nil)
        return session
    }

    @Test func fileStreamsAcceptPathsImplementingReadableString() async throws {
        let directory = try newFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("readable-name.bin")
        let session = try await session(for: path)
        let result = await session.evaluate("""
            | name writer reader |
            Object subclass: #AuditReadablePath instanceVariableNames: 'text'.
            AuditReadablePath compile: 'text: aString text := aString'.
            AuditReadablePath compile: 'asString ^ text'.
            AuditReadablePath compile: 'doesNotUnderstand: message
                ^ text perform: message selector withArguments: message arguments'.
            name := AuditReadablePath new text: filePath; yourself.
            writer := FileStream write: name mode: #create check: true type: #binary.
            [ writer nextPut: 17 ] ensure: [ writer close ].
            reader := FileStream read: name type: #binary.
            [ reader next ] ensure: [ reader close ]
            """)
        #expect(result.error == nil)
        #expect(result.value == "17")
        #expect(try Data(contentsOf: path) == Data([17]))
    }

    @Test func writeOnlyBinaryFileSupportsAppendAndPositioning() async throws {
        let directory = try newFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("write-only.bin")
        try Data([1, 2, 3]).write(to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o200], ofItemAtPath: path.path)

        let session = try await session(for: path)
        let result = await session.evaluate("""
            | writer initialPosition |
            writer := FileStream write: filePath mode: #append check: true type: #binary.
            [
                initialPosition := writer position.
                writer position: 1; nextPut: 9; setToEnd; nextPut: 42.
                Array with: initialPosition with: writer position
            ] ensure: [ writer close ]
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(3 4)")
        let permissions = try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? Int
        #expect(permissions == 0o200)

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        #expect(try Data(contentsOf: path) == Data([1, 9, 3, 42]))
    }

    @Test func writeOnlyTruncatedTextFileSupportsUnicodeReplacement() async throws {
        let directory = try newFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("write-only.txt")
        try Data("old contents".utf8).write(to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o200], ofItemAtPath: path.path)

        let session = try await session(for: path)
        let result = await session.evaluate("""
            | writer |
            writer := FileStream write: filePath mode: #truncate check: true type: #text.
            [
                writer nextPutAll: 'a🐱é'.
                writer reset; nextPut: $猫; nextPut: $b.
                Array with: writer contents with: writer position
            ] ensure: [ writer close ]
            """)
        #expect(result.error == nil)
        #expect(result.value == "#('猫bé' 2)")

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        #expect(try Data(contentsOf: path) == Data("猫bé".utf8))
    }

    @Test func writeOnlyTextFileCanAppendWithoutReadingItsPrefix() async throws {
        let directory = try newFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("utf8-prefix.txt")
        try Data("é猫".utf8).write(to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o200], ofItemAtPath: path.path)

        let session = try await session(for: path)
        let result = await session.evaluate("""
            | writer |
            writer := FileStream write: filePath mode: #append check: true type: #text.
            [ writer nextPut: $🙂 ] ensure: [ writer close ]
            """)
        #expect(result.error == nil)

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        #expect(try Data(contentsOf: path) == Data("é猫🙂".utf8))
    }

    @Test func puttableStreamsWriteEachValueDuringEnumeration() async throws {
        let directory = try newFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("enumeration.bin")

        let session = try await session(for: path)
        let result = await session.evaluate("""
            | source file collection readWrite fileObservation collectionObservation |
            Object subclass: #AuditStreamElements instanceVariableNames: 'target afterFirst'.
            AuditStreamElements compile: 'target: stream target := stream'.
            AuditStreamElements compile: 'positionAfterFirst ^ afterFirst'.
            AuditStreamElements compile: 'do: operation
                operation value: 7.
                afterFirst := target position.
                operation value: 8'.
            AuditStreamElements compile: 'asArray
                | result index |
                result := Array new: 2.
                index := 1.
                self do: [ :each | result at: index put: each. index := index + 1 ].
                ^ result'.
            source := AuditStreamElements new.
            file := FileStream write: filePath mode: #create check: true type: #binary.
            [
                source target: file.
                file nextPutAll: source.
                fileObservation := source positionAfterFirst
            ] ensure: [ file close ].
            collection := WriteStream with: Array new.
            source target: collection.
            collection nextPutAll: source.
            collectionObservation := source positionAfterFirst.
            readWrite := ReadWriteStream on: Array new.
            source target: readWrite.
            readWrite nextPutAll: source.
            Array with: fileObservation with: (Array with: collectionObservation with: collection contents)
                with: source positionAfterFirst with: readWrite contents
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(1 #(1 #(7 8)) 1 #(7 8))")
        #expect(try Data(contentsOf: path) == Data([7, 8]))
    }

    @Test func puttableStreamSubclassesInheritNextPutAllAndDispatchNextPut() async throws {
        let directory = try newFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("inherited.bin")
        let session = try await session(for: path)
        let result = await session.evaluate("""
            | writer readWriter file |
            WriteStream subclass: #AuditStreamWriter instanceVariableNames: ''.
            ReadWriteStream subclass: #AuditStreamReaderWriter instanceVariableNames: ''.
            AuditStreamReaderWriter compile: 'nextPut: element ^ super nextPut: element + 10'.
            WriteFileStream subclass: #AuditFileWriter instanceVariableNames: ''.
            writer := AuditStreamWriter with: #().
            readWriter := AuditStreamReaderWriter on: #().
            file := AuditFileWriter new _openFile: filePath mode: #create check: true type: #binary.
            [ file nextPutAll: #(5 6) ] ensure: [ file close ].
            writer nextPutAll: #(1 2).
            readWriter nextPutAll: #(3 4).
            Array with: writer contents with: readWriter contents
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(#(1 2) #(13 14))")
        #expect(try Data(contentsOf: path) == Data([5, 6]))
    }

    @Test func puttableStreamsHonorEditedNextPutMethodsWithBuiltInSources() async throws {
        let directory = try newFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("overridden.txt")

        let session = try await session(for: path)
        let result = await session.evaluate("""
            | file collection |
            WriteFileStream compile: 'nextPut: element
                self _writeFileElements: (Array with: element asUppercase)'.
            WriteStream compile: 'nextPut: element self _write: (Array with: 10 + element)'.
            file := FileStream write: filePath.
            [ file nextPutAll: 'ab' ] ensure: [ file close ].
            collection := WriteStream with: Array new.
            collection nextPutAll: #(1 2 3).
            collection contents
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(11 12 13)")
        #expect(try Data(contentsOf: path) == Data("AB".utf8))
    }

    @Test func puttableStreamsHonorEditedEnumerationMethodsOnArray() async throws {
        let directory = try newFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("reversed.bin")
        let session = try await session(for: path)
        let result = await session.evaluate("""
            | writer |
            Array compile: 'do: action
                | index |
                index := self size.
                [ index > 0 ] whileTrue: [
                    action value: (self at: index).
                    index := index - 1 ]'.
            writer := FileStream write: filePath mode: #create check: true type: #binary.
            [ writer nextPutAll: #(1 2 3) ] ensure: [ writer close ]
            """)
        #expect(result.error == nil)
        #expect(try Data(contentsOf: path) == Data([3, 2, 1]))
    }

    private func newFixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func session(for path: URL) async throws -> SmalltalkSession {
        let session = SmalltalkSession()
        try await session.worker.submitThrowing { runtime in
            runtime.globals["filePath"] = .string(path.path)
        }
        return session
    }
}
