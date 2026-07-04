import Foundation

public protocol AudioFileTranscribing: Sendable {
    func transcribe(audioFile: URL) async throws -> String
}

public enum AudioTranscriberError: Error, Equatable {
    case nonLoopbackEndpoint(String)
    case emptyTranscript
    case noiseOnlyTranscript(String)
    case badResponse(Int)
    case allBackendsFailed([String])
}

public struct NoopAudioFileTranscriber: AudioFileTranscribing {
    public init() {}

    public func transcribe(audioFile: URL) async throws -> String {
        throw AudioTranscriberError.emptyTranscript
    }
}
