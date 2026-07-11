import XCTest
@testable import LocalTypeCore

final class WhisperKitServerTranscriberTests: XCTestCase {
    func testTimedRequestUsesOnlyArgmaxSupportedMultipartFields() throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quiettype-multipart-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: audioURL) }
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: audioURL)

        let body = try WhisperKitServerTranscriber().multipartBody(
            audioFile: audioURL,
            boundary: "QuietType-Test",
            options: AudioTranscriptionOptions(initialPrompt: "Vocabulary: Raft."),
            includeWordTimestamps: true
        )
        let request = String(decoding: body, as: UTF8.self)

        XCTAssertTrue(request.contains("name=\"timestamp_granularities[]\""))
        XCTAssertTrue(request.contains("name=\"prompt\""))
        XCTAssertFalse(request.contains("name=\"word_timestamps\""))
    }

    func testRejectsNonLoopbackEndpoint() async throws {
        let transcriber = WhisperKitServerTranscriber(endpoint: URL(string: "https://example.com/v1/audio/transcriptions")!)

        do {
            _ = try await transcriber.transcribe(audioFile: URL(fileURLWithPath: "/tmp/missing.wav"))
            XCTFail("Expected non-loopback endpoint rejection")
        } catch AudioTranscriberError.nonLoopbackEndpoint("https://example.com/v1/audio/transcriptions") {
            // Expected.
        }
    }

    func testParsesOpenAIStyleTextResponse() throws {
        let data = #"{"text":"  hello quiettype  "}"#.data(using: .utf8)!

        XCTAssertEqual(try WhisperKitServerTranscriber.parseTranscript(from: data), "hello quiettype")
    }

    func testParsesTranscriptResponse() throws {
        let data = #"{"transcript":"turn and face the strange"}"#.data(using: .utf8)!

        XCTAssertEqual(try WhisperKitServerTranscriber.parseTranscript(from: data), "turn and face the strange")
    }

    func testParsesSegmentResponse() throws {
        let data = #"{"segments":[{"text":"turn and face"},{"text":" the strange"}]}"#.data(using: .utf8)!

        XCTAssertEqual(try WhisperKitServerTranscriber.parseTranscript(from: data), "turn and face the strange")
    }

    func testFallsBackFromEmptyTextToSegments() throws {
        let data = #"{"text":"   ","segments":[{"text":"turn and face"},{"text":" the strange"}]}"#.data(using: .utf8)!

        XCTAssertEqual(try WhisperKitServerTranscriber.parseTranscript(from: data), "turn and face the strange")
    }

    func testEmptyCreateTranscriptionResponseDoesNotExposeRawJSON() throws {
        let data = #"{"text":"","type":"CreateTranscriptionResponseJson"}"#.data(using: .utf8)!

        XCTAssertEqual(try WhisperKitServerTranscriber.parseTranscript(from: data), "")
    }

    func testParsesNestedResultSegments() throws {
        let data = #"{"result":{"segments":[{"text":"hello"},{"text":" quiettype"}]}}"#.data(using: .utf8)!

        XCTAssertEqual(try WhisperKitServerTranscriber.parseTranscript(from: data), "hello quiettype")
    }

    func testParsesTopLevelWordTimestamps() throws {
        let data = #"{"text":"hello quiettype","words":[{"word":"hello","start":0.1,"end":0.4,"confidence":0.91},{"word":"quiettype","start":0.5,"end":0.9,"probability":0.88}]}"#.data(using: .utf8)!

        let result = try WhisperKitServerTranscriber.parseTimedTranscript(from: data)

        XCTAssertEqual(result.text, "hello quiettype")
        XCTAssertEqual(result.words, [
            TranscribedWordTiming(word: "hello", startSeconds: 0.1, endSeconds: 0.4, confidence: 0.91),
            TranscribedWordTiming(word: "quiettype", startSeconds: 0.5, endSeconds: 0.9, confidence: 0.88)
        ])
    }

    func testParsesSegmentWordTimestamps() throws {
        let data = #"{"segments":[{"text":"hello quiettype","words":[{"text":"hello","start_seconds":"0.10","end_seconds":"0.40"},{"text":"quiettype","start_seconds":"0.50","end_seconds":"0.90"}]}]}"#.data(using: .utf8)!

        let result = try WhisperKitServerTranscriber.parseTimedTranscript(from: data)

        XCTAssertEqual(result.text, "hello quiettype")
        XCTAssertEqual(result.words, [
            TranscribedWordTiming(word: "hello", startSeconds: 0.1, endSeconds: 0.4),
            TranscribedWordTiming(word: "quiettype", startSeconds: 0.5, endSeconds: 0.9)
        ])
    }

    func testPreservesSingingMarkerInServerResponse() throws {
        let data = #"{"text":"*singing* I want it all"}"#.data(using: .utf8)!

        XCTAssertEqual(try WhisperKitServerTranscriber.parseTranscript(from: data), "[singing] I want it all")
    }

    func testRemovesMusicMarkerInServerResponse() throws {
        let data = #"{"text":"[Music] please send the note"}"#.data(using: .utf8)!

        XCTAssertEqual(try WhisperKitServerTranscriber.parseTranscript(from: data), "please send the note")
    }

    func testFullAudioTimeoutScalesWithDuration() {
        XCTAssertEqual(
            WhisperKitServerTranscriber.timeoutForFullAudio(durationSeconds: 1),
            WhisperKitServerTranscriber.minimumFullAudioTimeoutSeconds
        )
        XCTAssertEqual(WhisperKitServerTranscriber.timeoutForFullAudio(durationSeconds: 10), 80)
        XCTAssertEqual(
            WhisperKitServerTranscriber.timeoutForFullAudio(durationSeconds: 60),
            WhisperKitServerTranscriber.maximumFullAudioTimeoutSeconds
        )
    }

    func testRequestTimeoutFailureMessageIsUserReadable() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)

        let message = WhisperKitServerTranscriber.describeRequestFailure(error, timeoutSeconds: 45)

        XCTAssertTrue(message.contains("timed out after 45s"))
        XCTAssertFalse(message.contains("NSURLErrorDomain"))
    }
}
