import Foundation
@testable import LocalTypeCore
import XCTest

final class StreamingAudioTranscriptionSessionTests: XCTestCase {
    func testMergesChunkTranscriptsInSequenceOrder() async throws {
        let transcriber = StubAudioTranscriber(outputs: [
            "chunk-0001.wav": "world",
            "chunk-0000.wav": "hello"
        ])
        let session = StreamingAudioTranscriptionSession(transcriber: transcriber)

        await session.enqueue(WavAudioChunk(sequence: 1, url: URL(fileURLWithPath: "/tmp/chunk-0001.wav"), sampleRate: 16_000, sampleCount: 16_000))
        await session.enqueue(WavAudioChunk(sequence: 0, url: URL(fileURLWithPath: "/tmp/chunk-0000.wav"), sampleRate: 16_000, sampleCount: 16_000))

        let result = await session.finish()

        XCTAssertEqual(result.text, "hello world")
        XCTAssertEqual(result.chunkCount, 2)
        XCTAssertEqual(result.coveredDurationSeconds, 2.0, accuracy: 0.001)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.enqueuedChunkCount, 2)
        XCTAssertGreaterThanOrEqual(result.maxQueueDepth, 1)
    }

    func testTracksCoveredDurationForSuccessfulTranscriptChunksOnly() async throws {
        let transcriber = StubAudioTranscriber(outputs: [
            "chunk-0000.wav": "hello",
            "chunk-0002.wav": "world"
        ])
        let session = StreamingAudioTranscriptionSession(transcriber: transcriber)

        await session.enqueue(WavAudioChunk(sequence: 0, url: URL(fileURLWithPath: "/tmp/chunk-0000.wav"), sampleRate: 16_000, sampleCount: 32_000))
        await session.enqueue(WavAudioChunk(sequence: 1, url: URL(fileURLWithPath: "/tmp/chunk-0001.wav"), sampleRate: 16_000, sampleCount: 16_000))
        await session.enqueue(WavAudioChunk(sequence: 2, url: URL(fileURLWithPath: "/tmp/chunk-0002.wav"), sampleRate: 16_000, sampleCount: 48_000))

        let result = await session.finish()

        XCTAssertEqual(result.text, "hello world")
        XCTAssertEqual(result.chunkCount, 2)
        XCTAssertEqual(result.coveredDurationSeconds, 5.0, accuracy: 0.001)
        XCTAssertEqual(result.errors.count, 1)
    }

    func testKeepsSuccessfulChunksWhenOneChunkFails() async throws {
        let transcriber = StubAudioTranscriber(outputs: [
            "chunk-0000.wav": "hello"
        ])
        let session = StreamingAudioTranscriptionSession(transcriber: transcriber)

        await session.enqueue(WavAudioChunk(sequence: 0, url: URL(fileURLWithPath: "/tmp/chunk-0000.wav"), sampleRate: 16_000, sampleCount: 16_000))
        await session.enqueue(WavAudioChunk(sequence: 1, url: URL(fileURLWithPath: "/tmp/chunk-0001.wav"), sampleRate: 16_000, sampleCount: 16_000))

        let result = await session.finish()

        XCTAssertEqual(result.text, "hello")
        XCTAssertEqual(result.chunkCount, 1)
        XCTAssertEqual(result.coveredDurationSeconds, 1.0, accuracy: 0.001)
        XCTAssertEqual(result.errors.count, 1)
    }

    func testPassesTranscriptionOptionsToChunks() async throws {
        let transcriber = StubAudioTranscriber(outputs: [
            "chunk-0000.wav": "CometBFT"
        ])
        let session = StreamingAudioTranscriptionSession(
            transcriber: transcriber,
            options: AudioTranscriptionOptions(initialPrompt: "Vocabulary: CometBFT.")
        )

        await session.enqueue(WavAudioChunk(sequence: 0, url: URL(fileURLWithPath: "/tmp/chunk-0000.wav"), sampleRate: 16_000, sampleCount: 16_000))
        let result = await session.finish()
        let prompts = await transcriber.recordedPrompts()

        XCTAssertEqual(result.text, "CometBFT")
        XCTAssertEqual(prompts, ["Vocabulary: CometBFT."])
    }

    func testMergesOverlappedChunkTextWithoutDoubleCountingCoverage() async throws {
        let transcriber = StubAudioTranscriber(outputs: [
            "chunk-0000.wav": "we need apples and",
            "chunk-0001.wav": "apples and bananas"
        ])
        let session = StreamingAudioTranscriptionSession(transcriber: transcriber)

        await session.enqueue(WavAudioChunk(sequence: 0, url: URL(fileURLWithPath: "/tmp/chunk-0000.wav"), sampleRate: 4, sampleCount: 4, coveredSampleCount: 4))
        await session.enqueue(WavAudioChunk(sequence: 1, url: URL(fileURLWithPath: "/tmp/chunk-0001.wav"), sampleRate: 4, sampleCount: 4, coveredSampleCount: 3))

        let result = await session.finish()

        XCTAssertEqual(result.text, "we need apples and bananas")
        XCTAssertEqual(result.coveredDurationSeconds, 1.75, accuracy: 0.001)
    }

    func testDoesNotDeduplicateWordsWhenChunksDoNotOverlap() async throws {
        let transcriber = StubAudioTranscriber(outputs: [
            "chunk-0000.wav": "go",
            "chunk-0001.wav": "go home"
        ])
        let session = StreamingAudioTranscriptionSession(transcriber: transcriber)

        await session.enqueue(WavAudioChunk(sequence: 0, url: URL(fileURLWithPath: "/tmp/chunk-0000.wav"), sampleRate: 4, sampleCount: 4))
        await session.enqueue(WavAudioChunk(sequence: 1, url: URL(fileURLWithPath: "/tmp/chunk-0001.wav"), sampleRate: 4, sampleCount: 4))

        let result = await session.finish()

        XCTAssertEqual(result.text, "go go home")
    }

    func testPublishesMergedTextAfterEachSuccessfulChunk() async throws {
        let transcriber = StubAudioTranscriber(outputs: [
            "chunk-0000.wav": "hello",
            "chunk-0001.wav": "world"
        ])
        let updates = TranscriptUpdateRecorder()
        let session = StreamingAudioTranscriptionSession(
            transcriber: transcriber,
            onTranscriptUpdate: { text in
                await updates.record(text)
            }
        )

        await session.enqueue(WavAudioChunk(sequence: 0, url: URL(fileURLWithPath: "/tmp/chunk-0000.wav"), sampleRate: 4, sampleCount: 4))
        await session.enqueue(WavAudioChunk(sequence: 1, url: URL(fileURLWithPath: "/tmp/chunk-0001.wav"), sampleRate: 4, sampleCount: 4))
        _ = await session.finish()
        let publishedUpdates = await updates.values()

        XCTAssertEqual(publishedUpdates, ["hello", "hello world"])
    }

    func testCancelDiscardsQueuedAndInFlightTranscript() async throws {
        let transcriber = SlowStubAudioTranscriber(output: "should not survive")
        let session = StreamingAudioTranscriptionSession(transcriber: transcriber)

        await session.enqueue(WavAudioChunk(sequence: 0, url: URL(fileURLWithPath: "/tmp/chunk-0000.wav"), sampleRate: 16_000, sampleCount: 16_000))
        await session.cancel()

        let result = await session.finish()

        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.chunkCount, 0)
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testStopAndSnapshotKeepsCompletedPreviewWithoutDrainingMoreWork() async throws {
        let transcriber = StubAudioTranscriber(outputs: [
            "chunk-0000.wav": "hello"
        ])
        let session = StreamingAudioTranscriptionSession(transcriber: transcriber)

        await session.enqueue(WavAudioChunk(sequence: 0, url: URL(fileURLWithPath: "/tmp/chunk-0000.wav"), sampleRate: 16_000, sampleCount: 16_000))
        _ = await session.finish()

        let result = await session.stopAndSnapshot()

        XCTAssertEqual(result.text, "hello")
        XCTAssertEqual(result.chunkCount, 1)
        XCTAssertEqual(result.coveredDurationSeconds, 1.0, accuracy: 0.001)
    }

    func testStopAndSnapshotCancelsInFlightWorkAndDropsQueuedChunks() async {
        let transcriber = BlockingAudioTranscriber()
        let session = StreamingAudioTranscriptionSession(transcriber: transcriber)
        await session.enqueue(WavAudioChunk(sequence: 0, url: URL(fileURLWithPath: "/tmp/chunk-0000.wav"), sampleRate: 16_000, sampleCount: 16_000))
        await session.enqueue(WavAudioChunk(sequence: 1, url: URL(fileURLWithPath: "/tmp/chunk-0001.wav"), sampleRate: 16_000, sampleCount: 16_000))
        await transcriber.waitUntilStarted()

        let clock = ContinuousClock()
        let startedAt = clock.now
        let result = await session.stopAndSnapshot()
        let elapsed = startedAt.duration(to: clock.now)
        let invocationCount = await transcriber.invocationCount()

        XCTAssertEqual(result.chunkCount, 0)
        XCTAssertEqual(invocationCount, 1)
        XCTAssertEqual(result.enqueuedChunkCount, 2)
        XCTAssertGreaterThanOrEqual(result.maxQueueDepth, 1)
        XCTAssertLessThan(elapsed, .milliseconds(250))
    }
}

