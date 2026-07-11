import XCTest
@testable import LocalTypeCore

final class QuietTypeReleaseVersionTests: XCTestCase {
    func testOrdersBetaReleaseCandidateAndStableChannels() throws {
        let beta26 = try XCTUnwrap(QuietTypeReleaseVersion.parse("v1.0.0-beta.26"))
        let rc1 = try XCTUnwrap(QuietTypeReleaseVersion.parse("v1.0.0-rc.1"))
        let rc2 = try XCTUnwrap(QuietTypeReleaseVersion.parse("v1.0.0-rc.2"))
        let stable = try XCTUnwrap(QuietTypeReleaseVersion.parse("v1.0.0"))

        XCTAssertLessThan(beta26, rc1)
        XCTAssertLessThan(rc1, rc2)
        XCTAssertLessThan(rc2, stable)
    }

    func testParsesTagAndArtifactNamesWithExpectedLabels() throws {
        XCTAssertEqual(
            QuietTypeReleaseVersion.parse("v1.0.0-rc.1")?.displayLabel,
            "v1.0.0 RC1"
        )
        XCTAssertEqual(
            QuietTypeReleaseVersion.parse("QuietType-1.0.0-beta.26-macOS-arm64.dmg")?.displayLabel,
            "v1.0.0 beta.26"
        )
        XCTAssertEqual(
            QuietTypeReleaseVersion.parse("QuietType-1.0.0-macOS-arm64.dmg")?.displayLabel,
            "v1.0.0"
        )
    }

    func testRejectsMalformedOrUnknownVersions() {
        for value in [
            "v1.0",
            "v1.x.0-rc.1",
            "v1.0.0-rc",
            "v1.0.0-rc.0",
            "v1.0.0-rc.nope",
            "v1.0.0-preview.1",
            "v1.0.0-rc.1-extra"
        ] {
            XCTAssertNil(QuietTypeReleaseVersion.parse(value), value)
        }
    }
}
