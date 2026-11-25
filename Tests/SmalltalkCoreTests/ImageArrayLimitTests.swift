import Foundation
import Testing
@testable import SmalltalkCore

struct ImageArrayLimitTests {
    @Test func placeholderSizeIsCheckedBeforeCreatingItsStorage() throws {
        let runtime = SmalltalkRuntime(bootstrap: false)
        // Int.max cannot be used to construct a host array. Rejecting the
        // count itself proves the check precedes placeholder allocation.
        for count in [-1, runtime.arrayLimit + 1, Int.max] {
            #expect(throws: SmalltalkError.self) { try runtime.array(count: count) }
        }
        #expect(runtime.memory.statistics.totalAllocated == 0)
        for count in [0, runtime.arrayLimit] {
            guard case .array(let array) = try runtime.array(count: count) else {
                Issue.record("Expected a placeholder array.")
                return
            }
            #expect(array.elements.count == count)
            #expect(array.elements.allSatisfy(runtime.isNil))
        }
    }

    @Test func oversizedImageArrayRejectsWithoutReplacingTheLiveSession() async throws {
        let session = SmalltalkSession()
        #expect(await session.evaluate("kept := 42").error == nil)
        var image = try await JSONDecoder().decode(ImageArchive.self, from: session.imageData())
        image.globals["oversized"] = .reference(image.nodes.count)
        image.nodes.append(.array(Array(repeating: .nilValue, count: 4_097)))
        let bytes = try JSONEncoder().encode(image)

        do {
            _ = try await session.loadImage(bytes)
            Issue.record("An oversized image array was accepted.")
        } catch let error as SmalltalkError {
            #expect(error.message.contains("4,096"))
        }
        #expect(await session.evaluate("kept + 1").value == "43")
        #expect(await session.evaluate("oversized").executionError?.contains("Unknown variable") == true)
    }

    @Test func largestValidImageArrayRestoresItsSizeAndLastElement() async throws {
        let original = SmalltalkSession()
        #expect(await original.evaluate("full := Array new: 4096. full at: 4096 put: 73").error == nil)
        let restored = SmalltalkSession()
        _ = try await restored.loadImage(original.imageData())
        #expect(await restored.evaluate("full size").value == "4096")
        #expect(await restored.evaluate("full at: 4096").value == "73")
        #expect(await restored.evaluate("full at: 1").value == "nil")
    }
}