private actor StubAudioTranscriber: AudioFileTranscribing {
    let outputs: [String: String]
    private(set) var prompts: [String?] = []

    init(outputs: [String: String]) {
        self.outputs = outputs
    }

    func transcribe(audioFile: URL, options: AudioTranscriptionOptions) async throws -> String {
        prompts.append(options.initialPrompt)
        guard let output = outputs[audioFile.lastPathComponent] else {
            throw AudioTranscriberError.emptyTranscript
        }
        return output
    }

    func recordedPrompts() -> [String?] {
        prompts
    }
}

private actor BlockingAudioTranscriber: AudioFileTranscribing {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var invocations = 0

    func transcribe(audioFile: URL, options: AudioTranscriptionOptions) async throws -> String {
        invocations += 1
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        try await Task.sleep(for: .seconds(30))
        return audioFile.lastPathComponent
    }

    func waitUntilStarted() async {
        if started {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func invocationCount() -> Int {
        invocations
    }
}

private actor SlowStubAudioTranscriber: AudioFileTranscribing {
    let output: String

    init(output: String) {
        self.output = output
    }

    func transcribe(audioFile: URL, options: AudioTranscriptionOptions) async throws -> String {
        try? await Task.sleep(nanoseconds: 25_000_000)
        return output
    }
}

private actor TranscriptUpdateRecorder {
    private var updates: [String] = []

    func record(_ text: String) {
        updates.append(text)
    }

    func values() -> [String] {
        updates
    }
}
