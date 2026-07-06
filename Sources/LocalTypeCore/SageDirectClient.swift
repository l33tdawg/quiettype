import CryptoKit
import Foundation
import Security

public struct SageAgentRegistration: Equatable, Sendable {
    public var agentID: String
    public var status: String
    public var name: String
}

public struct SageMemoryRecord: Identifiable, Equatable, Sendable {
    public var id: String
    public var content: String
    public var domain: String
    public var type: String
    public var confidence: Double?
    public var createdAt: String?
    public var submittingAgent: String?

    public init(
        id: String,
        content: String,
        domain: String,
        type: String,
        confidence: Double? = nil,
        createdAt: String? = nil,
        submittingAgent: String? = nil
    ) {
        self.id = id
        self.content = content
        self.domain = domain
        self.type = type
        self.confidence = confidence
        self.createdAt = createdAt
        self.submittingAgent = submittingAgent
    }
}

public struct SageMemorySubmission: Equatable, Sendable {
    public var memoryID: String
    public var txHash: String
    public var status: String
}

public struct SageMemoryDeprecation: Equatable, Sendable {
    public var txHash: String?
    public var status: String?
}

public enum SageDirectClientError: LocalizedError, Equatable {
    case invalidEndpoint(URL)
    case invalidKeyData
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)
    case agentIDMismatch(expected: String, actual: String)
    case requestFailed(Int, String)

    public static func isTextSearchUnavailable(_ error: Error) -> Bool {
        guard case SageDirectClientError.requestFailed(let status, let body) = error else {
            return false
        }
        let lowered = body.lowercased()
        return status == 500
            && lowered.contains("text search unavailable")
            && (lowered.contains("semantic-only") || lowered.contains("vault-encrypted"))
    }

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let url):
            return "SAGE must be reached through a local endpoint. Current endpoint: \(url.absoluteString)"
        case .invalidKeyData:
            return "QuietType could not read its SAGE agent key."
        case .keychainReadFailed(let status):
            return "QuietType could not read its SAGE agent key from Keychain. Status \(status)."
        case .keychainWriteFailed(let status):
            return "QuietType could not save its SAGE agent key to Keychain. Status \(status)."
        case .agentIDMismatch(let expected, let actual):
            return "SAGE returned quiettype-agent \(actual), but this install signs as \(expected)."
        case .requestFailed(let status, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "SAGE returned HTTP \(status)."
            }
            return "SAGE returned HTTP \(status): \(String(trimmed.prefix(160)))"
        }
    }
}

public final class SageSigningIdentity: @unchecked Sendable {
    public let privateKey: Curve25519.Signing.PrivateKey

    public var agentID: String {
        privateKey.publicKey.rawRepresentation.hexEncodedString()
    }

    public init(privateKey: Curve25519.Signing.PrivateKey) {
        self.privateKey = privateKey
    }

    public static func loadOrCreate(fileManager: FileManager = .default) throws -> SageSigningIdentity {
        let keyURL = try identityURL(fileManager: fileManager)
        return try loadOrCreate(
            keyURL: keyURL,
            fileManager: fileManager,
            readKeychainSeed: { try keychainSeed() },
            saveKeychainSeed: { try saveSeedToKeychain($0) },
            generateSeed: { Curve25519.Signing.PrivateKey().rawRepresentation }
        )
    }

    static func loadOrCreate(
        keyURL: URL,
        fileManager: FileManager,
        readKeychainSeed: () throws -> Data?,
        saveKeychainSeed: (Data) throws -> Void,
        generateSeed: () throws -> Data
    ) throws -> SageSigningIdentity {
        if fileManager.fileExists(atPath: keyURL.path) {
            let data = try Data(contentsOf: keyURL)
            if data.count == 32 {
                try? saveKeychainSeed(data)
                return try SageSigningIdentity(privateKey: Curve25519.Signing.PrivateKey(rawRepresentation: data))
            }
        }

        if let keyData = try readKeychainSeed() {
            try mirrorSeedIfNeeded(keyData, to: keyURL, fileManager: fileManager)
            return try SageSigningIdentity(privateKey: Curve25519.Signing.PrivateKey(rawRepresentation: keyData))
        }

        let seed = try generateSeed()
        guard seed.count == 32 else {
            throw SageDirectClientError.invalidKeyData
        }
        try? saveKeychainSeed(seed)
        try mirrorSeedIfNeeded(seed, to: keyURL, fileManager: fileManager)
        return try SageSigningIdentity(privateKey: Curve25519.Signing.PrivateKey(rawRepresentation: seed))
    }

