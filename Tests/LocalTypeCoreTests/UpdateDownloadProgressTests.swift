import XCTest
@testable import LocalTypeCore

final class UpdateDownloadProgressTests: XCTestCase {
    func testFormatsKnownDownloadSizeWithPercentageAndCounter() {
        let progress = UpdateDownloadProgress(
            bytesDownloaded: 249_036_800,
            totalBytesExpected: 498_073_600
        )

        XCTAssertEqual(progress.fractionCompleted, 0.5)
        XCTAssertEqual(progress.displayText, "50% · 238 MB of 475 MB")
    }

    func testFallsBackToDownloadedCounterWhenTotalIsUnknown() {
        let progress = UpdateDownloadProgress(
            bytesDownloaded: 12_582_912,
            totalBytesExpected: nil
        )

        XCTAssertNil(progress.fractionCompleted)
        XCTAssertEqual(progress.displayText, "12 MB downloaded")
    }

    func testClampsInvalidAndOverflowingProgress() {
        XCTAssertEqual(
            UpdateDownloadProgress(bytesDownloaded: -10, totalBytesExpected: 0).displayText,
            "0 B downloaded"
        )
        XCTAssertEqual(
            UpdateDownloadProgress(bytesDownloaded: 200, totalBytesExpected: 100).displayText,
            "100% · 200 B of 100 B"
        )
    }
}
