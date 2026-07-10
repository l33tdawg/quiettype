import Foundation
import XCTest
@testable import LocalTypeCore

final class VoiceFlowMetricsTests: XCTestCase {
    func testAccumulatorRecordsContentFreeFlowMeasurements() throws {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000025")!
        var accumulator = VoiceFlowMetricAccumulator(sessionID: sessionID, startedAt: startedAt)

        accumulator.recordAudioFrame(activity: activity(state: .speech, didStart: true, durationMS: 100))
        accumulator.recordAudioFrame(activity: activity(state: .speech, durationMS: 100))
        accumulator.recordAudioFrame(activity: activity(state: .silence, didEnd: true, durationMS: 400))
        accumulator.recordEmittedChunks(total: 3)
        accumulator.recordStreamingDiagnostics(enqueuedChunkCount: 3, completedChunkCount: 2, maxQueueDepth: 2)
        accumulator.recordPartialTranscript("hello world", at: startedAt.addingTimeInterval(0.5))
        accumulator.recordPartialTranscript("hello brave world", at: startedAt.addingTimeInterval(0.7))
        accumulator.markReleased(at: startedAt.addingTimeInterval(2), recordingDuration: 2)
        accumulator.markFinalTranscript(at: startedAt.addingTimeInterval(2.4))
        let record = accumulator.finish(
            outcome: .inserted,
            finalWordCount: 3,
            at: startedAt.addingTimeInterval(2.8)
        )

        XCTAssertEqual(record.sessionID, sessionID)
        XCTAssertEqual(record.audioFrameCount, 3)
        XCTAssertEqual(record.speechSegmentCount, 1)
        XCTAssertEqual(record.activeSpeechDurationMS, 200)
        XCTAssertEqual(record.longestPauseMS, 400)
        XCTAssertEqual(record.emittedChunkCount, 3)
        XCTAssertEqual(record.streamingEnqueuedChunkCount, 3)
        XCTAssertEqual(record.streamingCompletedChunkCount, 2)
        XCTAssertEqual(record.maxStreamingQueueDepth, 2)
        XCTAssertEqual(record.firstPartialASRMS, 500)
        XCTAssertEqual(record.partialUpdateCount, 2)
        XCTAssertEqual(record.previewRevisionCount, 1)
        XCTAssertEqual(record.releaseToFinalTranscriptMS, 400)
        XCTAssertEqual(record.releaseToCompletionMS, 800)
        XCTAssertEqual(record.finalWordCount, 3)
        XCTAssertEqual(record.outcome, .inserted)

        let encoded = try JSONEncoder().encode(record)
        let json = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(json.contains("transcript"))
        XCTAssertFalse(json.contains("audioPath"))
        XCTAssertFalse(json.contains("appName"))
        XCTAssertFalse(json.contains("filename"))
    }

    func testStoreWritesOwnerOnlyJSONLines() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quiettype-voice-metrics-tests")
            .appendingPathComponent(UUID().uuidString)
        let fileURL = root.appendingPathComponent("metrics.jsonl")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalVoiceFlowMetricsStore(fileURL: fileURL)
        let startedAt = Date(timeIntervalSince1970: 2_000)
        let record = VoiceFlowMetricAccumulator(startedAt: startedAt).finish(outcome: .cancelled, at: startedAt)

        try await store.append(record)

        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
        XCTAssertEqual(lines.count, 1)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions.map { $0 & 0o777 }, 0o600)
    }

    func testHangoverCountsAsPauseInsteadOfActiveSpeech() {
        let startedAt = Date(timeIntervalSince1970: 3_000)
        var accumulator = VoiceFlowMetricAccumulator(startedAt: startedAt)

        accumulator.recordAudioFrame(activity: activity(state: .speech, didStart: true, durationMS: 100))
        accumulator.recordAudioFrame(activity: activity(state: .hangover, durationMS: 250))
        accumulator.recordAudioFrame(activity: activity(state: .speech, durationMS: 100))
        let record = accumulator.finish(outcome: .cancelled, at: startedAt.addingTimeInterval(0.45))

        XCTAssertEqual(record.activeSpeechDurationMS, 200)
        XCTAssertEqual(record.longestPauseMS, 250)
    }

    private func activity(
        state: SpeechActivityState,
        didStart: Bool = false,
        didEnd: Bool = false,
        durationMS: Int
    ) -> SpeechActivityUpdate {
        SpeechActivityUpdate(
            state: state,
            didStartSpeech: didStart,
            didEndSpeech: didEnd,
            frameDurationMS: durationMS,
            noiseFloorRMS: 0.004,
            activationThresholdRMS: 0.008,
            releaseThresholdRMS: 0.006
        )
    }
}
