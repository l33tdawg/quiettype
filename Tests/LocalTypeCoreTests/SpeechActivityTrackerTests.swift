import XCTest
@testable import LocalTypeCore

final class SpeechActivityTrackerTests: XCTestCase {
    func testRequiresSustainedSpeechAndKeepsShortPausesInsideHangover() {
        let configuration = SpeechActivityConfiguration(
            activationDurationMS: 100,
            hangoverDurationMS: 300
        )
        var tracker = SpeechActivityTracker(configuration: configuration)

        XCTAssertEqual(tracker.observe(rms: 0.003, frameDurationSeconds: 0.05).state, .silence)
        XCTAssertFalse(tracker.observe(rms: 0.03, frameDurationSeconds: 0.05).didStartSpeech)

        let started = tracker.observe(rms: 0.03, frameDurationSeconds: 0.05)
        XCTAssertTrue(started.didStartSpeech)
        XCTAssertEqual(started.state, .speech)

        let briefPause = tracker.observe(rms: 0.001, frameDurationSeconds: 0.10)
        XCTAssertEqual(briefPause.state, .hangover)
        XCTAssertTrue(briefPause.isSpeechActive)
        XCTAssertFalse(briefPause.didEndSpeech)

        XCTAssertEqual(tracker.observe(rms: 0.03, frameDurationSeconds: 0.05).state, .speech)
        XCTAssertFalse(tracker.observe(rms: 0.001, frameDurationSeconds: 0.10).didEndSpeech)
        XCTAssertFalse(tracker.observe(rms: 0.001, frameDurationSeconds: 0.10).didEndSpeech)
        let ended = tracker.observe(rms: 0.001, frameDurationSeconds: 0.10)
        XCTAssertTrue(ended.didEndSpeech)
        XCTAssertEqual(ended.state, .silence)
    }

    func testShortNoiseBurstDoesNotBecomeSpeech() {
        let configuration = SpeechActivityConfiguration(
            activationDurationMS: 120,
            hangoverDurationMS: 300
        )
        var tracker = SpeechActivityTracker(configuration: configuration)

        XCTAssertEqual(tracker.observe(rms: 0.04, frameDurationSeconds: 0.04).state, .silence)
        XCTAssertEqual(tracker.observe(rms: 0.002, frameDurationSeconds: 0.04).state, .silence)
        XCTAssertEqual(tracker.observe(rms: 0.04, frameDurationSeconds: 0.04).state, .silence)
    }

    func testNoiseFloorAdaptsOnlyWhileSilent() {
        var tracker = SpeechActivityTracker()
        let initialFloor = tracker.noiseFloorRMS

        for _ in 0..<20 {
            _ = tracker.observe(rms: 0.001, frameDurationSeconds: 0.02)
        }

        XCTAssertLessThan(tracker.noiseFloorRMS, initialFloor)
        XCTAssertGreaterThanOrEqual(tracker.noiseFloorRMS, 0.0004)
    }
}
