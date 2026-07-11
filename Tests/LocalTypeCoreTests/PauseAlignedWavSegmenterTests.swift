import XCTest
@testable import LocalTypeCore

final class PauseAlignedWavSegmenterTests: XCTestCase {
    func testCutsOnlyAtPauseAfterMinimumDuration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var segmenter = PauseAlignedWavSegmenter(sampleRate: 10, minimumSegmentDurationSeconds: 2)

        let earlyPause = try segmenter.append(
            AudioFrame(samples: Array(repeating: 0.1, count: 10), sampleRate: 10, timestamp: 0),
            activity: activity(didEndSpeech: true),
            outputDirectory: directory
        )
        let speech = try segmenter.append(
            AudioFrame(samples: Array(repeating: 0.1, count: 10), sampleRate: 10, timestamp: 1),
            activity: activity(didEndSpeech: false),
            outputDirectory: directory
        )
        let pause = try segmenter.append(
            AudioFrame(samples: Array(repeating: 0, count: 5), sampleRate: 10, timestamp: 2),
            activity: activity(didEndSpeech: true),
            outputDirectory: directory
        )

        XCTAssertNil(earlyPause)
        XCTAssertNil(speech)
        XCTAssertEqual(pause?.sampleCount, 25)
        XCTAssertEqual(pause?.coveredSampleCount, 25)
        XCTAssertEqual(segmenter.pendingDurationSeconds, 0)
    }

    func testFlushPreservesCompleteNonOverlappingCoverage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var segmenter = PauseAlignedWavSegmenter(sampleRate: 10, minimumSegmentDurationSeconds: 1)

        let first = try segmenter.append(
            AudioFrame(samples: Array(repeating: 0.1, count: 12), sampleRate: 10, timestamp: 0),
            activity: activity(didEndSpeech: true),
            outputDirectory: directory
        )
        _ = try segmenter.append(
            AudioFrame(samples: Array(repeating: 0.1, count: 7), sampleRate: 10, timestamp: 1.2),
            activity: activity(didEndSpeech: false),
            outputDirectory: directory
        )
        let final = try segmenter.flush(outputDirectory: directory)

        XCTAssertEqual(first?.sequence, 0)
        XCTAssertEqual(final?.sequence, 1)
        XCTAssertEqual((first?.coveredSampleCount ?? 0) + (final?.coveredSampleCount ?? 0), 19)
    }

    private func activity(didEndSpeech: Bool) -> SpeechActivityUpdate {
        SpeechActivityUpdate(
            state: didEndSpeech ? .silence : .speech,
            didStartSpeech: false,
            didEndSpeech: didEndSpeech,
            frameDurationMS: 100,
            noiseFloorRMS: 0.006,
            activationThresholdRMS: 0.0114,
            releaseThresholdRMS: 0.0081
        )
    }
}
