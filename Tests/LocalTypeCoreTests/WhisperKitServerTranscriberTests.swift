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
}