    public static func identityURL(fileManager: FileManager = .default) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("QuietType", isDirectory: true)
            .appendingPathComponent("sage-agent.key", isDirectory: false)
    }

    fileprivate func signedHeaders(method: String, path: String, body: Data, timestamp: Int64 = Int64(Date().timeIntervalSince1970)) throws -> [String: String] {
        var canonical = Data("\(method) \(path)\n".utf8)
        canonical.append(body)
        let bodyHash = Data(SHA256.hash(data: canonical))
        let nonce = Data((0..<8).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })

        var message = Data()
        message.append(bodyHash)
        message.append(UInt64(timestamp).bigEndianData)
        message.append(nonce)

        let signature = try privateKey.signature(for: message)
        return [
            "X-Agent-ID": agentID,
            "X-Signature": signature.hexEncodedString(),
            "X-Timestamp": "\(timestamp)",
            "X-Nonce": nonce.hexEncodedString()
        ]
    }

    private static let keychainService = "QuietType.SAGE"
    private static let keychainAccount = "quiettype-agent-ed25519-seed"

    private static func keychainSeed() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SageDirectClientError.keychainReadFailed(status)
        }
        guard let data = item as? Data, data.count == 32 else {
            throw SageDirectClientError.invalidKeyData
        }
        return data
    }

    private static func saveSeedToKeychain(_ seed: Data) throws {
        guard seed.count == 32 else {
            throw SageDirectClientError.invalidKeyData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: seed
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw SageDirectClientError.keychainWriteFailed(updateStatus)
        }

        var item = query
        item[kSecValueData as String] = seed
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw SageDirectClientError.keychainWriteFailed(addStatus)
        }
    }

    private static func mirrorSeedIfNeeded(_ seed: Data, to keyURL: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: keyURL.path),
           (try? Data(contentsOf: keyURL)) == seed {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
            return
        }
        try seed.write(to: keyURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
    }
}

public final class SageDirectClient: @unchecked Sendable {
    private let endpoint: URL
    private let identity: SageSigningIdentity
    private let registeredAgentID: String?
    private let session: URLSession

    public var signingAgentID: String {
        identity.agentID
    }

    public var memoryAgentID: String {
        registeredAgentID ?? identity.agentID
    }

    public init(
        endpoint: URL = URL(string: "http://127.0.0.1:8080")!,
        identity: SageSigningIdentity,
        session: URLSession = .shared,
        registeredAgentID: String? = nil
    ) throws {
        guard endpoint.isQuietTypeLocalSageEndpoint else {
            throw SageDirectClientError.invalidEndpoint(endpoint)
        }
        self.endpoint = endpoint
        self.identity = identity
        self.registeredAgentID = registeredAgentID
        self.session = session
    }

    public func usingRegisteredAgentID(_ agentID: String) throws -> SageDirectClient {
        try SageDirectClient(
            endpoint: endpoint,
            identity: identity,
            session: session,
            registeredAgentID: agentID
        )
    }

    public func registerQuietTypeAgent() async throws -> SageAgentRegistration {
        let body = try JSONSerialization.data(withJSONObject: [
            "name": "quiettype-agent",
            "role": "member",
            "provider": "quiettype",
            "boot_bio": "QuietType local dictation assistant. Stores approved vocabulary, corrections, and writing preferences as private local dictation memory."
        ])

        let data = try await request(method: "POST", path: "/v1/agent/register", body: body)
        let decoded = try JSONDecoder().decode(SageAgentRegistrationResponse.self, from: data)
        return SageAgentRegistration(
            agentID: decoded.agentID,
            status: decoded.status,
            name: decoded.name
        )
    }

