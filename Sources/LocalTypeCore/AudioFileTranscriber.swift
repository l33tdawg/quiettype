import Foundation

public struct AudioTranscriptionOptions: Equatable, Sendable {
    public var initialPrompt: String?

    public init(initialPrompt: String? = nil) {
        let trimmed = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.initialPrompt = trimmed?.isEmpty == false ? trimmed : nil
    }

    public static let none = AudioTranscriptionOptions()
}

public protocol AudioFileTranscribing: Sendable {
    func transcribe(audioFile: URL, options: AudioTranscriptionOptions) async throws -> String
}

public extension AudioFileTranscribing {
    func transcribe(audioFile: URL) async throws -> String {
        try await transcribe(audioFile: audioFile, options: .none)
    }
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

    public func transcribe(audioFile: URL, options: AudioTranscriptionOptions) async throws -> String {
        throw AudioTranscriberError.emptyTranscript
    }
}
