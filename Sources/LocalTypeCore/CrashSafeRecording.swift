import Foundation

/// The durable state for an in-progress local recording. Checkpoints are
/// individual valid WAV files, so an app or machine failure can lose at most
/// the uncheckpointed tail rather than the complete dictation.
public enum RecordingRecoveryState: String, Codable, Equatable, Sendable {
    case recording
    case interrupted
    case readyForTranscription
    case transcriptionFailed
}

public struct RecordingRecoveryManifest: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var startedAt: Date
    public var updatedAt: Date
    public var lastCheckpointAt: Date?
    public var capturedDurationSeconds: Double
    public var sampleRate: Int
    public var checkpointIntervalSeconds: Double
    public var segmentCount: Int
    public var state: RecordingRecoveryState
    public var reason: String?
    public var continuationOf: String?

    public init(
        id: String,
        startedAt: Date,
        updatedAt: Date,
        lastCheckpointAt: Date? = nil,
        capturedDurationSeconds: Double = 0,
        sampleRate: Int = 0,
        checkpointIntervalSeconds: Double,
        segmentCount: Int = 0,
        state: RecordingRecoveryState = .recording,
        reason: String? = nil,
        continuationOf: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.lastCheckpointAt = lastCheckpointAt
        self.capturedDurationSeconds = capturedDurationSeconds
        self.sampleRate = sampleRate
        self.checkpointIntervalSeconds = checkpointIntervalSeconds
        self.segmentCount = segmentCount
        self.state = state
        self.reason = reason
        self.continuationOf = continuationOf
    }

    public var isRecoverable: Bool {
        switch state {
        case .recording, .interrupted, .readyForTranscription, .transcriptionFailed:
            return true
        }
    }
}

public enum CrashSafeRecordingError: Error, Equatable, Sendable {
    case invalidAudioFrame
    case sampleRateChanged(expected: Int, actual: Int)
    case missingRecording(String)
    case recordingNotActive
    case noCheckpointedAudio
}

/// Owns the small, not-yet-saved audio tail for a single recording. All older
/// audio lives in owner-only WAV checkpoints in `directory`.
public struct CrashSafeRecordingSession {
    public let directory: URL
    public private(set) var manifest: RecordingRecoveryManifest

    private let fileManager: FileManager
    private var pendingSamples: [Float] = []
    private var nextSequence = 0

    fileprivate init(
        directory: URL,
        manifest: RecordingRecoveryManifest,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.manifest = manifest
        self.fileManager = fileManager
        self.nextSequence = manifest.segmentCount
    }

    @discardableResult
    public mutating func append(_ frame: AudioFrame, at date: Date = Date()) throws -> RecordingRecoveryManifest {
        guard manifest.state == .recording else {
            throw CrashSafeRecordingError.recordingNotActive
        }
        guard frame.sampleRate > 0, !frame.samples.isEmpty else {
            throw CrashSafeRecordingError.invalidAudioFrame
        }

        if manifest.sampleRate > 0, manifest.sampleRate != frame.sampleRate {
            throw CrashSafeRecordingError.sampleRateChanged(expected: manifest.sampleRate, actual: frame.sampleRate)
        }
        if manifest.sampleRate == 0 {
            manifest.sampleRate = frame.sampleRate
        }

        pendingSamples.append(contentsOf: frame.samples)
        let checkpointSamples = max(1, Int(manifest.checkpointIntervalSeconds * Double(frame.sampleRate)))
        while pendingSamples.count >= checkpointSamples {
            let samples = Array(pendingSamples.prefix(checkpointSamples))
            pendingSamples.removeFirst(checkpointSamples)
            try persist(samples: samples, sampleRate: frame.sampleRate, at: date)
        }
        manifest.updatedAt = date
        return manifest
    }

    @discardableResult
    public mutating func checkpoint(at date: Date = Date()) throws -> RecordingRecoveryManifest {
        guard manifest.state == .recording else {
            throw CrashSafeRecordingError.recordingNotActive
        }
        if !pendingSamples.isEmpty {
            try flushPending(at: date)
        } else {
            manifest.updatedAt = date
            try persistManifest()
        }
        return manifest
    }

