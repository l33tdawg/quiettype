import Foundation

/// Builds non-overlapping transcription segments and cuts only after a real
/// speech-to-silence transition. The complete recording remains authoritative
/// and can be used whenever the incremental result fails its integrity checks.
public struct PauseAlignedWavSegmenter: Sendable {
    private var pendingSamples: [Float] = []
    private var sequence = 0
    private var activeSampleRate: Int

    public let minimumSegmentDurationSeconds: Double

    public init(
        sampleRate: Int = 16_000,
        minimumSegmentDurationSeconds: Double = 12.0
    ) {
        self.activeSampleRate = max(1, sampleRate)
        self.minimumSegmentDurationSeconds = max(1, minimumSegmentDurationSeconds)
    }

    public var pendingDurationSeconds: Double {
        Double(pendingSamples.count) / Double(activeSampleRate)
    }

    public mutating func append(
        _ frame: AudioFrame,
        activity: SpeechActivityUpdate,
        outputDirectory: URL
    ) throws -> WavAudioChunk? {
        activeSampleRate = max(1, frame.sampleRate)
        pendingSamples.append(contentsOf: frame.samples)

        guard activity.didEndSpeech,
              pendingDurationSeconds >= minimumSegmentDurationSeconds else {
            return nil
        }
        return try emitPending(outputDirectory: outputDirectory, isFinal: false)
    }

    public mutating func flush(outputDirectory: URL) throws -> WavAudioChunk? {
        try emitPending(outputDirectory: outputDirectory, isFinal: true)
    }

    private mutating func emitPending(outputDirectory: URL, isFinal: Bool) throws -> WavAudioChunk? {
        guard !pendingSamples.isEmpty else {
            return nil
        }

        try OwnerOnlyFileSecurity.prepareDirectory(outputDirectory)
        let suffix = isFinal ? "-final" : ""
        let url = outputDirectory.appendingPathComponent(
            String(format: "segment-%04d%@.wav", sequence, suffix)
        )
        let samples = pendingSamples
        try WavFileWriter.writeMonoPCM16(samples: samples, sampleRate: activeSampleRate, to: url)
        pendingSamples.removeAll(keepingCapacity: true)

        let chunk = WavAudioChunk(
            sequence: sequence,
            url: url,
            sampleRate: activeSampleRate,
            sampleCount: samples.count
        )
        sequence += 1
        return chunk
    }
}
