import Foundation

public enum VoiceFlowOutcome: String, Codable, Equatable, Sendable {
    case inserted
    case readyToCopy
    case cancelled
    case noAudio
    case signalTooLow
    case transcriptionFailed
}

/// Content-free measurements for local voice-flow evaluation. Deliberately
/// excludes transcript text, audio paths, app context, and filenames.
public struct VoiceFlowMetricRecord: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var sessionID: UUID
    public var startedAt: Date
    public var recordingDurationMS: Int
    public var audioFrameCount: Int
    public var speechSegmentCount: Int
    public var activeSpeechDurationMS: Int
    public var longestPauseMS: Int
    public var emittedChunkCount: Int
    public var streamingEnqueuedChunkCount: Int
    public var streamingCompletedChunkCount: Int
    public var maxStreamingQueueDepth: Int
    public var firstPartialASRMS: Int?
    public var partialUpdateCount: Int
    public var previewRevisionCount: Int
    public var releaseToFinalTranscriptMS: Int?
    public var releaseToCompletionMS: Int?
    public var finalWordCount: Int
    public var outcome: VoiceFlowOutcome

    public init(
        schemaVersion: Int = 1,
        sessionID: UUID,
        startedAt: Date,
        recordingDurationMS: Int,
        audioFrameCount: Int,
        speechSegmentCount: Int,
        activeSpeechDurationMS: Int,
        longestPauseMS: Int,
        emittedChunkCount: Int,
        streamingEnqueuedChunkCount: Int,
        streamingCompletedChunkCount: Int,
        maxStreamingQueueDepth: Int,
        firstPartialASRMS: Int?,
        partialUpdateCount: Int,
        previewRevisionCount: Int,
        releaseToFinalTranscriptMS: Int?,
        releaseToCompletionMS: Int?,
        finalWordCount: Int,
        outcome: VoiceFlowOutcome
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.recordingDurationMS = recordingDurationMS
        self.audioFrameCount = audioFrameCount
        self.speechSegmentCount = speechSegmentCount
        self.activeSpeechDurationMS = activeSpeechDurationMS
        self.longestPauseMS = longestPauseMS
        self.emittedChunkCount = emittedChunkCount
        self.streamingEnqueuedChunkCount = streamingEnqueuedChunkCount
        self.streamingCompletedChunkCount = streamingCompletedChunkCount
        self.maxStreamingQueueDepth = maxStreamingQueueDepth
        self.firstPartialASRMS = firstPartialASRMS
        self.partialUpdateCount = partialUpdateCount
        self.previewRevisionCount = previewRevisionCount
        self.releaseToFinalTranscriptMS = releaseToFinalTranscriptMS
        self.releaseToCompletionMS = releaseToCompletionMS
        self.finalWordCount = finalWordCount
        self.outcome = outcome
    }
}

public struct VoiceFlowMetricAccumulator: Sendable {
    public let sessionID: UUID
    public let startedAt: Date

    private var audioFrameCount = 0
    private var speechSegmentCount = 0
    private var activeSpeechDurationMS = 0
    private var longestPauseMS = 0
    private var currentPauseMS = 0
    private var hasDetectedSpeech = false
    private var emittedChunkCount = 0
    private var streamingEnqueuedChunkCount = 0
    private var streamingCompletedChunkCount = 0
    private var maxStreamingQueueDepth = 0
    private var firstPartialASRMS: Int?
    private var partialUpdateCount = 0
    private var previewRevisionCount = 0
    private var previousPartialWords: [String] = []
    private var releasedAt: Date?
    private var recordingDurationMS = 0
    private var releaseToFinalTranscriptMS: Int?

    public init(sessionID: UUID = UUID(), startedAt: Date = Date()) {
        self.sessionID = sessionID
        self.startedAt = startedAt
    }

