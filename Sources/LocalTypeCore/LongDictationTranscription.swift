import Foundation

public enum LongDictationTranscription {
    public static let activationDurationSeconds = 45.0
    public static let chunkDurationSeconds = 28.0
    public static let overlapDurationSeconds = 2.0
    public static let tailRescueDurationSeconds = 8.0

    public static func requiresChunkedRecovery(sampleCount: Int, sampleRate: Int) -> Bool {
        guard sampleCount > 0, sampleRate > 0 else {
            return false
        }
        return Double(sampleCount) / Double(sampleRate) >= activationDurationSeconds
    }

    public static func makeChunks(
        samples: [Float],
        sampleRate: Int,
        outputDirectory: URL
    ) throws -> [WavAudioChunk] {
        var chunker = StreamingWavChunker(
            sampleRate: sampleRate,
            chunkDurationSeconds: chunkDurationSeconds,
            overlapDurationSeconds: overlapDurationSeconds,
            maxDurationSeconds: .greatestFiniteMagnitude
        )
        var chunks = try chunker.append(
            AudioFrame(samples: samples, sampleRate: sampleRate, timestamp: 0),
            outputDirectory: outputDirectory
        )
        if let finalChunk = try chunker.flush(outputDirectory: outputDirectory) {
            chunks.append(finalChunk)
        }
        return chunks
    }

    public static func makeTailRescueChunk(
        samples: [Float],
        sampleRate: Int,
        sequence: Int,
        outputDirectory: URL
    ) throws -> WavAudioChunk? {
        let rescueSampleCount = min(samples.count, Int(Double(sampleRate) * tailRescueDurationSeconds))
        guard rescueSampleCount > 0 else {
            return nil
        }
        let tail = Array(samples.suffix(rescueSampleCount))
        let rms = sqrt(
            tail.reduce(0.0) { partial, sample in
                partial + Double(sample * sample)
            } / Double(rescueSampleCount)
        )
        guard rms >= 0.002 else {
            return nil
        }

        try OwnerOnlyFileSecurity.prepareDirectory(outputDirectory)
        let url = outputDirectory.appendingPathComponent("chunk-tail-rescue.wav")
        try WavFileWriter.writeMonoPCM16(samples: tail, sampleRate: sampleRate, to: url)
        return WavAudioChunk(
            sequence: sequence,
            url: url,
            sampleRate: sampleRate,
            sampleCount: tail.count,
            coveredSampleCount: 0
        )
    }

    public static func isComplete(
        _ result: StreamingTranscriptionResult,
        expectedDurationSeconds: Double
    ) -> Bool {
        let coverageDelta = abs(result.coveredDurationSeconds - expectedDurationSeconds)
        return result.enqueuedChunkCount >= 2
            && result.chunkCount == result.enqueuedChunkCount
            && result.errors.isEmpty
            && coverageDelta <= 0.25
            && !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
