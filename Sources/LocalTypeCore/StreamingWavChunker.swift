import Foundation

public struct WavAudioChunk: Codable, Equatable, Sendable {
    public var sequence: Int
    public var url: URL
    public var sampleRate: Int
    public var sampleCount: Int

    public var durationSeconds: Double {
        Double(sampleCount) / Double(sampleRate)
    }
}

public struct StreamingWavChunker: Sendable {
    private var pendingSamples: [Float] = []
    private var sequence = 0
    private var totalSamples = 0
    private var activeSampleRate: Int

    public let chunkDurationSeconds: Double
    public let maxDurationSeconds: Double

    public init(
        sampleRate: Int = 16_000,
        chunkDurationSeconds: Double = 1.0,
        maxDurationSeconds: Double = 60.0
    ) {
        self.activeSampleRate = sampleRate
        self.chunkDurationSeconds = chunkDurationSeconds
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

        while pendingSamples.count >= chunkSampleCount {
            let samples = Array(pendingSamples.prefix(chunkSampleCount))
            pendingSamples.removeFirst(chunkSampleCount)

            let url = outputDirectory.appendingPathComponent(String(format: "chunk-%04d.wav", sequence))
            try WavFileWriter.writeMonoPCM16(samples: samples, sampleRate: activeSampleRate, to: url)
            chunks.append(WavAudioChunk(sequence: sequence, url: url, sampleRate: activeSampleRate, sampleCount: samples.count))
            sequence += 1
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

        let url = outputDirectory.appendingPathComponent(String(format: "chunk-%04d-final.wav", sequence))
        try WavFileWriter.writeMonoPCM16(samples: samples, sampleRate: activeSampleRate, to: url)
        let chunk = WavAudioChunk(sequence: sequence, url: url, sampleRate: activeSampleRate, sampleCount: samples.count)
        sequence += 1
        return chunk
    }
}