    @discardableResult
    public mutating func seal(
        reason: String = "Recording finished",
        at date: Date = Date()
    ) throws -> RecordingRecoveryManifest {
        _ = try checkpoint(at: date)
        manifest.state = .readyForTranscription
        manifest.reason = reason
        manifest.updatedAt = date
        try persistManifest()
        return manifest
    }

    private mutating func flushPending(at date: Date) throws {
        guard !pendingSamples.isEmpty else {
            return
        }
        let samples = pendingSamples
        pendingSamples.removeAll(keepingCapacity: false)
        try persist(samples: samples, sampleRate: manifest.sampleRate, at: date)
    }

    private mutating func persist(samples: [Float], sampleRate: Int, at date: Date) throws {
        try OwnerOnlyFileSecurity.prepareDirectory(directory, fileManager: fileManager)
        let filename = String(format: "segment-%06d.wav", nextSequence)
        let url = directory.appendingPathComponent(filename, isDirectory: false)
        try WavFileWriter.writeMonoPCM16(samples: samples, sampleRate: sampleRate, to: url)
        nextSequence += 1
        manifest.segmentCount = nextSequence
        manifest.capturedDurationSeconds += Double(samples.count) / Double(sampleRate)
        manifest.lastCheckpointAt = date
        manifest.updatedAt = date
        try persistManifest()
    }

    private func persistManifest() throws {
        let url = directory.appendingPathComponent("manifest.json", isDirectory: false)
        let data = try JSONEncoder.recovery.encode(manifest)
        try data.write(to: url, options: [.atomic])
        try OwnerOnlyFileSecurity.protectFile(url, fileManager: fileManager)
    }
}

/// Lists, repairs, merges, and deletes durable recording checkpoints. Keeping
/// this store separate from the UI makes recovery available as soon as the app
/// launches, before audio/transcription services have warmed up.
public struct CrashSafeRecordingStore {
    public let directory: URL
    public let checkpointIntervalSeconds: Double

    private let fileManager: FileManager

    public init(
        directory: URL,
        checkpointIntervalSeconds: Double = 3,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.checkpointIntervalSeconds = max(1, checkpointIntervalSeconds)
        self.fileManager = fileManager
    }

    public func begin(
        id: String = UUID().uuidString,
        at date: Date = Date(),
        continuationOf: String? = nil
    ) throws -> CrashSafeRecordingSession {
        try OwnerOnlyFileSecurity.prepareDirectory(directory, fileManager: fileManager)
        let recordingDirectory = directory.appendingPathComponent(id, isDirectory: true)
        try OwnerOnlyFileSecurity.prepareDirectory(recordingDirectory, fileManager: fileManager)
        let manifest = RecordingRecoveryManifest(
            id: id,
            startedAt: date,
            updatedAt: date,
            checkpointIntervalSeconds: checkpointIntervalSeconds,
            continuationOf: continuationOf
        )
        var session = CrashSafeRecordingSession(directory: recordingDirectory, manifest: manifest, fileManager: fileManager)
        _ = try session.checkpointPlaceholder(at: date)
        return session
    }

