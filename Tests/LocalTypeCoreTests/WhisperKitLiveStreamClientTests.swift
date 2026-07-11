import XCTest
@testable import LocalTypeCore

final class WhisperKitLiveStreamClientTests: XCTestCase {
    func testEncodesPCM16LittleEndian() {
        let data = WhisperKitLiveStreamClient.encodePCM16([-1, 0, 1])

        XCTAssertEqual(Array(data), [1, 128, 0, 0, 255, 127])
    }

    func testDecodesFinalServerEvent() throws {
        let data = Data(#"{"type":"final","text":"hello","covered_samples":32000,"sample_rate":16000}"#.utf8)

        let event = try JSONDecoder().decode(WhisperKitLiveStreamClient.ServerEvent.self, from: data)

        XCTAssertEqual(event.type, "final")
        XCTAssertEqual(event.text, "hello")
        XCTAssertEqual(event.coveredSamples, 32_000)
        XCTAssertEqual(event.sampleRate, 16_000)
    }

    func testRejectsNonLoopbackEndpointBeforeSendingAudio() async {
        let client = WhisperKitLiveStreamClient(endpoint: URL(string: "ws://example.com/v1/audio/live")!)

        do {
            try await client.append(AudioFrame(samples: [0.1], sampleRate: 16_000, timestamp: 0))
            XCTFail("Expected non-loopback endpoint rejection")
        } catch AudioTranscriberError.nonLoopbackEndpoint(let value) {
            XCTAssertEqual(value, "ws://example.com/v1/audio/live")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
