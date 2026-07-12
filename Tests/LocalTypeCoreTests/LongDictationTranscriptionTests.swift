import Foundation
@testable import LocalTypeCore
import XCTest

final class LongDictationTranscriptionTests: XCTestCase {
    func testActivatesOnlyBeyondSafeSingleWindowDuration() {
        XCTAssertFalse(
            LongDictationTranscription.requiresChunkedRecovery(sampleCount: 44_999, sampleRate: 1_000)
        )
        XCTAssertTrue(
            LongDictationTranscription.requiresChunkedRecovery(sampleCount: 45_000, sampleRate: 1_000)
        )
    }

    func testChunksObservedLongRecordingWithCompleteNonDuplicatedCoverage() throws {
        let sampleRate = 100
        let sampleCount = 6_540
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quiettype-long-dictation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let chunks = try LongDictationTranscription.makeChunks(
            samples: Array(repeating: 0.1, count: sampleCount),
            sampleRate: sampleRate,
            outputDirectory: directory
        )

        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks.map(\.sampleCount), [2_800, 2_800, 1_340])
        XCTAssertEqual(chunks.map(\.coveredSampleCount), [2_800, 2_600, 1_140])
        XCTAssertEqual(chunks.reduce(0) { $0 + $1.coveredSampleCount }, sampleCount)
    }

    func testRejectsIncompleteChunkResultsEvenWhenSomeTextExists() {
        let incomplete = StreamingTranscriptionResult(
            text: "only the first half",
            chunkCount: 1,
            coveredDurationSeconds: 28,
            errors: [],
            enqueuedChunkCount: 3
        )
        XCTAssertFalse(
            LongDictationTranscription.isComplete(incomplete, expectedDurationSeconds: 65.4)
        )

        let complete = StreamingTranscriptionResult(
            text: "the complete merged transcript",
            chunkCount: 3,
            coveredDurationSeconds: 65.4,
            errors: [],
            enqueuedChunkCount: 3
        )
        XCTAssertTrue(
            LongDictationTranscription.isComplete(complete, expectedDurationSeconds: 65.4)
        )
    }

    func testCreatesZeroCoverageTailRescueOnlyWhenTailHasSignal() throws {
        let sampleRate = 100
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quiettype-tail-rescue-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let rescue = try XCTUnwrap(
            LongDictationTranscription.makeTailRescueChunk(
                samples: Array(repeating: 0.1, count: 1_000),
                sampleRate: sampleRate,
                sequence: 3,
                outputDirectory: directory
            )
        )
        XCTAssertEqual(rescue.sequence, 3)
        XCTAssertEqual(rescue.sampleCount, 800)
        XCTAssertEqual(rescue.coveredSampleCount, 0)

        XCTAssertNil(
            try LongDictationTranscription.makeTailRescueChunk(
                samples: Array(repeating: 0.0001, count: 1_000),
                sampleRate: sampleRate,
                sequence: 3,
                outputDirectory: directory
            )
        )
    }
}
