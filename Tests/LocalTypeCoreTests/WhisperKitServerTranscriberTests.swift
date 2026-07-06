import XCTest
@testable import LocalTypeCore

final class WhisperKitServerTranscriberTests: XCTestCase {
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

    func testPreservesSingingMarkerInServerResponse() throws {
        let data = #"{"text":"*singing* I want it all"}"#.data(using: .utf8)!

        XCTAssertEqual(try WhisperKitServerTranscriber.parseTranscript(from: data), "[singing] I want it all")
    }

    func testRemovesMusicMarkerInServerResponse() throws {
        let data = #"{"text":"[Music] please send the note"}"#.data(using: .utf8)!

        XCTAssertEqual(try WhisperKitServerTranscriber.parseTranscript(from: data), "please send the note")
    }
}