    public func recoverableRecordings() throws -> [RecordingRecoveryManifest] {
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }
        let directories = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try directories.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return try manifest(at: url)
        }
        .filter(\.isRecoverable)
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Any `recording` manifest found during a new launch has necessarily been
    /// interrupted. Mark it explicitly so it never appears to have stopped
    /// silently.
    @discardableResult
    public func markActiveRecordingsInterrupted(at date: Date = Date()) throws -> [RecordingRecoveryManifest] {
        let recordings = try recoverableRecordings()
        return try recordings.map { recording in
            guard recording.state == .recording else {
                return recording
            }
            return try update(
                id: recording.id,
                state: .interrupted,
                reason: "QuietType closed before this recording was finished.",
                at: date
            )
        }
    }

    @discardableResult
    public func update(
        id: String,
        state: RecordingRecoveryState,
        reason: String? = nil,
        at date: Date = Date()
    ) throws -> RecordingRecoveryManifest {
        let recordingDirectory = directory.appendingPathComponent(id, isDirectory: true)
        var manifest = try manifest(at: recordingDirectory)
        manifest.state = state
        manifest.reason = reason
        manifest.updatedAt = date
        try write(manifest, in: recordingDirectory)
        return manifest
    }

    public func mergeRecording(id: String, to url: URL) throws -> RecordingRecoveryManifest {
        let recordingDirectory = directory.appendingPathComponent(id, isDirectory: true)
        let manifest = try manifest(at: recordingDirectory)
        let files = try segmentURLs(in: recordingDirectory)
        guard !files.isEmpty, manifest.sampleRate > 0 else {
            throw CrashSafeRecordingError.noCheckpointedAudio
        }
        try WavFileWriter.mergeMonoPCM16(files: files, sampleRate: manifest.sampleRate, to: url, fileManager: fileManager)
        return manifest
    }

    public func discard(id: String) throws {
        let recordingDirectory = directory.appendingPathComponent(id, isDirectory: true)
        guard fileManager.fileExists(atPath: recordingDirectory.path) else {
            throw CrashSafeRecordingError.missingRecording(id)
        }
        try fileManager.removeItem(at: recordingDirectory)
    }

    private func manifest(at recordingDirectory: URL) throws -> RecordingRecoveryManifest {
        let manifestURL = recordingDirectory.appendingPathComponent("manifest.json", isDirectory: false)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw CrashSafeRecordingError.missingRecording(recordingDirectory.lastPathComponent)
        }
        var manifest = try JSONDecoder.recovery.decode(RecordingRecoveryManifest.self, from: Data(contentsOf: manifestURL))
        let files = try segmentURLs(in: recordingDirectory)
        if files.count > manifest.segmentCount {
            manifest.segmentCount = files.count
            manifest.capturedDurationSeconds = try recoveredDuration(files: files, sampleRate: manifest.sampleRate)
            manifest.lastCheckpointAt = manifest.updatedAt
            try write(manifest, in: recordingDirectory)
        }
        return manifest
    }

    private func segmentURLs(in recordingDirectory: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: recordingDirectory.path) else {
            throw CrashSafeRecordingError.missingRecording(recordingDirectory.lastPathComponent)
        }
        return try fileManager.contentsOfDirectory(
            at: recordingDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "wav" && $0.lastPathComponent.hasPrefix("segment-") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func recoveredDuration(files: [URL], sampleRate: Int) throws -> Double {
        guard sampleRate > 0 else {
            return 0
        }
        return try files.reduce(0) { duration, url in
            let data = try Data(contentsOf: url)
            return duration + Double(max(data.count - 44, 0) / 2) / Double(sampleRate)
        }
    }

    private func write(_ manifest: RecordingRecoveryManifest, in directory: URL) throws {
        let url = directory.appendingPathComponent("manifest.json", isDirectory: false)
        let data = try JSONEncoder.recovery.encode(manifest)
        try data.write(to: url, options: [.atomic])
        try OwnerOnlyFileSecurity.protectFile(url, fileManager: fileManager)
    }
}

private extension CrashSafeRecordingSession {
    /// Creates the first durable manifest before any audio arrives.
    mutating func checkpointPlaceholder(at date: Date) throws -> RecordingRecoveryManifest {
        manifest.updatedAt = date
        let url = directory.appendingPathComponent("manifest.json", isDirectory: false)
        let data = try JSONEncoder.recovery.encode(manifest)
        try data.write(to: url, options: [.atomic])
        try OwnerOnlyFileSecurity.protectFile(url, fileManager: fileManager)
        return manifest
    }
}

private extension JSONEncoder {
    static let recovery: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let recovery: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
