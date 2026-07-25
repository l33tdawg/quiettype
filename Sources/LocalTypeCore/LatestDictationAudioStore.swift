import Foundation

/// One owner-only local recording and its optional diagnostic text. These are
/// never synced or sent unless the person explicitly chooses one in a bug
/// report email.
public struct RecentDictationDiagnostic: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var createdAt: Date
    public var audioFilename: String
    public var transcript: String
    public var output: String
    public var error: String?
    public var status: String

    public init(
        id: String,
        createdAt: Date,
        audioFilename: String,
        transcript: String = "",
        output: String = "",
        error: String? = nil,
        status: String = "Captured locally"
    ) {
        self.id = id
        self.createdAt = createdAt
        self.audioFilename = audioFilename
        self.transcript = transcript
        self.output = output
        self.error = error
        self.status = status
    }
}

/// Retains a rolling, owner-only local history for diagnostic reports. Audio
/// files and their optional text metadata stay on this Mac until the user
/// explicitly selects a sample for an email draft.
public struct LatestDictationAudioStore: Sendable {
    public let directory: URL
    public let maxSamples: Int

    private let manifestFilename = "RecentDictations.json"
    private let legacyFilename = "LastDictation.wav"

    public init(directory: URL, maxSamples: Int = 3) {
        self.directory = directory
        self.maxSamples = max(1, maxSamples)
    }

    /// Compatibility accessor for callers that only need the newest retained
    /// recording.
    public var retainedAudioURL: URL {
        if let sample = try? samples().first {
            return audioURL(for: sample)
        }
        return directory.appendingPathComponent(legacyFilename, isDirectory: false)
    }

