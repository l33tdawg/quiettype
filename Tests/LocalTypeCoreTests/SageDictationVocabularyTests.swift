import XCTest
@testable import LocalTypeCore

final class SageDictationVocabularyTests: XCTestCase {
    private let remembered = [
        "The VANTARAQ dashboard needs review.",
        "QuietType owns the shortcut.",
        "VANTARAQ pricing still needs work.",
        "SAGE runs on CometBFT.",
        "Assign voice-interface to Mynah.",
        "VANTARAQ and QuietType both appear here."
    ]

    func testMinedVocabularyRepairsSplitCoinages() {
        let profile = ProfileMemoryCompiler.enrich(
            DictationProfile(),
            with: SageDictationVocabulary.memories(fromRemembered: remembered)
        )
        let engine = CorrectionEngine(profile: profile)

        XCTAssertEqual(engine.apply(to: "the Quiet Type shortcut"), "the QuietType shortcut")
        XCTAssertEqual(engine.apply(to: "SAGE runs on Comet BFT"), "SAGE runs on CometBFT")
        XCTAssertEqual(engine.apply(to: "assign voice interface"), "assign voice-interface")
    }

    func testPhoneticMishearingStillRequiresExplicitCorrection() {
        let profile = ProfileMemoryCompiler.enrich(
            DictationProfile(),
            with: SageDictationVocabulary.memories(fromRemembered: remembered)
        )

        XCTAssertEqual(
            CorrectionEngine(profile: profile).apply(to: "the Vantirac dashboard"),
            "the Vantirac dashboard"
        )
    }

    func testCoinageFilterLeavesOrdinaryLanguageAlone() {
        for coined in ["QuietType", "CometBFT", "VANTARAQ", "voice-interface", "sage.dev"] {
            XCTAssertTrue(SageDictationVocabulary.isCoinage(coined), coined)
        }

        for ordinary in ["the", "Friday", "Mynah", "AI", "US", "2026", "11.14.2", "e.g", "i.e"] {
            XCTAssertFalse(SageDictationVocabulary.isCoinage(ordinary), ordinary)
        }
    }

    func testRankingCountsSeparateMemoriesAndHonorsLimit() {
        let repeatedInOne = [
            "FOOBAR FOOBAR FOOBAR",
            "BAZQUX appears here.",
            "BAZQUX appears again."
        ]
        XCTAssertEqual(
            SageDictationVocabulary.ranked(fromRemembered: repeatedInOne).first?.term,
            "BAZQUX"
        )

        let many = (0..<100).map { "TERM\($0)X is a coined term." }
        XCTAssertEqual(
            SageDictationVocabulary.memories(fromRemembered: many, limit: 10).count,
            10
        )
    }

    func testLocalReviewExtractionUsesPolishedTextNotRawASR() {
        let transcript = DictationMemory(
            type: .transcriptNote,
            payload: [
                "raw_transcript": "the quiet type shortcut",
                "polished_text": "The QuietType shortcut"
            ],
            source: "review",
            confidence: 0.82
        )
        let correction = DictationMemory(
            type: .correction,
            payload: ["raw": "quiet type", "corrected": "QuietType"],
            source: "review",
            confidence: 0.95
        )

        XCTAssertEqual(
            SageDictationVocabulary.rememberedTexts(from: [transcript, correction]),
            ["The QuietType shortcut"]
        )
    }

    func testEmptyOrOrdinaryMemoriesDoNotChangeProfile() {
        XCTAssertTrue(SageDictationVocabulary.memories(fromRemembered: []).isEmpty)
        XCTAssertTrue(
            SageDictationVocabulary.memories(
                fromRemembered: ["He wants to buy bread on Friday."]
            ).isEmpty
        )
    }
}
