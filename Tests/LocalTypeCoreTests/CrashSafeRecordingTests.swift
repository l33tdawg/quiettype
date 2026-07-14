import XCTest
@testable import LocalTypeCore

final class CrashSafeRecordingTests: XCTestCase {
    func testCheckpointsAudioAndMarksUnfinishedRecordingInterrupted() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CrashSafeRecordingStore(directory: directory, checkpointIntervalSeconds: 1)
        var session = try store.begin(id: "recording", at: Date(timeIntervalSince1970: 100))

        try session.append(
            AudioFrame(samples: Array(repeating: 0.25, count: 10), sampleRate: 4, timestamp: 0),
            at: Date(timeIntervalSince1970: 102)
        )

        XCTAssertEqual(session.manifest.segmentCount, 2)
        XCTAssertEqual(session.manifest.capturedDurationSeconds, 2, accuracy: 0.001)

        let recovered = try store.markActiveRecordingsInterrupted(at: Date(timeIntervalSince1970: 103))
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered.first?.state, .interrupted)
        XCTAssertEqual(recovered.first?.reason, "QuietType closed before this recording was finished.")
    }

    func testSealFlushesTailAndMergesCheckpointFiles() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("merged.wav")
        let store = CrashSafeRecordingStore(directory: directory, checkpointIntervalSeconds: 1)
        var session = try store.begin(id: "recording", at: Date(timeIntervalSince1970: 100))

        try session.append(
            AudioFrame(samples: Array(repeating: 0.25, count: 9), sampleRate: 4, timestamp: 0),
            at: Date(timeIntervalSince1970: 102)
        )
        let sealed = try session.seal(at: Date(timeIntervalSince1970: 103))
        XCTAssertEqual(sealed.state, .readyForTranscription)
        XCTAssertEqual(sealed.segmentCount, 3)
        XCTAssertEqual(sealed.capturedDurationSeconds, 2.25, accuracy: 0.001)

        let merged = try store.mergeRecording(id: sealed.id, to: output)
        XCTAssertEqual(merged.id, sealed.id)
        let data = try Data(contentsOf: output)
        XCTAssertEqual(String(data: data[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(data.count, 44 + 9 * 2)
    }

    func testDiscardRemovesRecoveryRecording() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CrashSafeRecordingStore(directory: directory)
        _ = try store.begin(id: "recording")

        try store.discard(id: "recording")

        XCTAssertTrue(try store.recoverableRecordings().isEmpty)
    }

    func testRejectsSampleRateChangesInsteadOfCreatingAnUnrecoverableFile() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CrashSafeRecordingStore(directory: directory)
        var session = try store.begin(id: "recording")

        try session.append(AudioFrame(samples: [0.2], sampleRate: 16_000, timestamp: 0))

        XCTAssertThrowsError(
            try session.append(AudioFrame(samples: [0.2], sampleRate: 48_000, timestamp: 0))
        ) { error in
            XCTAssertEqual(
                error as? CrashSafeRecordingError,
                .sampleRateChanged(expected: 16_000, actual: 48_000)
            )
        }
    }

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("quiettype-recovery-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
