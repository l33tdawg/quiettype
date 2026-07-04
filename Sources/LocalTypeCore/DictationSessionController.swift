import Foundation

public actor DictationSessionController {
    private let profile: DictationProfile
    private let configuration: RuntimeConfiguration
    private let asrBackend: ASRBackend
    private let contextCollector: ContextCollecting
    private let inserter: TextInserting
    private let memoryStore: MemoryStore
    private let semanticEditor: SemanticEditor

    private var state: DictationSessionState = .idle
    private var pipeline: DictationPipeline?
    private var currentContext: AppContext?
    private var rawSegments: [String] = []
    private var timing = DictationTiming()
    private var startedAt: Date?
    private var releasedAt: Date?

    public init(
        profile: DictationProfile,
        configuration: RuntimeConfiguration = RuntimeConfiguration(),
        asrBackend: ASRBackend,
        contextCollector: ContextCollecting,
        inserter: TextInserting,
        memoryStore: MemoryStore = SQLiteMemoryStore(),
        semanticEditor: SemanticEditor
    ) {
        self.profile = profile
        self.configuration = configuration
        self.asrBackend = asrBackend
        self.contextCollector = contextCollector
        self.inserter = inserter
        self.memoryStore = memoryStore
        self.semanticEditor = semanticEditor
    }

    public func currentState() -> DictationSessionState {
        state
    }

    public func begin() async throws {
        guard state == .idle || state == .completed || state == .cancelled || state == .failed else {
            throw LocalTypeError.invalidSessionState("Cannot begin from \(state.rawValue)")
        }

        state = .capturing
        startedAt = Date()
        releasedAt = nil
        rawSegments = []
        timing = DictationTiming()

        let context = try await contextCollector.currentContext()
        guard !context.isSecureInput else {
            state = .failed
            throw LocalTypeError.secureInputBlocked(context.appName)
        }

        let enrichedProfile = try await profileWithRecalledMemories(for: context, partialText: "")
        currentContext = context
        pipeline = DictationPipeline(profile: enrichedProfile, semanticEditor: semanticEditor)

        try await asrBackend.startSession(profile: enrichedProfile)
        timing.timeToAudioStartMS = elapsedSinceStart()
    }

    public func ingestAudio(_ frame: AudioFrame) async throws {
        guard state == .capturing else {
            throw LocalTypeError.invalidSessionState("Cannot ingest audio from \(state.rawValue)")
        }
        try await asrBackend.pushAudio(frame)
        _ = try await processStableSegments(isFinal: false)
    }

    public func finishAndInsert() async throws -> DictationSessionResult {
        guard state == .capturing else {
            throw LocalTypeError.invalidSessionState("Cannot finish from \(state.rawValue)")
        }
        guard let context = currentContext else {
            throw LocalTypeError.invalidSessionState("Missing active app context")
        }

        state = .finalizing
        releasedAt = Date()

        let finalSegments = try await asrBackend.finish()
        guard !finalSegments.isEmpty else {
            state = .failed
            throw LocalTypeError.emptyDictation
        }

        let result = try await process(finalSegments, context: context)
        timing.semanticEditorLatencyMS = result.latencyMS

        state = .inserting
        let insertionStart = Date()
        try await inserter.insert(result.text, into: context)
        timing.insertionLatencyMS = Int(Date().timeIntervalSince(insertionStart) * 1000)
        timing.keyReleaseToInsertMS = releasedAt.map { Int(Date().timeIntervalSince($0) * 1000) }
        timing.totalSessionDurationMS = elapsedSinceStart()

        state = .completed
        return DictationSessionResult(
            text: result.text,
            rawTranscript: rawSegments.joined(separator: " "),
            context: context,
            timing: timing
        )
    }

    public func cancel() async {
        await asrBackend.cancel()
        state = .cancelled
    }

    private func processStableSegments(isFinal: Bool) async throws -> EditorResult? {
        guard let context = currentContext else {
            return nil
        }

        let segments = try await asrBackend.stableSegments()
        guard !segments.isEmpty else {
            return nil
        }

        if timing.firstStableSegmentMS == nil {
            timing.firstStableSegmentMS = elapsedSinceStart()
        }

        return try await process(segments.map { StableSegment(text: $0.text, confidence: $0.confidence, isFinal: isFinal || $0.isFinal) }, context: context)
    }

    private func process(_ segments: [StableSegment], context: AppContext) async throws -> EditorResult {
        guard let pipeline else {
            throw LocalTypeError.invalidSessionState("Pipeline is not initialized")
        }

        var latest: EditorResult?
        for segment in segments {
            rawSegments.append(segment.text)
            latest = try await pipeline.processStableSegment(segment, context: context)
        }

        guard let latest else {
            throw LocalTypeError.emptyDictation
        }
        return latest
    }

    private func profileWithRecalledMemories(for context: AppContext, partialText: String) async throws -> DictationProfile {
        let queryText = [context.appName, context.windowTitle, context.nearbyText, partialText]
            .compactMap { $0 }
            .joined(separator: " ")
        let contextualMemories = try await memoryStore.search(
            MemorySearchQuery(
                text: queryText,
                appName: context.appName,
                types: [.vocabulary, .correction, .styleProfile, .formattingPreference],
                limit: configuration.recallLimit,
                localOnly: configuration.strictOfflineMode
            )
        )
        let globalDictationMemories = try await memoryStore.search(
            MemorySearchQuery(
                text: "",
                types: [.vocabulary, .correction, .formattingPreference],
                limit: configuration.recallLimit,
                localOnly: configuration.strictOfflineMode
            )
        )

        return ProfileMemoryCompiler.enrich(profile, with: dedupeMemories(contextualMemories + globalDictationMemories))
    }

    private func dedupeMemories(_ memories: [DictationMemory]) -> [DictationMemory] {
        var seen: Set<String> = []
        var result: [DictationMemory] = []

        for memory in memories {
            let key = memory.id ?? "\(memory.type.rawValue):\(memory.payload.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "|"))"
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            result.append(memory)
        }

        return result
    }

    private func elapsedSinceStart() -> Int? {
        startedAt.map { Int(Date().timeIntervalSince($0) * 1000) }
    }
}
