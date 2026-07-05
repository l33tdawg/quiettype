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
        XCTAssertTrue(result.errors.isEmpty)
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
