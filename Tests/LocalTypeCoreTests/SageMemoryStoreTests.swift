import XCTest
@testable import LocalTypeCore

final class SageMemoryStoreTests: XCTestCase {
    func testDetectsSageAppBundlePath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageDetectorTests-\(UUID().uuidString)", isDirectory: true)
        let app = root.appendingPathComponent("SAGE.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)

        let detector = SageDetector(fileManager: .default, appPath: root.appendingPathComponent("SAGE").path)
        let installation = detector.detect()

        XCTAssertTrue(installation.isInstalled)
        XCTAssertEqual(installation.appPath, app.path)
    }

    func testQuietTypeRegistrationPayloadMatchesPRD() async throws {
        let store = SageMemoryStore(fallback: SQLiteMemoryStore())
        let data = try await store.registrationPayload()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["agent_name"] as? String, "QuietType")
        XCTAssertEqual(json?["agent_type"] as? String, "local_dictation_assistant")
        XCTAssertEqual(json?["privacy_mode"] as? String, "local_first")
        XCTAssertEqual(json?["network_policy"] as? String, "user_controlled")

        let capabilities = json?["capabilities"] as? [String]
        XCTAssertTrue(capabilities?.contains("vocabulary_memory") == true)
        XCTAssertTrue(capabilities?.contains("app_contextual_recall") == true)
    }

    func testRejectsNonLocalSageEndpoint() async throws {
        let store = SageMemoryStore(
            endpoint: URL(string: "https://sage.example.com")!,
            fallback: SQLiteMemoryStore()
        )

        do {
            _ = try await store.search(MemorySearchQuery(text: "CometBFT"))
            XCTFail("Expected non-local SAGE endpoint to be rejected")
        } catch MemoryStoreError.nonLocalSageEndpoint("https://sage.example.com") {
            // Expected.
        }
    }

    func testHybridStoreReturnsLocalMemoryWhenSageUnavailable() async throws {
        let local = SQLiteMemoryStore()
        let sage = SageMemoryStore(fallback: nil)
        let hybrid = HybridMemoryStore(local: local, sage: sage)

        _ = try await hybrid.put(
            DictationMemory(
                type: .vocabulary,
                payload: ["term": "CometBFT", "preferred_spelling": "CometBFT"],
                contexts: ["SAGE", "consensus"],
                source: "user_correction",
                confidence: 0.96
            )
        )

        let results = try await hybrid.search(MemorySearchQuery(text: "CometBFT"))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.payload["term"], "CometBFT")
    }
}
