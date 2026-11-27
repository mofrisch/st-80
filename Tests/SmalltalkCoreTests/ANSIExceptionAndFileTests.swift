import Foundation
import Testing
@testable import SmalltalkCore

struct ANSIExceptionAndFileTests {
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
