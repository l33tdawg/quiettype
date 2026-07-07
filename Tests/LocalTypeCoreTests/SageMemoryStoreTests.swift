import CryptoKit
import XCTest
@testable import LocalTypeCore

final class SageMemoryStoreTests: XCTestCase {
    override func tearDown() {
        SageDirectClientURLProtocol.handler = nil
        super.tearDown()
    }

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

        let encryptedURL = directory.appendingPathComponent("memory-store.qtmemory")
        let stored = try Data(contentsOf: encryptedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: encryptedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertFalse(String(data: stored, encoding: .utf8)?.contains("SAGE") == true)
    }

    func testSigningIdentityPrefersExistingMirroredSeedOverKeychainSeed() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageIdentityTests-\(UUID().uuidString)", isDirectory: true)
        let keyURL = root.appendingPathComponent("sage-agent.key")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let mirroredSeed = Data(repeating: 0x11, count: 32)
        let keychainSeed = Data(repeating: 0x22, count: 32)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try mirroredSeed.write(to: keyURL)

        var didReadKeychain = false
        var savedSeed: Data?
        let identity = try SageSigningIdentity.loadOrCreate(
            keyURL: keyURL,
            fileManager: .default,
            readKeychainSeed: {
                didReadKeychain = true
                return keychainSeed
            },
            saveKeychainSeed: { seed in
                savedSeed = seed
            },
            generateSeed: {
                XCTFail("Existing mirrored seed should be recovered before creating a new seed.")
                return Data(repeating: 0x33, count: 32)
            }
        )