    public func samples(fileManager: FileManager = .default) throws -> [RecentDictationDiagnostic] {
        try OwnerOnlyFileSecurity.prepareDirectory(directory, fileManager: fileManager)
        let manifestURL = directory.appendingPathComponent(manifestFilename, isDirectory: false)
        if fileManager.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL)
            let retained = try JSONDecoder.recentDiagnostics.decode([RecentDictationDiagnostic].self, from: data)
                .sorted { $0.createdAt > $1.createdAt }
            try removeOrphanedDiagnosticFiles(keeping: retained, fileManager: fileManager)
            return retained
        }

        let legacyURL = directory.appendingPathComponent(legacyFilename, isDirectory: false)
        guard fileManager.fileExists(atPath: legacyURL.path) else {
            return []
        }
        let createdAt = (try? legacyURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? Date()
        let migrated = RecentDictationDiagnostic(
            id: "legacy-\(UUID().uuidString)",
            createdAt: createdAt,
            audioFilename: legacyFilename,
            status: "Retained from an earlier QuietType version"
        )
        try save([migrated], fileManager: fileManager)
        return [migrated]
    }

    @discardableResult
    public func retainSample(
        at sourceURL: URL,
        createdAt: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> RecentDictationDiagnostic {
        try OwnerOnlyFileSecurity.prepareDirectory(directory, fileManager: fileManager)
        var retained = try samples(fileManager: fileManager)
        let id = UUID().uuidString
        let filename = "Dictation-\(id).wav"
        let destinationURL = directory.appendingPathComponent(filename, isDirectory: false)
        let temporaryURL = directory.appendingPathComponent(".latest-\(id).wav")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        // Recording files and Application Support normally share a local APFS
        // volume. Linking avoids copying bytes on the transcription hot path;
        // cross-volume locations retain the secure-copy fallback.
        do {
            try fileManager.linkItem(at: sourceURL, to: temporaryURL)
        } catch {
            try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        }
        try OwnerOnlyFileSecurity.protectFile(temporaryURL, fileManager: fileManager)
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        try OwnerOnlyFileSecurity.protectFile(destinationURL, fileManager: fileManager)

        let sample = RecentDictationDiagnostic(
            id: id,
            createdAt: createdAt,
            audioFilename: filename
        )
        retained.insert(sample, at: 0)
        try saveAndPrune(retained, fileManager: fileManager)
        return sample
    }

    /// Compatibility wrapper for code that only needs the newest audio URL.
    @discardableResult
    public func retainWAV(at sourceURL: URL, fileManager: FileManager = .default) throws -> URL {
        let sample = try retainSample(at: sourceURL, fileManager: fileManager)
        return audioURL(for: sample)
    }

    public func update(
        id: String,
        transcript: String,
        output: String,
        error: String?,
        status: String,
        fileManager: FileManager = .default
    ) throws {
        var retained = try samples(fileManager: fileManager)
        guard let index = retained.firstIndex(where: { $0.id == id }) else {
            return
        }
        retained[index].transcript = transcript
        retained[index].output = output
        retained[index].error = error
        retained[index].status = status
        try save(retained, fileManager: fileManager)
    }

    public func audioURL(for sample: RecentDictationDiagnostic) -> URL {
        directory.appendingPathComponent(sample.audioFilename, isDirectory: false)
    }

    public func remove(id: String, fileManager: FileManager = .default) throws {
        let retained = try samples(fileManager: fileManager)
        guard let removed = retained.first(where: { $0.id == id }) else {
            return
        }
        try save(retained.filter { $0.id != id }, fileManager: fileManager)
        try? fileManager.removeItem(at: audioURL(for: removed))
    }

    public func clear(fileManager: FileManager = .default) throws {
        try OwnerOnlyFileSecurity.prepareDirectory(directory, fileManager: fileManager)
        let diagnosticFilenames = try fileManager.contentsOfDirectory(atPath: directory.path)
            .filter(isDiagnosticFilename)
        for filename in diagnosticFilenames {
            try? fileManager.removeItem(at: directory.appendingPathComponent(filename, isDirectory: false))
        }
    }

    private func saveAndPrune(
        _ samples: [RecentDictationDiagnostic],
        fileManager: FileManager
    ) throws {
        let sorted = samples.sorted { $0.createdAt > $1.createdAt }
        let kept = Array(sorted.prefix(maxSamples))
        let removed = sorted.dropFirst(maxSamples)
        try save(kept, fileManager: fileManager)
        for sample in removed {
            try? fileManager.removeItem(at: audioURL(for: sample))
        }
    }

    private func save(
        _ samples: [RecentDictationDiagnostic],
        fileManager: FileManager
    ) throws {
        try OwnerOnlyFileSecurity.prepareDirectory(directory, fileManager: fileManager)
        let manifestURL = directory.appendingPathComponent(manifestFilename, isDirectory: false)
        let data = try JSONEncoder.recentDiagnostics.encode(samples.sorted { $0.createdAt > $1.createdAt })
        try data.write(to: manifestURL, options: [.atomic])
        try OwnerOnlyFileSecurity.protectFile(manifestURL, fileManager: fileManager)
    }

    private func removeOrphanedDiagnosticFiles(
        keeping samples: [RecentDictationDiagnostic],
        fileManager: FileManager
    ) throws {
        let keptFilenames = Set(samples.map(\.audioFilename))
        let diagnosticFilenames = try fileManager.contentsOfDirectory(atPath: directory.path)
            .filter(isDiagnosticAudioFilename)
        for filename in diagnosticFilenames where !keptFilenames.contains(filename) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(filename, isDirectory: false))
        }
    }

    private func isDiagnosticFilename(_ filename: String) -> Bool {
        filename == manifestFilename || isDiagnosticAudioFilename(filename)
    }

    private func isDiagnosticAudioFilename(_ filename: String) -> Bool {
        filename == legacyFilename
            || filename.hasPrefix("Dictation-") && filename.hasSuffix(".wav")
            || filename.hasPrefix(".latest-") && filename.hasSuffix(".wav")
    }
}

private extension JSONEncoder {
    static let recentDiagnostics: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let recentDiagnostics: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
