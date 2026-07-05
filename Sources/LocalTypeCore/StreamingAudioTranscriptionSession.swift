import Foundation

public actor StreamingAudioTranscriptionSession {
    private let transcriber: AudioFileTranscribing
    private let options: AudioTranscriptionOptions
    private var queue: [WavAudioChunk] = []
    private var transcripts: [Int: String] = [:]
    private var errors: [String] = []
    private var isProcessing = false

    public init(transcriber: AudioFileTranscribing, options: AudioTranscriptionOptions = .none) {
        self.transcriber = transcriber
        self.options = options
    }

    public func enqueue(_ chunk: WavAudioChunk) {
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
            errors: errors
        )
    }

    private func processQueue() async {
        while !queue.isEmpty {
            let chunk = queue.removeFirst()
            do {
                let text = try await transcriber.transcribe(audioFile: chunk.url, options: options)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    transcripts[chunk.sequence] = trimmed
                }
            } catch {
                errors.append("chunk \(chunk.sequence): \(String(describing: error))")
            }
        }

        isProcessing = false
        if !queue.isEmpty {
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
    public var errors: [String]

    public init(text: String, chunkCount: Int, errors: [String]) {
        self.text = text
        self.chunkCount = chunkCount
        self.errors = errors
    }
}
