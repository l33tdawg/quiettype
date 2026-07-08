import Foundation

public actor StreamingAudioTranscriptionSession {
    private let transcriber: AudioFileTranscribing
    private let options: AudioTranscriptionOptions
    private var queue: [WavAudioChunk] = []
    private var transcripts: [Int: String] = [:]
    private var transcriptDurations: [Int: Double] = [:]
    private var errors: [String] = []
    private var isProcessing = false
    private var isCancelled = false

    public init(transcriber: AudioFileTranscribing, options: AudioTranscriptionOptions = .none) {
        self.transcriber = transcriber
        self.options = options
    }

    public func enqueue(_ chunk: WavAudioChunk) {
        guard !isCancelled else {
            return
        }

        queue.append(chunk)
        guard !isProcessing else {
            return
        }

        isProcessing = true
        Task {
            await processQueue()
        }
    }

    public func finish() async -> StreamingTranscriptionResult {
        while isProcessing || !queue.isEmpty {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        return StreamingTranscriptionResult(
            text: mergedTranscript(),
            chunkCount: transcripts.count,
            coveredDurationSeconds: transcriptDurations.values.reduce(0, +),
            errors: errors
        )
    }

    public func cancel() {
        isCancelled = true
        queue.removeAll(keepingCapacity: false)
        transcripts.removeAll(keepingCapacity: false)
        transcriptDurations.removeAll(keepingCapacity: false)
        errors.removeAll(keepingCapacity: false)
    }

    private func processQueue() async {
        while !queue.isEmpty && !isCancelled {
            let chunk = queue.removeFirst()
            do {
                let text = try await transcriber.transcribe(audioFile: chunk.url, options: options)
                guard !isCancelled else {
                    continue
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    transcripts[chunk.sequence] = trimmed
                    transcriptDurations[chunk.sequence] = chunk.durationSeconds
                }
            } catch {
                if !isCancelled {
                    errors.append("chunk \(chunk.sequence): \(String(describing: error))")
                }
            }
        }

        isProcessing = false
        if !queue.isEmpty && !isCancelled {
            enqueuePlaceholderPump()
        }
    }

    private func enqueuePlaceholderPump() {
        guard !isProcessing else {
            return
        }
        isProcessing = true
        Task {
            await processQueue()
        }
    }

    private func mergedTranscript() -> String {
        transcripts
            .keys
            .sorted()
            .compactMap { transcripts[$0] }
            .joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct StreamingTranscriptionResult: Equatable, Sendable {
    public var text: String
    public var chunkCount: Int
    public var coveredDurationSeconds: Double
    public var errors: [String]

    public init(text: String, chunkCount: Int, coveredDurationSeconds: Double = 0, errors: [String]) {
        self.text = text
        self.chunkCount = chunkCount
        self.coveredDurationSeconds = coveredDurationSeconds
        self.errors = errors
    }
}
