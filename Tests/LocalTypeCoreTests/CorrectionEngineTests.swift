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
}
