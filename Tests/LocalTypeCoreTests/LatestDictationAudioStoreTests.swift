import XCTest
@testable import LocalTypeCore

final class LatestDictationAudioStoreTests: XCTestCase {
    func testRetainsRollingThreeOwnerOnlyWAVs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("latest-dictation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sources = (1...4).map { root.appendingPathComponent("\($0).wav") }
        for (index, source) in sources.enumerated() {
            try Data("sample \(index + 1)".utf8).write(to: source)
        }
        let store = LatestDictationAudioStore(directory: root.appendingPathComponent("retained"))

        for source in sources {
            try store.retainWAV(at: source)
        }

        let retained = try store.samples()
        XCTAssertEqual(retained.count, 3)
        XCTAssertEqual(try Data(contentsOf: store.retainedAudioURL), Data("sample 4".utf8))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: store.directory.path).contains { $0.hasPrefix(".latest-") })
        let fileMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: store.retainedAudioURL.path)[.posixPermissions] as? NSNumber
        )
        let directoryMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: store.directory.path)[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(fileMode.intValue & 0o777, 0o600)
        XCTAssertEqual(directoryMode.intValue & 0o777, 0o700)
    }

    func testUpdatesDiagnosticTextForSelectedSample() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("latest-dictation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.wav")
        try Data("audio".utf8).write(to: source)
        let store = LatestDictationAudioStore(directory: root.appendingPathComponent("retained"))
        let sample = try store.retainSample(at: source)

        try store.update(
            id: sample.id,
            transcript: "raw local transcript",
            output: "processed local result",
            error: "local processing error",
            status: "Processing failed"
        )

        let updated = try XCTUnwrap(store.samples().first)
        XCTAssertEqual(updated.transcript, "raw local transcript")
        XCTAssertEqual(updated.output, "processed local result")
        XCTAssertEqual(updated.error, "local processing error")
        XCTAssertEqual(updated.status, "Processing failed")
    }

    func testClearRemovesRetainedWAV() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("latest-dictation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.wav")
        try Data("audio".utf8).write(to: source)
        let store = LatestDictationAudioStore(directory: root.appendingPathComponent("retained"))
        try store.retainWAV(at: source)

        try store.clear()

        XCTAssertTrue((try store.samples()).isEmpty)
    }

    func testClearRemovesOrphanedAudioWhenManifestIsCorrupt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("latest-dictation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("retained", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not valid json".utf8).write(to: directory.appendingPathComponent("RecentDictations.json"))
        try Data("orphan".utf8).write(to: directory.appendingPathComponent("Dictation-orphan.wav"))
        try Data("temporary".utf8).write(to: directory.appendingPathComponent(".latest-interrupted.wav"))
        try Data("legacy".utf8).write(to: directory.appendingPathComponent("LastDictation.wav"))
        let store = LatestDictationAudioStore(directory: directory)

        try store.clear()

        XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: directory.path)).isEmpty)
        XCTAssertTrue((try store.samples()).isEmpty)
    }

    func testMigratesLegacyRecordingAndPrunesItWithRollingHistory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("latest-dictation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("retained", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyURL = directory.appendingPathComponent("LastDictation.wav")
        try Data("legacy audio".utf8).write(to: legacyURL)
        let source = root.appendingPathComponent("new.wav")
        try Data("new audio".utf8).write(to: source)
        let store = LatestDictationAudioStore(directory: directory, maxSamples: 1)

        let migrated = try XCTUnwrap(store.samples().first)
        XCTAssertEqual(migrated.audioFilename, "LastDictation.wav")
        _ = try store.retainSample(at: source)

        XCTAssertEqual(try store.samples().count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        try store.clear()
        XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: directory.path)).isEmpty)
    }

    func testRetainedWAVSurvivesSourceCleanup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("latest-dictation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.wav")
        let audio = Data("audio retained for a report".utf8)
        try audio.write(to: source)
        let store = LatestDictationAudioStore(directory: root.appendingPathComponent("retained"))

        try store.retainWAV(at: source)
        try FileManager.default.removeItem(at: source)

        XCTAssertEqual(try Data(contentsOf: store.retainedAudioURL), audio)
    }
}
