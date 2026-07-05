import Foundation

public struct SageAgentIdentity: Codable, Equatable, Sendable {
    public var agentName: String
    public var agentType: String
    public var capabilities: [String]
    public var privacyMode: String
    public var networkPolicy: String

    public static let privateDictate = SageAgentIdentity(
        agentName: "quiettype-agent",
        agentType: "local_dictation_assistant",
        capabilities: [
            "dictation_profile_memory",
            "vocabulary_memory",
            "correction_memory",
            "style_profile_memory",
            "app_contextual_recall"
        ],
        privacyMode: "local_first",
        networkPolicy: "user_controlled"
    )

    enum CodingKeys: String, CodingKey {
        case agentName = "agent_name"
        case agentType = "agent_type"
        case capabilities
        case privacyMode = "privacy_mode"
        case networkPolicy = "network_policy"
    }
}

public struct SageInstallation: Equatable, Sendable {
    public var appPath: String
    public var localEndpoint: URL
    public var isInstalled: Bool

    public init(
        appPath: String = "/Applications/SAGE",
        localEndpoint: URL = URL(string: "http://127.0.0.1:8080")!,
        isInstalled: Bool
    ) {
        self.appPath = appPath
        self.localEndpoint = localEndpoint
        self.isInstalled = isInstalled
    }
}

public struct SageDetector {
    private let fileManager: FileManager
    private let appPaths: [String]
    private let localEndpoint: URL

    public init(
        fileManager: FileManager = .default,
        appPath: String = "/Applications/SAGE",
        bundledAppPath: String? = SageDetector.defaultBundledAppPath(),
        includeDefaultPaths: Bool = true,
        localEndpoint: URL = URL(string: "http://127.0.0.1:8080")!
    ) {
        self.fileManager = fileManager
        self.appPaths = Self.candidatePaths(
            preferredPath: appPath,
            bundledAppPath: bundledAppPath,
            includeDefaultPaths: includeDefaultPaths
        )
        self.localEndpoint = localEndpoint
    }

    public func detect() -> SageInstallation {
        let installedPath = appPaths.first { path in
            fileManager.fileExists(atPath: path)
        }

        return SageInstallation(
            appPath: installedPath ?? appPaths[0],
            localEndpoint: localEndpoint,
            isInstalled: installedPath != nil
        )
    }

    public static func defaultBundledAppPath(bundle: Bundle = .main) -> String? {
        bundle.resourceURL?
            .appendingPathComponent("SAGE.app", isDirectory: true)
            .path
    }

    private static func candidatePaths(
        preferredPath: String,
        bundledAppPath: String?,
        includeDefaultPaths: Bool
    ) -> [String] {
        let preferredAlternate: String
        if preferredPath.hasSuffix(".app") {
            preferredAlternate = String(preferredPath.dropLast(4))
        } else {
            preferredAlternate = "\(preferredPath).app"
        }

        var paths: [String?] = [
            preferredPath,
            preferredAlternate
        ]

        if includeDefaultPaths {
            paths.append(contentsOf: [
                "/Applications/SAGE.app",
                "/Applications/SAGE",
                "\(NSHomeDirectory())/Applications/SAGE.app",
                "\(NSHomeDirectory())/Applications/SAGE"
            ])
        }

        paths.append(bundledAppPath)
        let compactPaths = paths.compactMap { $0 }

        var seen = Set<String>()
        return compactPaths.filter { seen.insert($0).inserted }
    }
}

public actor SageMemoryStore: MemoryStore {
    private let endpoint: URL
    private let identity: SageAgentIdentity
    private let allowNetworkPolicy: Bool
    private let fallback: MemoryStore?

    public init(
        endpoint: URL = URL(string: "http://127.0.0.1:8080")!,
        identity: SageAgentIdentity = .privateDictate,
        allowNetworkPolicy: Bool = false,
        fallback: MemoryStore? = nil
    ) {
        self.endpoint = endpoint
        self.identity = identity
        self.allowNetworkPolicy = allowNetworkPolicy
        self.fallback = fallback
    }

    public func registrationPayload() throws -> Data {
        try JSONEncoder().encode(identity)
    }

    public func put(_ memory: DictationMemory) async throws -> String {
        try validateLocalEndpoint()
        try validatePrivacy(memory)

        // The concrete SDK/API adapter belongs here once the Swift-facing SAGE
        // integration is finalized. Until then, preserve behavior through the
        // optional local cache rather than inventing a parallel protocol.
        guard let fallback else {
            throw MemoryStoreError.sageUnavailable
        }
        return try await fallback.put(memory)
    }

    public func search(_ query: MemorySearchQuery) async throws -> [DictationMemory] {
        try validateLocalEndpoint()

        guard let fallback else {
            throw MemoryStoreError.sageUnavailable
        }
        return try await fallback.search(query)
    }

    public func update(memoryID: String, patch: [String: String]) async throws {
        try validateLocalEndpoint()
        guard let fallback else {
            throw MemoryStoreError.sageUnavailable
        }
        try await fallback.update(memoryID: memoryID, patch: patch)
    }

    public func delete(memoryID: String) async throws {
        try validateLocalEndpoint()
        guard let fallback else {
            throw MemoryStoreError.sageUnavailable
        }
        try await fallback.delete(memoryID: memoryID)
    }

    public func explain(memoryID: String) async throws -> String {
        try validateLocalEndpoint()
        guard let fallback else {
            throw MemoryStoreError.sageUnavailable
        }
        return try await fallback.explain(memoryID: memoryID)
    }

    private func validateLocalEndpoint() throws {
        guard endpoint.isLocalSageEndpoint else {
            throw MemoryStoreError.nonLocalSageEndpoint(endpoint.absoluteString)
        }
    }

    private func validatePrivacy(_ memory: DictationMemory) throws {
        guard memory.privacy == "local" || allowNetworkPolicy else {
            throw MemoryStoreError.networkedSageRequiresUserConsent
        }
    }
}

public actor HybridMemoryStore: MemoryStore {
    private let local: MemoryStore
    private let sage: MemoryStore

    public init(local: MemoryStore, sage: MemoryStore) {
        self.local = local
        self.sage = sage
    }

    public func put(_ memory: DictationMemory) async throws -> String {
        let localID = try await local.put(memory)
        _ = try? await sage.put(memory)
        return localID
    }

    public func search(_ query: MemorySearchQuery) async throws -> [DictationMemory] {
        let localResults = try await local.search(query)
        let sageResults = (try? await sage.search(query)) ?? []
        return dedupe(localResults + sageResults).prefixArray(query.limit)
    }

    public func update(memoryID: String, patch: [String: String]) async throws {
        try await local.update(memoryID: memoryID, patch: patch)
        try? await sage.update(memoryID: memoryID, patch: patch)
    }

    public func delete(memoryID: String) async throws {
        try await local.delete(memoryID: memoryID)
        try? await sage.delete(memoryID: memoryID)
    }

    public func explain(memoryID: String) async throws -> String {
        try await local.explain(memoryID: memoryID)
    }

    private func dedupe(_ memories: [DictationMemory]) -> [DictationMemory] {
        var seen = Set<String>()
        return memories.filter { memory in
            let key = memory.id ?? "\(memory.type.rawValue):\(memory.payload.sorted { $0.key < $1.key })"
            return seen.insert(key).inserted
        }
    }
}

private extension Array {
    func prefixArray(_ maxLength: Int) -> [Element] {
        Array(prefix(maxLength))
    }
}

private extension URL {
    var isLocalSageEndpoint: Bool {
        guard scheme == "http", let host else {
            return false
        }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
}