    public mutating func recordAudioFrame(activity: SpeechActivityUpdate) {
        audioFrameCount += 1
        if activity.didStartSpeech {
            speechSegmentCount += 1
            hasDetectedSpeech = true
            currentPauseMS = 0
        }
        if activity.state == .speech {
            activeSpeechDurationMS += activity.frameDurationMS
            currentPauseMS = 0
        } else if hasDetectedSpeech {
            currentPauseMS += activity.frameDurationMS
            longestPauseMS = max(longestPauseMS, currentPauseMS)
        }
    }

    public mutating func recordEmittedChunks(total: Int) {
        emittedChunkCount = max(emittedChunkCount, max(0, total))
    }

    public mutating func recordStreamingDiagnostics(
        enqueuedChunkCount: Int,
        completedChunkCount: Int,
        maxQueueDepth: Int
    ) {
        streamingEnqueuedChunkCount = max(streamingEnqueuedChunkCount, max(0, enqueuedChunkCount))
        streamingCompletedChunkCount = max(streamingCompletedChunkCount, max(0, completedChunkCount))
        maxStreamingQueueDepth = max(maxStreamingQueueDepth, max(0, maxQueueDepth))
    }

    public mutating func recordPartialTranscript(_ partial: String, at date: Date = Date()) {
        let words = Self.normalizedWords(partial)
        guard !words.isEmpty, words != previousPartialWords else {
            return
        }

        if firstPartialASRMS == nil {
            firstPartialASRMS = Self.elapsedMS(from: startedAt, to: date)
        }
        partialUpdateCount += 1
        if !previousPartialWords.isEmpty,
           !words.starts(with: previousPartialWords) {
            previewRevisionCount += 1
        }
        previousPartialWords = words
    }

    public mutating func markReleased(at date: Date = Date(), recordingDuration: TimeInterval) {
        releasedAt = date
        recordingDurationMS = max(0, Int((recordingDuration * 1_000).rounded()))
    }

    public mutating func markFinalTranscript(at date: Date = Date()) {
        guard let releasedAt else {
            return
        }
        releaseToFinalTranscriptMS = Self.elapsedMS(from: releasedAt, to: date)
    }

    public func finish(
        outcome: VoiceFlowOutcome,
        finalWordCount: Int = 0,
        at date: Date = Date()
    ) -> VoiceFlowMetricRecord {
        let completionMS = releasedAt.map { Self.elapsedMS(from: $0, to: date) }
        return VoiceFlowMetricRecord(
            sessionID: sessionID,
            startedAt: startedAt,
            recordingDurationMS: recordingDurationMS,
            audioFrameCount: audioFrameCount,
            speechSegmentCount: speechSegmentCount,
            activeSpeechDurationMS: activeSpeechDurationMS,
            longestPauseMS: longestPauseMS,
            emittedChunkCount: emittedChunkCount,
            streamingEnqueuedChunkCount: streamingEnqueuedChunkCount,
            streamingCompletedChunkCount: streamingCompletedChunkCount,
            maxStreamingQueueDepth: maxStreamingQueueDepth,
            firstPartialASRMS: firstPartialASRMS,
            partialUpdateCount: partialUpdateCount,
            previewRevisionCount: previewRevisionCount,
            releaseToFinalTranscriptMS: releaseToFinalTranscriptMS,
            releaseToCompletionMS: completionMS,
            finalWordCount: max(0, finalWordCount),
            outcome: outcome
        )
    }

    private static func normalizedWords(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map { word in
                word.unicodeScalars
                    .filter { CharacterSet.alphanumerics.contains($0) }
                    .map(String.init)
                    .joined()
            }
            .filter { !$0.isEmpty }
    }

    private static func elapsedMS(from start: Date, to end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) * 1_000).rounded()))
    }
}

public actor LocalVoiceFlowMetricsStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func append(_ record: VoiceFlowMetricRecord) throws {
        let fileManager = FileManager.default
        try OwnerOnlyFileSecurity.prepareDirectory(fileURL.deletingLastPathComponent(), fileManager: fileManager)
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(record)
        data.append(0x0A)

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try OwnerOnlyFileSecurity.protectFile(fileURL, fileManager: fileManager)
    }
}
