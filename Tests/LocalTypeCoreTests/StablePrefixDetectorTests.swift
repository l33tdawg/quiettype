import XCTest
@testable import LocalTypeCore

final class StablePrefixDetectorTests: XCTestCase {
    func testLeavesTrailingWordsUnstable() {
        let detector = StablePrefixDetector(minimumSharedSuffixDrop: 2)

        let stable = detector.stablePrefix(
            previousPartial: "tell Sarah the SAGE benchmark needs to",
            currentPartial: "tell Sarah the SAGE benchmark needs to rerun"
        )

        XCTAssertEqual(stable, "tell Sarah the SAGE benchmark")
    }
}
