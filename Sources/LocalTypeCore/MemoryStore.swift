import Foundation

public enum MemoryBackendMode: String, Codable, Sendable {
    case sqliteOnly
    case sage
    case hybrid
}

public enum DictationMemoryType: String, Codable, Sendable {
    case vocabulary = "dictation.vocabulary"
    case correction = "dictation.correction"
    case styleProfile = "dictation.style_profile"
    case formattingPreference = "dictation.formatting_preference"
}

public struct DictationMemory: Codable, Equatable, Sendable, Identifiable {
    public var id: String?
    public var type: DictationMemoryType
    public var payload: [String: String]
    public var contexts: [String]
    public var source: String
    public var confidence: Double
    public var privacy: String
    public var createdBy: String

    public init(
        id: String? = nil,
        type: DictationMemoryType,
        payload: [String: String],
        contexts: [String] = [],
        source: String,
        confidence: Double,
        privacy: String = "local",
        createdBy: String = SageAgentIdentity.privateDictate.agentName
    ) {
        self.id = id
        self.type = type
        self.payload = payload
        self.contexts = contexts
        self.source = source
        self.confidence = confidence
        self.privacy = privacy
        self.createdBy = createdBy
    }
}

public struct MemorySearchQuery: Codable, Equatable, Sendable {
    public var text: String
    public var appName: String?
    public var types: [DictationMemoryType]
    public var limit: Int
    public var localOnly: Bool

    public init(
        text: String,
        appName: String? = nil,
        types: [DictationMemoryType] = [],
        limit: Int = 8,
        localOnly: Bool = true
    ) {
        self.text = text
        self.appName = appName
        self.types = types
        self.limit = limit
        self.localOnly = localOnly
    }
}

public protocol MemoryStore: Sendable {
    func put(_ memory: DictationMemory) async throws -> String
    func search(_ query: MemorySearchQuery) async throws -> [DictationMemory]
    func update(memoryID: String, patch: [String: String]) async throws
    func delete(memoryID: String) async throws
    func explain(memoryID: String) async throws -> String
}

public actor SQLiteMemoryStore: MemoryStore {
    private var memories: [String: DictationMemory] = [:]

    public init() {}

    public func put(_ memory: DictationMemory) async throws -> String {
        let id = memory.id ?? UUID().uuidString
        var stored = memory
        stored.id = id
        memories[id] = stored
        return id
    }

    public func search(_ query: MemorySearchQuery) async throws -> [DictationMemory] {
        let needle = query.text.lowercased()
        let filtered = memories.values.filter { memory in
            let typeMatches = query.types.isEmpty || query.types.contains(memory.type)
            let textMatches = needle.isEmpty
                || memory.contexts.joined(separator: " ").lowercased().contains(needle)
                || memory.payload.values.joined(separator: " ").lowercased().contains(needle)
            return typeMatches && textMatches
        }

        return Array(filtered.prefix(query.limit))
    }

    public func update(memoryID: String, patch: [String: String]) async throws {
        guard var memory = memories[memoryID] else {
            throw MemoryStoreError.notFound(memoryID)
        }
        for (key, value) in patch {
            memory.payload[key] = value
        }
        memories[memoryID] = memory
    }

    public func delete(memoryID: String) async throws {
        memories.removeValue(forKey: memoryID)
    }

    public func explain(memoryID: String) async throws -> String {
        guard let memory = memories[memoryID] else {
            throw MemoryStoreError.notFound(memoryID)
        }
        return "Stored locally as \(memory.type.rawValue) with confidence \(memory.confidence)."
    }
}

public enum MemoryStoreError: Error, Equatable {
    case notFound(String)
    case sageUnavailable
    case nonLocalSageEndpoint(String)
    case networkedSageRequiresUserConsent
}
