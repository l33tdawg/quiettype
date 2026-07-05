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

    func testDetectsBundledSageAppWhenUserInstallIsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageDetectorTests-\(UUID().uuidString)", isDirectory: true)
        let bundled = root
            .appendingPathComponent("QuietType.app/Contents/Resources/SAGE.app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let detector = SageDetector(
            fileManager: .default,
            appPath: root.appendingPathComponent("Applications/SAGE").path,
            bundledAppPath: bundled.path,
            includeDefaultPaths: false
        )
        let installation = detector.detect()

        XCTAssertTrue(installation.isInstalled)
        XCTAssertEqual(installation.appPath, bundled.path)
    }

    func testQuietTypeRegistrationPayloadMatchesPRD() async throws {
        let store = SageMemoryStore(fallback: SQLiteMemoryStore())
        let data = try await store.registrationPayload()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["agent_name"] as? String, "quiettype-agent")
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

    func testSQLiteMemoryStorePersistsAcrossInstances() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quiettype-memory-store-\(UUID().uuidString)", isDirectory: true)
        let storeURL = directory.appendingPathComponent("memory-store.json")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let firstStore = SQLiteMemoryStore(storeURL: storeURL)
        _ = try await firstStore.put(
            DictationMemory(
                type: .vocabulary,
                payload: ["term": "CometBFT", "preferred": "CometBFT"],
                contexts: ["voice_calibration"],
                source: "test",
                confidence: 0.94
            )
        )

        let secondStore = SQLiteMemoryStore(storeURL: storeURL)
        let results = try await secondStore.search(MemorySearchQuery(text: "CometBFT", types: [.vocabulary]))

        XCTAssertEqual(results.first?.payload["preferred"], "CometBFT")
    }

    func testPersistentDefaultCreatesEncryptedStorePath() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("quiettype-memory-home-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: home)
        }

        let store = SQLiteMemoryStore.persistentDefault(homeDirectory: home)
        _ = try await store.put(
            DictationMemory(
                type: .transcriptNote,
                payload: ["raw_transcript": "hello", "polished_text": "Hello."],
                contexts: ["dictation_review"],
                source: "test",
                confidence: 0.82
            )
        )

        let storeURL = home
            .appendingPathComponent("Library/Application Support/QuietType", isDirectory: true)
            .appendingPathComponent("memory-store.qtmemory")
        let stored = try Data(contentsOf: storeURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertFalse(String(data: stored, encoding: .utf8)?.contains("hello") == true)
    }

    func testPersistentDefaultLoadsLegacyJSONStore() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("quiettype-memory-home-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: home)
        }
        let directory = home
            .appendingPathComponent("Library/Application Support/QuietType", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyURL = directory.appendingPathComponent("memory-store.json")
        let legacyMemory = DictationMemory(
            id: "legacy-term",
            type: .vocabulary,
            payload: ["term": "SAGE", "preferred": "SAGE"],
            contexts: ["voice_calibration"],
            source: "legacy",
            confidence: 0.9
        )
        let data = try JSONEncoder().encode(["legacy-term": legacyMemory])
        try data.write(to: legacyURL)

        let store = SQLiteMemoryStore.persistentDefault(homeDirectory: home)
        let results = try await store.search(MemorySearchQuery(text: "SAGE", types: [.vocabulary]))

        XCTAssertEqual(results.first?.payload["preferred"], "SAGE")
    }
}
