import XCTest
@testable import LocalTypeCore

final class LocalASRDiscoveryTests: XCTestCase {
    func testDiscoversCommandAndPreferredModel() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bin = root.appendingPathComponent("vendor/whisper.cpp/build/bin")
        let models = root.appendingPathComponent("models")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)

        let executable = bin.appendingPathComponent("whisper-cli")
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let model = models.appendingPathComponent("ggml-small.en.bin")
        try Data().write(to: model)

        let discovery = LocalASRDiscovery(rootDirectory: root, homeDirectory: root.appendingPathComponent("home"))
        XCTAssertNotNil(discovery.firstExecutable())
        XCTAssertEqual(discovery.firstModel()?.path, model.path)
    }
}
