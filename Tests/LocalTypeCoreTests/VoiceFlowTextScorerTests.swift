import XCTest
@testable import LocalTypeCore

final class VoiceFlowTextScorerTests: XCTestCase {
    func testScoresWordErrorsAndRequiredTerms() {
        let score = VoiceFlowTextScorer.score(
            reference: "The SAGE benchmark needs CometBFT latency numbers",
            hypothesis: "The sage benchmark needs comet latency number",
            requiredTerms: ["SAGE", "CometBFT"]
        )

        XCTAssertEqual(score.referenceWordCount, 7)
        XCTAssertEqual(score.hypothesisWordCount, 7)
        XCTAssertEqual(score.wordErrorCount, 2)
        XCTAssertEqual(score.wordErrorRate, 2.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(score.requiredTermCount, 2)
        XCTAssertEqual(score.matchedRequiredTermCount, 1)
        XCTAssertEqual(score.requiredTermAccuracy, 0.5)
    }

    func testEmptyReferenceHasBoundedWordErrorRate() {
        XCTAssertEqual(VoiceFlowTextScorer.score(reference: "", hypothesis: "").wordErrorRate, 0)
        XCTAssertEqual(VoiceFlowTextScorer.score(reference: "", hypothesis: "noise").wordErrorRate, 1)
    }
}
