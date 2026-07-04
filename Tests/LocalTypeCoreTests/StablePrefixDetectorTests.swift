import XCTest
@testable import LocalTypeCore

final class StablePrefixDetectorTests: XCTestCase {
    func testLeavesTrailingWordsUnstable() {
        let detector = StablePrefixDetector(minimumSharedSuffixDrop: 2)

        let stable = detector.stablePrefix(
            previousPartial: "tell najwa the SAGE benchmark needs to",
            currentPartial: "tell najwa the SAGE benchmark needs to rerun"
        )

        XCTAssertEqual(stable, "tell najwa the SAGE benchmark")
    }
}
