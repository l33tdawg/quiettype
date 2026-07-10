import XCTest
@testable import LocalTypeCore

final class StreamingWavChunkerTests: XCTestCase {
    func testEmitsOneSecondChunks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        var chunker = StreamingWavChunker(sampleRate: 4, chunkDurationSeconds: 1, maxDurationSeconds: 60)
        let chunks = try chunker.append(
            AudioFrame(samples: Array(repeating: 0.1, count: 9), sampleRate: 4, timestamp: 0),
            outputDirectory: directory
        )

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].sampleCount, 4)
        XCTAssertEqual(chunks[1].sampleCount, 4)
        XCTAssertTrue(FileManager.default.fileExists(atPath: chunks[0].url.path))

        let final = try chunker.flush(outputDirectory: directory)
        XCTAssertEqual(final?.sampleCount, 1)
    }

    func testReportsMaxDuration() throws {
        var chunker = StreamingWavChunker(sampleRate: 10, chunkDurationSeconds: 1, maxDurationSeconds: 2)
        _ = try chunker.append(
            AudioFrame(samples: Array(repeating: 0.1, count: 20), sampleRate: 10, timestamp: 0),
            outputDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )

        XCTAssertTrue(chunker.reachedMaxDuration)
    }

    func testOverlapsChunksAndReportsOnlyNewCoverage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        var chunker = StreamingWavChunker(
            sampleRate: 4,
            chunkDurationSeconds: 1,
            overlapDurationSeconds: 0.25,
            maxDurationSeconds: 60
        )
        let chunks = try chunker.append(
            AudioFrame(samples: Array(repeating: 0.1, count: 9), sampleRate: 4, timestamp: 0),
            outputDirectory: directory
        )
        let final = try chunker.flush(outputDirectory: directory)

        XCTAssertEqual(chunks.map { $0.sampleCount }, [4, 4])
        XCTAssertEqual(chunks.map { $0.coveredSampleCount }, [4, 3])
        XCTAssertEqual(final?.sampleCount, 3)
        XCTAssertEqual(final?.coveredSampleCount, 2)
        XCTAssertEqual(chunks.reduce(0) { $0 + $1.coveredSampleCount } + (final?.coveredSampleCount ?? 0), 9)
    }
}
