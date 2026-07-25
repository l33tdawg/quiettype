import Foundation

/// Retains exactly one owner-only plaintext WAV for local debugging. A new
/// completed transcription attempt replaces the previous file; nothing is
/// synced or referenced from transcript memory.
public struct LatestDictationAudioStore: Sendable {
    public let directory: URL
    public let filename: String

    public init(directory: URL, filename: String = "LastDictation.wav") {
        self.directory = directory
        self.filename = filename
    }

    public var retainedAudioURL: URL {
        directory.appendingPathComponent(filename, isDirectory: false)
    }

    @discardableResult
    public func retainWAV(at sourceURL: URL, fileManager: FileManager = .default) throws -> URL {
        try OwnerOnlyFileSecurity.prepareDirectory(directory, fileManager: fileManager)
        let temporaryURL = directory.appendingPathComponent(".latest-\(UUID().uuidString).wav")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        // Recording files and Application Support normally live on the same
        // local APFS volume. Linking keeps the completed WAV available for a
        // report without copying its bytes on the transcription hot path. The
        // source is never written after recording stops, and later cleanup
        // simply removes its directory entry. Fall back to a secure copy for
        // uncommon cross-volume locations.
        do {
            try fileManager.linkItem(at: sourceURL, to: temporaryURL)
        } catch {
            try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        }
        try OwnerOnlyFileSecurity.protectFile(temporaryURL, fileManager: fileManager)
        if fileManager.fileExists(atPath: retainedAudioURL.path) {
            try fileManager.removeItem(at: retainedAudioURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: retainedAudioURL)
        try OwnerOnlyFileSecurity.protectFile(retainedAudioURL, fileManager: fileManager)
        return retainedAudioURL
    }

    public func clear(fileManager: FileManager = .default) throws {
        if fileManager.fileExists(atPath: retainedAudioURL.path) {
            try fileManager.removeItem(at: retainedAudioURL)
        }
    }
}
