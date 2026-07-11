import XCTest
@testable import LocalTypeCore

final class LatestDictationAudioStoreTests: XCTestCase {
    func testRetainsOnlyLatestOwnerOnlyWAV() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("latest-dictation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let first = root.appendingPathComponent("first.wav")
        let second = root.appendingPathComponent("second.wav")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        let store = LatestDictationAudioStore(directory: root.appendingPathComponent("retained"))

        try store.retainWAV(at: first)
        try store.retainWAV(at: second)

        XCTAssertEqual(try Data(contentsOf: store.retainedAudioURL), Data("second".utf8))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: store.directory.path),
            ["LastDictation.wav"]
        )
        let fileMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: store.retainedAudioURL.path)[.posixPermissions] as? NSNumber
        )
        let directoryMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: store.directory.path)[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(fileMode.intValue & 0o777, 0o600)
        XCTAssertEqual(directoryMode.intValue & 0o777, 0o700)
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

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.retainedAudioURL.path))
    }
}