        XCTAssertFalse(didReadKeychain)
        XCTAssertEqual(identity.privateKey.rawRepresentation, mirroredSeed)
        XCTAssertEqual(savedSeed, mirroredSeed)
        XCTAssertEqual(try Data(contentsOf: keyURL), mirroredSeed)
    }

    func testSigningIdentityFallsBackToKeychainWhenMirroredSeedIsInvalid() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageIdentityTests-\(UUID().uuidString)", isDirectory: true)
        let keyURL = root.appendingPathComponent("sage-agent.key")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let keychainSeed = Data(repeating: 0x22, count: 32)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 0x11, count: 12).write(to: keyURL)

        let identity = try SageSigningIdentity.loadOrCreate(
            keyURL: keyURL,
            fileManager: .default,
            readKeychainSeed: {
                keychainSeed
            },
            saveKeychainSeed: { _ in },
            generateSeed: {
                XCTFail("Valid Keychain seed should be used before creating a new seed.")
                return Data(repeating: 0x33, count: 32)
            }
        )

        XCTAssertEqual(identity.privateKey.rawRepresentation, keychainSeed)
        XCTAssertEqual(try Data(contentsOf: keyURL), keychainSeed)
    }

    func testSigningIdentityDoesNotRotateWhenKeychainReadFails() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageIdentityTests-\(UUID().uuidString)", isDirectory: true)
        let keyURL = root.appendingPathComponent("sage-agent.key")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        do {
            _ = try SageSigningIdentity.loadOrCreate(
                keyURL: keyURL,
                fileManager: .default,
                readKeychainSeed: {
                    throw SageDirectClientError.keychainReadFailed(errSecInteractionNotAllowed)
                },
                saveKeychainSeed: { _ in },
                generateSeed: {
                    XCTFail("A Keychain read failure should not create a new SAGE signing seed.")
                    return Data(repeating: 0x33, count: 32)
                }
            )
            XCTFail("Expected Keychain read failure to be surfaced.")
        } catch SageDirectClientError.keychainReadFailed(errSecInteractionNotAllowed) {
            XCTAssertFalse(FileManager.default.fileExists(atPath: keyURL.path))
        }
    }

    func testRecoveredQuietTypeAgentIDIsUsedForMemoryQueriesAndSubmissions() async throws {
        let seed = Data(repeating: 0x44, count: 32)
        let identity = try SageSigningIdentity(
            privateKey: Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        )
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SageDirectClientURLProtocol.self]
        let session = URLSession(configuration: config)
        let endpoint = URL(string: "http://127.0.0.1:18080")!
        let recoveredAgentID = identity.agentID
        var memoryListURL: URL?
        var searchBody: [String: Any]?
        var submitAgentID: String?

        SageDirectClientURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/agents":
                return (
                    200,
                    """
                    {
                      "agents": [
                        {
                          "agent_id": "\(recoveredAgentID)",
                          "name": "quiettype-agent",
                          "registered_name": "quiettype-agent",
                          "status": "active"
                        }
                      ]
                    }
                    """.data(using: .utf8)!
                )
            case "/v1/memory/search":
                if let body = request.bodyData {
                    searchBody = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                }
                return (
                    200,
                    """
                    {
                      "results": [
                        {
                          "memory_id": "memory-2",
                          "content": "QuietType found this.",
                          "domain_tag": "quiettype.transcripts",
                          "memory_type": "observation",
                          "submitting_agent": "\(recoveredAgentID)"
                        }
                      ]
                    }
                    """.data(using: .utf8)!
                )
            case "/v1/memory/list":
                memoryListURL = request.url
                return (
                    200,
                    """
                    {
                      "memories": [
                        {
                          "memory_id": "memory-1",
                          "content": "QuietType remembered this.",
                          "domain_tag": "quiettype.transcripts",
                          "memory_type": "observation",
                          "submitting_agent": "\(recoveredAgentID)"
                        }
                      ]
                    }
                    """.data(using: .utf8)!
                )
            case "/v1/memory/submit":
                submitAgentID = request.value(forHTTPHeaderField: "X-Agent-ID")
                return (
                    200,
                    """
                    {
                      "memory_id": "memory-3",
                      "tx_hash": "tx-3",
                      "status": "committed"
                    }
                    """.data(using: .utf8)!
                )
            default:
                return (404, Data())
            }
        }

        let client = try SageDirectClient(endpoint: endpoint, identity: identity, session: session)
        let existing = try await client.registeredAgent(agentID: client.signingAgentID)
        XCTAssertEqual(existing?.agentID, recoveredAgentID)

        let recoveredClient = try client.usingRegisteredAgentID(existing!.agentID)
        let memories = try await recoveredClient.listMemories(limit: 16)
        let searchResults = try await recoveredClient.searchMemories(query: "quiettype", limit: 16)
        let submission = try await recoveredClient.submitTranscriptNote(content: "Reviewed a transcript.")

        XCTAssertEqual(memories.first?.submittingAgent, recoveredAgentID)
        XCTAssertEqual(searchResults.first?.submittingAgent, recoveredAgentID)
        XCTAssertEqual(submission.memoryID, "memory-3")
        XCTAssertEqual(submitAgentID, recoveredAgentID)
        let queryItems = URLComponents(url: memoryListURL!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(queryItems?.first(where: { $0.name == "agent" })?.value, recoveredAgentID)
        XCTAssertEqual(searchBody?["agent"] as? String, recoveredAgentID)
    }

    func testDeprecateMemoryCallsForgetEndpointWithReason() async throws {
        let seed = Data(repeating: 0x45, count: 32)
        let identity = try SageSigningIdentity(
            privateKey: Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        )
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SageDirectClientURLProtocol.self]
        let session = URLSession(configuration: config)
        let endpoint = URL(string: "http://127.0.0.1:18080")!
        var requestBody: [String: Any]?
        var signingAgentID: String?

        SageDirectClientURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/memory/memory-1/forget")
            signingAgentID = request.value(forHTTPHeaderField: "X-Agent-ID")
            if let body = request.bodyData {
                requestBody = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            return (
                200,
                """
                {
                  "tx_hash": "tx-forget",
                  "status": "proposed"
                }
                """.data(using: .utf8)!
            )
        }

        let client = try SageDirectClient(endpoint: endpoint, identity: identity, session: session)
        let result = try await client.deprecateMemory(id: "memory-1", reason: "Superseded by corrected transcript.")

        XCTAssertEqual(result.txHash, "tx-forget")
        XCTAssertEqual(result.status, "proposed")
        XCTAssertEqual(signingAgentID, identity.agentID)
        XCTAssertEqual(requestBody?["reason"] as? String, "Superseded by corrected transcript.")
    }

    func testRegisteredAgentRecoversUniqueActiveQuietTypeAgentForMemoryReads() async throws {
        let seed = Data(repeating: 0x55, count: 32)
        let identity = try SageSigningIdentity(
            privateKey: Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        )
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SageDirectClientURLProtocol.self]
        let session = URLSession(configuration: config)
        let endpoint = URL(string: "http://127.0.0.1:18080")!
        let legacyAgentID = "e9606667ca0299cdf957d3f0434e6ca9366f0c992d03a9f75aadb5ca2349950b"
        var memoryListURL: URL?

        SageDirectClientURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/agents":
                return (
                    200,
                    """
                    {
                      "agents": [
                        {
                          "agent_id": "\(legacyAgentID)",
                          "name": "quiettype-agent",
                          "registered_name": "quiettype-agent",
                          "provider": "quiettype",
                          "status": "active",
                          "memory_count": 36
                        }
                      ]
                    }
                    """.data(using: .utf8)!
                )
            case "/v1/memory/list":
                memoryListURL = request.url
                return (
                    200,
                    """
                    {
                      "memories": [
                        {
                          "memory_id": "memory-1",
                          "content": "QuietType transcript note for review.",
                          "domain_tag": "quiettype.transcripts",
                          "memory_type": "observation",
                          "submitting_agent": "\(legacyAgentID)"
                        }
                      ]
                    }
                    """.data(using: .utf8)!
                )
            default:
                return (404, Data())
            }
        }

        let client = try SageDirectClient(endpoint: endpoint, identity: identity, session: session)
        let existing = try await client.registeredAgent(agentID: client.signingAgentID)

        XCTAssertEqual(existing?.agentID, legacyAgentID)
        let recoveredClient = try client.usingRegisteredAgentID(existing!.agentID)
        let memories = try await recoveredClient.listMemories(limit: 16)

        XCTAssertEqual(memories.count, 1)
        let queryItems = URLComponents(url: memoryListURL!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(queryItems?.first(where: { $0.name == "agent" })?.value, legacyAgentID)
    }

    func testRegisteredAgentDoesNotRecoverAmbiguousQuietTypeAgents() async throws {
        let seed = Data(repeating: 0x56, count: 32)
        let identity = try SageSigningIdentity(
            privateKey: Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        )
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SageDirectClientURLProtocol.self]
        let session = URLSession(configuration: config)
        let endpoint = URL(string: "http://127.0.0.1:18080")!

        SageDirectClientURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/agents")
            return (
                200,
                """
                {
                  "agents": [
                    {
                      "agent_id": "active-quiettype-agent-1",
                      "name": "quiettype-agent",
                      "registered_name": "quiettype-agent",
                      "status": "active"
                    },
                    {
                      "agent_id": "active-quiettype-agent-2",
                      "name": "quiettype-agent",
                      "registered_name": "quiettype-agent",
                      "status": "active"
                    }
                  ]
                }
                """.data(using: .utf8)!
            )
        }

        let client = try SageDirectClient(endpoint: endpoint, identity: identity, session: session)
        let existing = try await client.registeredAgent(agentID: client.signingAgentID)

        XCTAssertNil(existing)
    }

    func testDetectsSemanticOnlyTextSearchUnavailableResponse() async throws {
        let seed = Data(repeating: 0x66, count: 32)
        let identity = try SageSigningIdentity(
            privateKey: Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        )
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SageDirectClientURLProtocol.self]
        let session = URLSession(configuration: config)
        let endpoint = URL(string: "http://127.0.0.1:18080")!

        SageDirectClientURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/memory/search")
            return (
                500,
                """
                {
                  "detail": "text search unavailable: content is vault-encrypted; this node is in semantic-only mode",
                  "status": 500,
                  "title": "Search error",
                  "type": "https://sage.dev"
                }
                """.data(using: .utf8)!
            )
        }

        let client = try SageDirectClient(endpoint: endpoint, identity: identity, session: session)

        do {
            _ = try await client.searchMemories(query: "quiettype", limit: 16)
            XCTFail("Expected semantic-only search failure.")
        } catch {
            XCTAssertTrue(SageDirectClientError.isTextSearchUnavailable(error))
        }
    }
}

private final class SageDirectClientURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    var bodyData: Data? {
        if let httpBody {
            return httpBody
        }
        guard let httpBodyStream else {
            return nil
        }

        httpBodyStream.open()
        defer {
            httpBodyStream.close()
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while httpBodyStream.hasBytesAvailable {
            let count = httpBodyStream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data
    }
}
