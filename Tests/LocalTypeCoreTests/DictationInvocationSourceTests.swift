import XCTest
@testable import LocalTypeCore

final class DictationInvocationSourceTests: XCTestCase {
    func testInAppControlKeepsTranscriptInQuietType() {
        XCTAssertTrue(DictationInvocationSource.inAppControl.forcesPreviewOnly)
        XCTAssertFalse(DictationInvocationSource.inAppControl.usesExternalApplicationTarget)
    }

    func testGlobalShortcutTargetsTheExternalApplication() {
        XCTAssertFalse(DictationInvocationSource.globalShortcut.forcesPreviewOnly)
        XCTAssertTrue(DictationInvocationSource.globalShortcut.usesExternalApplicationTarget)
    }
}
