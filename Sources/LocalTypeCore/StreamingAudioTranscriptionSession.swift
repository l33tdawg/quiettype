import Foundation

public actor StreamingAudioTranscriptionSession {
    public typealias TranscriptUpdateHandler = @Sendable (String) async -> Void

    private let transcriber: AudioFileTranscribing
    private let options: AudioTranscriptionOptions
    private let onTranscriptUpdate: TranscriptUpdateHandler?
    private var queue: [WavAudioChunk] = []
    private var transcripts: [Int: String] = [:]
    private var transcriptDurations: [Int: Double] = [:]
    private var transcriptHasOverlap: [Int: Bool] = [:]
    private var errors: [String] = []
    private var isProcessing = false
    private var isCancelled = false
    private var processingTask: Task<Void, Never>?
    private var enqueuedChunkCount = 0
    private var maxQueueDepth = 0

    public init(
        transcriber: AudioFileTranscribing,
        options: AudioTranscriptionOptions = .none,
        onTranscriptUpdate: TranscriptUpdateHandler? = nil
    ) {
        self.transcriber = transcriber
        self.options = options
        self.onTranscriptUpdate = onTranscriptUpdate
    }

    public func enqueue(_ chunk: WavAudioChunk) {
        guard !isCancelled else {
            return
        }

        queue.append(chunk)
        enqueuedChunkCount += 1
        maxQueueDepth = max(maxQueueDepth, queue.count)
        guard !isProcessing else {
            return
        }

        isProcessing = true
        processingTask = Task {
            await processQueue()
        }
    }

    public func finish() async -> StreamingTranscriptionResult {
        while isProcessing || !queue.isEmpty {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        return currentResult()
    }

    /// Stops queued/in-flight preview work and returns only chunks that already
    /// completed. The full-audio finalizer can then start immediately instead of
    /// waiting for advisory streaming work to drain.
    public func stopAndSnapshot() -> StreamingTranscriptionResult {
        isCancelled = true
        queue.removeAll(keepingCapacity: false)
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        return currentResult()
    }

    public func latestTranscript() -> String {
        mergedTranscript()
    }

    public func cancel() {
        isCancelled = true
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        queue.removeAll(keepingCapacity: false)
        transcripts.removeAll(keepingCapacity: false)
        transcriptDurations.removeAll(keepingCapacity: false)
        transcriptHasOverlap.removeAll(keepingCapacity: false)
        errors.removeAll(keepingCapacity: false)
    }

    private func processQueue() async {
        while !queue.isEmpty && !isCancelled && !Task.isCancelled {
            let chunk = queue.removeFirst()
            do {
                let text = try await transcriber.transcribe(audioFile: chunk.url, options: options)
                guard !isCancelled else {
                    continue
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    transcripts[chunk.sequence] = trimmed
                    transcriptDurations[chunk.sequence] = chunk.coveredDurationSeconds
                    transcriptHasOverlap[chunk.sequence] = chunk.coveredSampleCount < chunk.sampleCount
                    await onTranscriptUpdate?(mergedTranscript())
                }
            } catch {
                if !isCancelled && !Task.isCancelled {
                    errors.append("chunk \(chunk.sequence): \(String(describing: error))")
                }
            }
        }

        isProcessing = false
        processingTask = nil
        if !queue.isEmpty && !isCancelled {
            enqueuePlaceholderPump()
        }
    }

    private func enqueuePlaceholderPump() {
        guard !isProcessing else {
            return
        }
        isProcessing = true
        processingTask = Task {
            await processQueue()
        }
    }

    private func currentResult() -> StreamingTranscriptionResult {
        StreamingTranscriptionResult(
            text: mergedTranscript(),
            chunkCount: transcripts.count,
            coveredDurationSeconds: transcriptDurations.values.reduce(0, +),
            errors: errors,
            enqueuedChunkCount: enqueuedChunkCount,
            maxQueueDepth: maxQueueDepth
        )
    }

    private func mergedTranscript() -> String {
        let orderedTranscripts: [(text: String, hasOverlap: Bool)] = transcripts
            .keys
            .sorted()
            .compactMap { sequence -> (text: String, hasOverlap: Bool)? in
                guard let text = transcripts[sequence] else {
                    return nil
                }
                return (text: text, hasOverlap: transcriptHasOverlap[sequence] ?? false)
            }

        return Self.mergeOverlappingTranscripts(orderedTranscripts)
    }

    static func mergeOverlappingTranscripts(_ transcripts: [(text: String, hasOverlap: Bool)]) -> String {
        transcripts.reduce("") { merged, chunk in
            let trimmedNext = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedNext.isEmpty else {
                return merged
            }
            guard !merged.isEmpty else {
                return trimmedNext
            }
            guard chunk.hasOverlap else {
                return "\(merged) \(trimmedNext)"
            }

            let existingWords = merged.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let nextWords = trimmedNext.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let maximumOverlap = min(12, existingWords.count, nextWords.count)
            var overlapCount = 0

            if maximumOverlap > 0 {
                for count in stride(from: maximumOverlap, through: 1, by: -1) {
                    let existingSuffix = existingWords.suffix(count).map(Self.normalizedWord)
                    let nextPrefix = nextWords.prefix(count).map(Self.normalizedWord)
                    if existingSuffix == nextPrefix, !existingSuffix.allSatisfy({ $0.isEmpty }) {
                        overlapCount = count
                        break
                    }
                }
            }

            let suffix = nextWords.dropFirst(overlapCount).joined(separator: " ")
            return suffix.isEmpty ? merged : "\(merged) \(suffix)"
        }
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedWord(_ word: String) -> String {
        word.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
}

public struct StreamingTranscriptionResult: Equatable, Sendable {
    public var text: String
    public var chunkCount: Int
    public var coveredDurationSeconds: Double
    public var errors: [String]
    public var enqueuedChunkCount: Int
    public var maxQueueDepth: Int

    public init(
        text: String,
        chunkCount: Int,
        coveredDurationSeconds: Double = 0,
        errors: [String],
        enqueuedChunkCount: Int = 0,
        maxQueueDepth: Int = 0
    ) {
        self.text = text
        self.chunkCount = chunkCount
        self.coveredDurationSeconds = coveredDurationSeconds
        self.errors = errors
        self.enqueuedChunkCount = enqueuedChunkCount
        self.maxQueueDepth = maxQueueDepth
    }
}