    public func registeredAgent(agentID: String) async throws -> SageAgentRegistration? {
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/agents"))
        request.httpMethod = "GET"
        request.timeoutInterval = 3

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw SageDirectClientError.requestFailed(statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(SageAgentListResponse.self, from: data)
        guard let agent = Self.preferredQuietTypeAgent(from: decoded.agents, matching: agentID) else {
            return nil
        }

        return SageAgentRegistration(
            agentID: agent.agentID,
            status: agent.status == "active" ? "already_registered" : agent.status,
            name: agent.registeredName ?? agent.name
        )
    }

    public func isHealthy() async -> Bool {
        do {
            var request = URLRequest(url: endpoint.appendingPathComponent("health"))
            request.httpMethod = "GET"
            request.timeoutInterval = 2
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return false
            }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    public func listMemories(limit: Int = 12) async throws -> [SageMemoryRecord] {
        let path = "/v1/memory/list?limit=\(limit)&sort=newest&status=committed&agent=\(memoryAgentID)"
        let data = try await request(method: "GET", path: path, body: Data())
        let decoded = try JSONDecoder().decode(SageMemoryListResponse.self, from: data)
        return decoded.memories.map(\.record)
    }

    public func searchMemories(query: String, limit: Int = 12, tags: [String] = []) async throws -> [SageMemoryRecord] {
        var payload: [String: Any] = [
            "query": query,
            "top_k": limit,
            "status_filter": "committed",
            "agent": memoryAgentID
        ]
        if !tags.isEmpty {
            payload["tags"] = tags
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await request(method: "POST", path: "/v1/memory/search", body: body)
        let decoded = try JSONDecoder().decode(SageMemorySearchResponse.self, from: data)
        return decoded.results.map(\.record)
    }

    private static func preferredQuietTypeAgent(from agents: [SageAgentDTO], matching agentID: String) -> SageAgentDTO? {
        let quietTypeAgents = agents.filter { $0.isQuietTypeAgent }
        let activeQuietTypeAgents = quietTypeAgents.filter(\.isActive)

        if let exactActive = activeQuietTypeAgents.first(where: { $0.agentID == agentID }) {
            return exactActive
        }
        if let exact = quietTypeAgents.first(where: { $0.agentID == agentID }) {
            return exact
        }
        if activeQuietTypeAgents.count == 1 {
            return activeQuietTypeAgents[0]
        }
        if quietTypeAgents.count == 1 {
            return quietTypeAgents[0]
        }
        return nil
    }

    public func submitTranslationMemory(content: String, confidence: Double = 0.95) async throws -> SageMemorySubmission {
        let body = try JSONSerialization.data(withJSONObject: [
            "content": content,
            "memory_type": "fact",
            "domain_tag": "quiettype.translation",
            "provider": "quiettype",
            "confidence_score": confidence,
            "classification": 0,
            "tags": ["quiettype", "dictation", "translation"]
        ])

        let data = try await registeredClientForSubmitting().request(method: "POST", path: "/v1/memory/submit", body: body)
        let decoded = try JSONDecoder().decode(SageMemorySubmitResponse.self, from: data)
        return SageMemorySubmission(memoryID: decoded.memoryID, txHash: decoded.txHash, status: decoded.status)
    }

    public func submitTranscriptNote(content: String, confidence: Double = 0.82) async throws -> SageMemorySubmission {
        let body = try JSONSerialization.data(withJSONObject: [
            "content": content,
            "memory_type": "observation",
            "domain_tag": "quiettype.transcripts",
            "provider": "quiettype",
            "confidence_score": confidence,
            "classification": 0,
            "tags": ["quiettype", "dictation", "transcript", "review"]
        ])

        let data = try await registeredClientForSubmitting().request(method: "POST", path: "/v1/memory/submit", body: body)
        let decoded = try JSONDecoder().decode(SageMemorySubmitResponse.self, from: data)
        return SageMemorySubmission(memoryID: decoded.memoryID, txHash: decoded.txHash, status: decoded.status)
    }

    public func deprecateMemory(id memoryID: String, reason: String) async throws -> SageMemoryDeprecation {
        let encodedID = memoryID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? memoryID
        let path = "/v1/memory/\(encodedID)/forget"
        let body = try JSONSerialization.data(withJSONObject: [
            "reason": reason
        ])
        let data = try await registeredClientForSubmitting().request(method: "POST", path: path, body: body)
        let decoded = try? JSONDecoder().decode(SageMemoryForgetResponse.self, from: data)
        return SageMemoryDeprecation(txHash: decoded?.txHash, status: decoded?.status)
    }

    private func registeredClientForSubmitting() throws -> SageDirectClient {
        if let registeredAgentID {
            guard registeredAgentID == signingAgentID else {
                throw SageDirectClientError.agentIDMismatch(expected: signingAgentID, actual: registeredAgentID)
            }
        }
        return self
    }

    private func request(method: String, path: String, body: Data) async throws -> Data {
        let url = endpoint.appendingPathComponent(String(path.dropFirst()))
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let queryStart = path.firstIndex(of: "?") {
            let rawPath = String(path[..<queryStart])
            components = URLComponents(url: endpoint.appendingPathComponent(String(rawPath.dropFirst())), resolvingAgainstBaseURL: false)
            components?.percentEncodedQuery = String(path[path.index(after: queryStart)...])
        }

        guard let requestURL = components?.url else {
            throw SageDirectClientError.invalidEndpoint(endpoint)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.timeoutInterval = 4
        request.httpBody = body.isEmpty ? nil : body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in try identity.signedHeaders(method: method, path: path, body: body) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw SageDirectClientError.requestFailed(statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}

private struct SageAgentRegistrationResponse: Decodable {
    var agentID: String
    var status: String
    var name: String

    enum CodingKeys: String, CodingKey {
        case agentID = "agent_id"
        case status
        case name
    }
}

private struct SageAgentListResponse: Decodable {
    var agents: [SageAgentDTO]
}

private struct SageAgentDTO: Decodable {
    var agentID: String
    var name: String
    var registeredName: String?
    var status: String

    enum CodingKeys: String, CodingKey {
        case agentID = "agent_id"
        case name
        case registeredName = "registered_name"
        case status
    }

    var isQuietTypeAgent: Bool {
        name == "quiettype-agent" || registeredName == "quiettype-agent"
    }

    var isActive: Bool {
        status == "active" || status == "already_registered" || status == "registered"
    }
}

private struct SageMemoryListResponse: Decodable {
    var memories: [SageMemoryDTO]
}

private struct SageMemorySearchResponse: Decodable {
    var results: [SageMemoryDTO]
}

private struct SageMemorySubmitResponse: Decodable {
    var memoryID: String
    var txHash: String
    var status: String

    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case txHash = "tx_hash"
        case status
    }
}

private struct SageMemoryForgetResponse: Decodable {
    var txHash: String?
    var status: String?

    enum CodingKeys: String, CodingKey {
        case txHash = "tx_hash"
        case status
    }
}

private struct SageMemoryDTO: Decodable {
    var memoryID: String?
    var id: String?
    var content: String?
    var domainTag: String?
    var memoryType: String?
    var type: String?
    var confidenceScore: Double?
    var confidence: Double?
    var createdAt: String?
    var submittingAgent: String?

    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case id
        case content
        case domainTag = "domain_tag"
        case memoryType = "memory_type"
        case type
        case confidenceScore = "confidence_score"
        case confidence
        case createdAt = "created_at"
        case submittingAgent = "submitting_agent"
    }

    var record: SageMemoryRecord {
        SageMemoryRecord(
            id: memoryID ?? id ?? UUID().uuidString,
            content: content ?? "",
            domain: domainTag ?? "memory",
            type: memoryType ?? type ?? "memory",
            confidence: confidenceScore ?? confidence,
            createdAt: createdAt,
            submittingAgent: submittingAgent
        )
    }
}

private extension UInt64 {
    var bigEndianData: Data {
        var value = bigEndian
        return Data(bytes: &value, count: MemoryLayout<UInt64>.size)
    }
}

private extension Data {
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension URL {
    var isQuietTypeLocalSageEndpoint: Bool {
        guard scheme == "http", let host else {
            return false
        }
        return ["127.0.0.1", "localhost", "::1"].contains(host)
    }
}
