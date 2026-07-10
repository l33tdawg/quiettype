import XCTest
@testable import LocalTypeCore

#if os(macOS)
final class MacOSInsertionTests: XCTestCase {
    func testInsertionFailsClosedWithoutCapturedTargetIdentity() async {
        let context = AppContext(appName: "Unknown")

        do {
            try await ClipboardTextInserter().insert("private transcript", into: context)
            XCTFail("Insertion should reject a context without a captured process identifier.")
        } catch let error as LocalTypeError {
            XCTAssertEqual(
                error,
                .insertionFailed("No target app was captured. Copy the transcript instead.")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
#endif
