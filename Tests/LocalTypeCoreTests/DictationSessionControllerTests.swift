import XCTest
@testable import LocalTypeCore

final class DictationSessionControllerTests: XCTestCase {
    func testFinishAndInsertRunsLocalDictationLoop() async throws {
        let asr = TranscriptASRBackend(transcript: "the sage benchmark needs comet b f t latency numbers")
        let inserter = BufferingTextInserter()
        let controller = DictationSessionController(
            profile: .development,
            asrBackend: asr,
            contextCollector: StaticContextCollector(context: AppContext(appName: "Slack", profile: .messaging)),
            inserter: inserter,
            semanticEditor: RuleBasedSemanticEditor()
        )

        try await controller.begin()
        let result = try await controller.finishAndInsert()
        let state = await controller.currentState()
        let insertedText = await inserter.lastInsertedText()

        XCTAssertEqual(state, .completed)
        XCTAssertEqual(result.text, "The SAGE benchmark needs CometBFT latency numbers.")
        XCTAssertEqual(insertedText, result.text)
        XCTAssertNotNil(result.timing.keyReleaseToInsertMS)
    }

    func testBeginBlocksSecureInputBeforeASRStarts() async throws {
        let controller = DictationSessionController(
            profile: .development,
            asrBackend: TranscriptASRBackend(transcript: "secret"),
            contextCollector: StaticContextCollector(context: AppContext(appName: "Password Manager", isSecureInput: true)),
            inserter: BufferingTextInserter(),
            semanticEditor: RuleBasedSemanticEditor()
        )

        do {
            try await controller.begin()
            XCTFail("Expected secure input to be blocked")
        } catch LocalTypeError.secureInputBlocked("Password Manager") {
            let state = await controller.currentState()
            XCTAssertEqual(state, .failed)
        }
    }

    func testMemoryRecallEnrichesProfileBeforeCorrection() async throws {
        let memoryStore = SQLiteMemoryStore()
        _ = try await memoryStore.put(
            DictationMemory(
                type: .correction,
                payload: ["raw": "all llama", "corrected": "Ollama"],
                contexts: ["Cursor", "local model"],
                source: "explicit_user_instruction",
                confidence: 0.94
            )
        )

        let inserter = BufferingTextInserter()
        let controller = DictationSessionController(
            profile: DictationProfile(vocabulary: [], confusions: []),
            asrBackend: TranscriptASRBackend(transcript: "use all llama for local inference"),
            contextCollector: StaticContextCollector(context: AppContext(appName: "Cursor", profile: .codeEditor)),
            inserter: inserter,
            memoryStore: memoryStore,
            semanticEditor: RuleBasedSemanticEditor()
        )

        try await controller.begin()
        let result = try await controller.finishAndInsert()
        let insertedText = await inserter.lastInsertedText()

        XCTAssertTrue(result.text.contains("Ollama"))
        XCTAssertEqual(insertedText, result.text)
    }

    func testBeginPassesMemoryEnrichedProfileToASR() async throws {
        let memoryStore = SQLiteMemoryStore()
        _ = try await memoryStore.put(
            DictationMemory(
                type: .vocabulary,
                payload: [
                    "term": "CometBFT",
                    "preferred": "CometBFT",
                    "spoken_forms": "comet b f t"
                ],
                contexts: ["Cursor"],
                source: "quiettype_voice_training",
                confidence: 0.94
            )
        )

        let asr = CapturingASRBackend(transcript: "comet b f t")
        let controller = DictationSessionController(
            profile: DictationProfile(vocabulary: [], confusions: []),
            asrBackend: asr,
            contextCollector: StaticContextCollector(context: AppContext(appName: "Cursor", profile: .codeEditor)),
            inserter: BufferingTextInserter(),
            memoryStore: memoryStore,
            semanticEditor: RuleBasedSemanticEditor()
        )

        try await controller.begin()
        let profile = await asr.startedProfile

        XCTAssertTrue(profile?.vocabulary.contains { $0.preferredSpelling == "CometBFT" } == true)
        await controller.cancel()
    }

    func testBeginUsesSetupVocabularyAcrossApps() async throws {
        let memoryStore = SQLiteMemoryStore()
        _ = try await memoryStore.put(
            DictationMemory(
                type: .vocabulary,
                payload: [
                    "term": "CometBFT",
                    "preferred": "CometBFT",
                    "spoken_forms": "comet b f t"
                ],
                contexts: ["voice_calibration", "Notes"],
                source: "quiettype_voice_training",
                confidence: 0.94
            )
        )

        let inserter = BufferingTextInserter()
        let controller = DictationSessionController(
            profile: DictationProfile(vocabulary: [], confusions: []),
            asrBackend: TranscriptASRBackend(transcript: "rerun comet b f t latency numbers"),
            contextCollector: StaticContextCollector(context: AppContext(appName: "Slack", profile: .messaging)),
            inserter: inserter,
            memoryStore: memoryStore,
            semanticEditor: RuleBasedSemanticEditor()
        )

        try await controller.begin()
        let result = try await controller.finishAndInsert()

        XCTAssertEqual(result.text, "Rerun CometBFT latency numbers.")
    }

    func testCancelStopsSessionBeforeInsert() async throws {
        let inserter = BufferingTextInserter()
        let controller = DictationSessionController(
            profile: .development,
            asrBackend: TranscriptASRBackend(transcript: "hello"),
            contextCollector: StaticContextCollector(context: AppContext(appName: "Notes", profile: .notes)),
            inserter: inserter,
            semanticEditor: RuleBasedSemanticEditor()
        )

        try await controller.begin()
        await controller.cancel()
        let state = await controller.currentState()
        let insertedText = await inserter.lastInsertedText()

        XCTAssertEqual(state, .cancelled)
        XCTAssertNil(insertedText)
    }
}

private actor CapturingASRBackend: ASRBackend {
    private let transcript: String
    private(set) var startedProfile: DictationProfile?

    init(transcript: String) {
        self.transcript = transcript
    }

    func startSession(profile: DictationProfile) async throws {
        startedProfile = profile
    }

    func pushAudio(_ frame: AudioFrame) async throws {}

    func partialTranscript() async throws -> String {
        transcript
    }

    func stableSegments() async throws -> [StableSegment] {
        [StableSegment(text: transcript, isFinal: false)]
    }

    func finish() async throws -> [StableSegment] {
        [StableSegment(text: transcript, isFinal: true)]
    }

    func cancel() async {}
}
