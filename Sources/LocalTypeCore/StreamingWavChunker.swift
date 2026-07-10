import Foundation

public struct WavAudioChunk: Codable, Equatable, Sendable {
    public var sequence: Int
    public var url: URL
    public var sampleRate: Int
    public var sampleCount: Int
    /// Audio not already represented by the preceding chunk.
    public var coveredSampleCount: Int

    public init(
        sequence: Int,
        url: URL,
        sampleRate: Int,
        sampleCount: Int,
        coveredSampleCount: Int? = nil
    ) {
        self.sequence = sequence
        self.url = url
        self.sampleRate = sampleRate
        self.sampleCount = sampleCount
        self.coveredSampleCount = min(max(coveredSampleCount ?? sampleCount, 0), sampleCount)
    }

    public var durationSeconds: Double {
        Double(sampleCount) / Double(sampleRate)
    }

    public var coveredDurationSeconds: Double {
        Double(coveredSampleCount) / Double(sampleRate)
    }
}

public struct StreamingWavChunker: Sendable {
    private var pendingSamples: [Float] = []
    private var sequence = 0
    private var totalSamples = 0
    private var activeSampleRate: Int

    public let chunkDurationSeconds: Double
    public let overlapDurationSeconds: Double
    public let maxDurationSeconds: Double

    public init(
        sampleRate: Int = 16_000,
        chunkDurationSeconds: Double = 1.0,
        overlapDurationSeconds: Double = 0,
        maxDurationSeconds: Double = 60.0
    ) {
        self.activeSampleRate = sampleRate
        self.chunkDurationSeconds = chunkDurationSeconds
        self.overlapDurationSeconds = overlapDurationSeconds
        self.maxDurationSeconds = maxDurationSeconds
    }

    public var totalDurationSeconds: Double {
        Double(totalSamples) / Double(activeSampleRate)
    }

    public var reachedMaxDuration: Bool {
        totalDurationSeconds >= maxDurationSeconds
    }

    public mutating func append(_ frame: AudioFrame, outputDirectory: URL) throws -> [WavAudioChunk] {
        activeSampleRate = frame.sampleRate
        pendingSamples.append(contentsOf: frame.samples)
        totalSamples += frame.samples.count

        try OwnerOnlyFileSecurity.prepareDirectory(outputDirectory)

        var chunks: [WavAudioChunk] = []
        let chunkSampleCount = max(1, Int(Double(activeSampleRate) * chunkDurationSeconds))
        let overlapSampleCount = min(
            chunkSampleCount - 1,
            max(0, Int(Double(activeSampleRate) * overlapDurationSeconds))
        )
        let strideSampleCount = chunkSampleCount - overlapSampleCount

        while pendingSamples.count >= chunkSampleCount {
            let samples = Array(pendingSamples.prefix(chunkSampleCount))

            let url = outputDirectory.appendingPathComponent(String(format: "chunk-%04d.wav", sequence))
            try WavFileWriter.writeMonoPCM16(samples: samples, sampleRate: activeSampleRate, to: url)
            let coveredSampleCount = sequence == 0 ? samples.count : strideSampleCount
            chunks.append(
                WavAudioChunk(
                    sequence: sequence,
                    url: url,
                    sampleRate: activeSampleRate,
                    sampleCount: samples.count,
                    coveredSampleCount: coveredSampleCount
                )
            )
            sequence += 1
            pendingSamples.removeFirst(strideSampleCount)
        }

        return chunks
    }

    public mutating func flush(outputDirectory: URL) throws -> WavAudioChunk? {
        guard !pendingSamples.isEmpty else {
            return nil
        }

        try OwnerOnlyFileSecurity.prepareDirectory(outputDirectory)
        let samples = pendingSamples
        pendingSamples = []

        let overlapSampleCount = min(
            max(0, Int(Double(activeSampleRate) * overlapDurationSeconds)),
            samples.count
        )
        let coveredSampleCount = sequence == 0 ? samples.count : samples.count - overlapSampleCount
        guard coveredSampleCount > 0 else {
            return nil
        }

        let url = outputDirectory.appendingPathComponent(String(format: "chunk-%04d-final.wav", sequence))
        try WavFileWriter.writeMonoPCM16(samples: samples, sampleRate: activeSampleRate, to: url)
        let chunk = WavAudioChunk(
            sequence: sequence,
            url: url,
            sampleRate: activeSampleRate,
            sampleCount: samples.count,
            coveredSampleCount: coveredSampleCount
        )
        sequence += 1
        return chunk
    }
}
