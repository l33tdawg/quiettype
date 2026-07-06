import XCTest
@testable import LocalTypeCore

final class ProfileMemoryCompilerTests: XCTestCase {
    func testCompilesSetupVocabularyCorrectionsAndCadenceIntoProfile() {
        let memories = [
            DictationMemory(
                type: .vocabulary,
                payload: [
                    "term": "CometBFT",
                    "preferred": "CometBFT",
                    "spoken_forms": "comet b f t, comet bee eff tee",
                    "estimated_wpm": "186",
                    "raw_transcript": "comet beef tea"
                ],
                contexts: ["voice_calibration"],
                source: "quiettype_voice_training",
                confidence: 0.94
            ),
            DictationMemory(
                type: .correction,
                payload: ["raw": "all llama", "corrected": "Ollama"],
                contexts: ["local models"],
                source: "user_teaching",
                confidence: 0.96
            ),
            DictationMemory(
                type: .transcriptNote,
                payload: [
                    "raw_transcript": "ultimate go",
                    "polished_text": "Utimaco"
                ],
                contexts: ["dictation_review"],
                source: "quiettype_dictation_turn",
                confidence: 0.82
            )
        ]

        let profile = ProfileMemoryCompiler.enrich(
            DictationProfile(speechRateWPM: 148, vocabulary: [], confusions: []),
            with: memories
        )

        XCTAssertEqual(profile.speechRateWPM, 186)
        XCTAssertEqual(profile.pauseThresholdMS, 330)
        XCTAssertTrue(profile.vocabulary.contains { $0.preferredSpelling == "CometBFT" && $0.spokenForms.contains("comet b f t") })
        XCTAssertTrue(profile.confusions.contains { $0.heard == "all llama" && $0.corrected == "Ollama" })
        XCTAssertTrue(profile.confusions.contains { $0.corrected == "CometBFT" })
        XCTAssertFalse(profile.confusions.contains { $0.heard == "ultimate go" && $0.corrected == "Utimaco" })
    }

    func testCorrectionMemoryAddsRecordedSpokenForms() {
        let memories = [
            DictationMemory(
                type: .correction,
                payload: [
                    "raw": "steven",
                    "corrected": "Stephen",
                    "spoken_forms": "steven, stephen, seven"
                ],
                contexts: ["pronunciation_training"],
                source: "user_teaching",
                confidence: 0.95
            )
        ]

        let profile = ProfileMemoryCompiler.enrich(
            DictationProfile(speechRateWPM: 148, vocabulary: [], confusions: []),
            with: memories
        )

        XCTAssertTrue(profile.confusions.contains { $0.heard == "steven" && $0.corrected == "Stephen" })
        XCTAssertTrue(profile.confusions.contains { $0.heard == "stephen" && $0.corrected == "Stephen" })
        XCTAssertTrue(profile.confusions.contains { $0.heard == "seven" && $0.corrected == "Stephen" })
    }
}
