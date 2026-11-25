import Foundation

public struct LoadedImage: Sendable {
    public let evaluation: EvaluationResult
    public let workspace: String
    public let transcript: String
}

extension SmalltalkSession {
    public func imageData(workspace: String = "", transcript: String = "") async throws -> Data {
        try await worker.submitThrowing { try ImageCodec.encode($0, workspace: workspace, transcript: transcript) }
    }

    public func loadImage(_ data: Data) async throws -> LoadedImage {
        try await worker.submitThrowing { runtime in
            let (replacement, contents) = try ImageCodec.decode(data)
            runtime = replacement
            return contents
        }
    }

    public func saveImage(to url: URL, workspace: String, transcript: String) async throws {
        try await worker.submitThrowing { runtime in
            try ImageFiles.save(runtime, to: url, workspace: workspace, transcript: transcript)
        }
    }

    public func loadImage(from url: URL) async throws -> LoadedImage {
        try await worker.submitThrowing { runtime in
            let (replacement, contents) = try ImageFiles.load(url)
            runtime = replacement
            return contents
        }
    }
}
