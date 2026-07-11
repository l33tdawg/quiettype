import XCTest
@testable import LocalTypeCore

final class ASRPromptBuilderTests: XCTestCase {
    func testBuildsCompactPromptFromVocabularyOnlyByDefault() {
        let profile = DictationProfile(
            vocabulary: [
                VocabularyEntry(term: "CometBFT", spokenForms: ["comet b f t"], preferredSpelling: "CometBFT", category: "technical", confidenceBoost: 0.95),
                VocabularyEntry(term: "Ollama", spokenForms: ["all llama"], preferredSpelling: "Ollama", category: "technical", confidenceBoost: 0.93)
            ],
            confusions: [
                ASRConfusion(heard: "all llama", corrected: "Ollama", contextTerms: ["local models"], confidence: 0.96),
                ASRConfusion(heard: "comet beef tea", corrected: "CometBFT", contextTerms: ["SAGE"], confidence: 0.94)
            ]
        )

        let prompt = ASRPromptBuilder().prompt(for: profile, appName: "Cursor")

        XCTAssertTrue(prompt.contains("Vocabulary: CometBFT, Ollama."))
        XCTAssertFalse(prompt.contains("all llama -> Ollama"))
        XCTAssertFalse(prompt.contains("comet beef tea -> CometBFT"))
        XCTAssertFalse(prompt.contains("Context: dictation into Cursor."))
        XCTAssertTrue(prompt.contains("Preserve exact names"))
    }

    func testLimitsPromptSize() {
        let vocabulary = (0..<30).map {
            VocabularyEntry(term: "Term\($0)", spokenForms: [], preferredSpelling: "Term\($0)", category: "technical", confidenceBoost: 1.0 - Double($0) / 100.0)
        }
        let confusions = (0..<20).map {
            ASRConfusion(heard: "heard \($0)", corrected: "Corrected\($0)", contextTerms: [], confidence: 1.0 - Double($0) / 100.0)
        }

        let prompt = ASRPromptBuilder(maxVocabularyTerms: 3, maxCorrectionPairs: 2)
            .prompt(for: DictationProfile(vocabulary: vocabulary, confusions: confusions))

        XCTAssertTrue(prompt.contains("Vocabulary: Term0, Term1, Term2."))
        XCTAssertTrue(prompt.contains("heard 0 -> Corrected0; heard 1 -> Corrected1."))
        XCTAssertFalse(prompt.contains("Term3"))
        XCTAssertFalse(prompt.contains("heard 2"))
    }

    func testProductionOptionsRemainUnpromptedEvenWithGovernedVocabulary() {
        let profile = DictationProfile(
            vocabulary: [
                VocabularyEntry(
                    term: "SAGE",
                    spokenForms: ["sage"],
                    preferredSpelling: "SAGE",
                    category: "technical",
                    confidenceBoost: 0.95
                )
            ]
        )

        XCTAssertFalse(ASRPromptBuilder().prompt(for: profile).isEmpty)
        let options = ASRPromptBuilder().productionOptions()

        XCTAssertNil(options.initialPrompt)
    }
}
