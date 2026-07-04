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

        currentContext = context
        pipeline = DictationPipeline(
            profile: try await profileWithRecalledMemories(for: context, partialText: ""),
            semanticEditor: semanticEditor
        )

        try await asrBackend.startSession(profile: profile)
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
        var enriched = profile
        let queryText = [context.appName, context.windowTitle, context.nearbyText, partialText]
            .compactMap { $0 }
            .joined(separator: " ")
        let memories = try await memoryStore.search(
            MemorySearchQuery(
                text: queryText,
                appName: context.appName,
                types: [.vocabulary, .correction, .styleProfile, .formattingPreference],
                limit: configuration.recallLimit,
                localOnly: configuration.strictOfflineMode
            )
        )

        for memory in memories {
            switch memory.type {
            case .vocabulary:
                if let term = memory.payload["term"] ?? memory.payload["preferred_spelling"] {
                    let spokenForms = memory.payload["spoken_forms"]?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? [term]
                    enriched.vocabulary.append(
                        VocabularyEntry(
                            term: term,
                            spokenForms: spokenForms,
                            preferredSpelling: memory.payload["preferred_spelling"] ?? term,
                            category: "sage_memory",
                            confidenceBoost: memory.confidence
                        )
                    )
                }
            case .correction:
                if let raw = memory.payload["raw"], let corrected = memory.payload["corrected"] {
                    enriched.confusions.append(
                        ASRConfusion(
                            heard: raw,
                            corrected: corrected,
                            contextTerms: memory.contexts,
                            confidence: memory.confidence
                        )
                    )
                }
            case .styleProfile, .formattingPreference:
                continue
            }
        }

        return enriched
    }

    private func elapsedSinceStart() -> Int? {
        startedAt.map { Int(Date().timeIntervalSince($0) * 1000) }
    }
}
