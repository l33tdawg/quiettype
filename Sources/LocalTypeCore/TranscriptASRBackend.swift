import Foundation

public actor TranscriptASRBackend: ASRBackend {
    private var transcript: String
    private var didStart = false
    private var didCancel = false

    public init(transcript: String = "") {
        self.transcript = transcript
    }

    public func setTranscript(_ transcript: String) {
        self.transcript = transcript
    }

    public func startSession(profile: DictationProfile) async throws {
        didStart = true
        didCancel = false
    }

    public func pushAudio(_ frame: AudioFrame) async throws {
        guard didStart, !didCancel else {
            throw LocalTypeError.invalidSessionState("ASR session is not active")
        }
    }

    public func partialTranscript() async throws -> String {
        guard didStart, !didCancel else {
            return ""
        }
        return transcript
    }

    public func stableSegments() async throws -> [StableSegment] {
        guard didStart, !didCancel, !transcript.isEmpty else {
            return []
        }
        return [StableSegment(text: transcript, confidence: 1.0, isFinal: false)]
    }

    public func finish() async throws -> [StableSegment] {
        guard didStart, !didCancel else {
            throw LocalTypeError.invalidSessionState("ASR session cannot finish before start")
        }
        return transcript.isEmpty ? [] : [StableSegment(text: transcript, confidence: 1.0, isFinal: true)]
    }

    public func cancel() async {
        didCancel = true
    }
}
