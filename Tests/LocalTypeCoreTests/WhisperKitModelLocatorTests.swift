import XCTest
@testable import LocalTypeCore

final class WhisperKitModelLocatorTests: XCTestCase {
    func testPrefersBundledModelRootBeforeHomeDirectories() throws {
        let modelName = "openai_whisper-large-v3-v20240930_626MB"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let bundled = root
            .appendingPathComponent("Bundle/Contents/Resources/WhisperKit")
            .appendingPathComponent(modelName)
        let home = root
            .appendingPathComponent("Home/Documents/huggingface/models/argmaxinc/whisperkit-coreml")
            .appendingPathComponent(modelName)
        try createCompleteModel(at: bundled)
        try createCompleteModel(at: home)

        let bundle = Bundle(path: root.appendingPathComponent("Bundle").path) ?? .main
        let found = WhisperKitModelLocator.localModelPath(
            named: modelName,
            bundle: bundle,
            homeDirectory: root.appendingPathComponent("Home")
        )

        XCTAssertEqual(found?.standardizedFileURL.path, bundled.standardizedFileURL.path)
    }

    private func createCompleteModel(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for directory in ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"] {
            try FileManager.default.createDirectory(
                at: url.appendingPathComponent(directory),
                withIntermediateDirectories: true
            )
        }
        for file in ["config.json", "generation_config.json", "tokenizer.json", "tokenizer_config.json"] {
            try Data("{}".utf8).write(to: url.appendingPathComponent(file))
        }
    }
}
