import XCTest
@testable import LocalTypeCore

final class CorrectionEngineTests: XCTestCase {
    func testAppliesVocabularyAndKnownConfusions() {
        let engine = CorrectionEngine(profile: .development)

        let corrected = engine.apply(to: "the sage benchmark needs comet b f t and ultimate go see as e one hundred with ed twenty five five nineteen")

        XCTAssertTrue(corrected.contains("SAGE"))
        XCTAssertTrue(corrected.contains("CometBFT"))
        XCTAssertTrue(corrected.contains("Utimaco"))
        XCTAssertTrue(corrected.contains("CSe100"))
        XCTAssertTrue(corrected.contains("Ed25519"))
    }

    func testDoesNotReplaceVocabularyInsideLargerWords() {
        let engine = CorrectionEngine(
            profile: DictationProfile(
                vocabulary: [
                    VocabularyEntry(
                        term: "SAGE",
                        spokenForms: ["sage"],
                        preferredSpelling: "SAGE",
                        category: "technical",
                        confidenceBoost: 0.9
                    )
                ],
                confusions: []
            )
        )

        XCTAssertEqual(engine.apply(to: "message sage usage"), "message SAGE usage")
    }

    func testReviewedNameCasingRepairsNearbyAllCapsASRVariant() {
        let engine = CorrectionEngine(
            profile: DictationProfile(
                vocabulary: [],
                confusions: [
                    ASRConfusion(heard: "AMy", corrected: "Amy", contextTerms: [], confidence: 0.93)
                ]
            )
        )

        XCTAssertEqual(engine.apply(to: "I spoke to AMy and then AME."), "I spoke to Amy and then Amy.")
    }

    func testReviewedNameCasingDoesNotFuzzyReplaceOrdinaryLowercaseWords() {
        let engine = CorrectionEngine(
            profile: DictationProfile(
                vocabulary: [],
                confusions: [
                    ASRConfusion(heard: "AMy", corrected: "Amy", contextTerms: [], confidence: 0.93)
                ]
            )
        )

        XCTAssertEqual(engine.apply(to: "any AM and amyloid remain unchanged"), "any AM and amyloid remain unchanged")
    }

    func testRejectsGlobalButToBroCorrectionMemory() {
        let engine = CorrectionEngine(
            profile: DictationProfile(
                vocabulary: [],
                confusions: [
                    ASRConfusion(heard: "but", corrected: "bro", contextTerms: [], confidence: 0.93)
                ]
            )
        )

        XCTAssertEqual(
            engine.apply(to: "Hey bro, I think we did this but just take a look."),
            "Hey bro, I think we did this but just take a look."
        )
    }

    func testRejectsGlobalButToBroVocabularyMemory() {
        let engine = CorrectionEngine(
            profile: DictationProfile(
                vocabulary: [
                    VocabularyEntry(
                        term: "bro",
                        spokenForms: ["but"],
                        preferredSpelling: "bro",
                        category: "review",
                        confidenceBoost: 0.93
                    )
                ],
                confusions: []
            )
        )

        XCTAssertEqual(engine.apply(to: "It is ready but please check."), "It is ready but please check.")
    }

    func testRejectsGlobalBroToButCorrectionMemory() {
        let engine = CorrectionEngine(
            profile: DictationProfile(
                vocabulary: [],
                confusions: [
                    ASRConfusion(heard: "bro", corrected: "but", contextTerms: [], confidence: 0.93)
                ]
            )
        )

        XCTAssertEqual(engine.apply(to: "Thanks bro for checking."), "Thanks bro for checking.")
    }
}
