import XCTest
@testable import LocalTypeCore

final class OllamaSemanticEditorTests: XCTestCase {
    func testRejectsNonLoopbackEndpointThroughFallback() async throws {
        let editor = OllamaSemanticEditor(
            endpoint: URL(string: "https://example.com/api/generate")!,
            model: "test",
            fallback: nil
        )

        let request = EditorRequest(
            stableText: "hello",
            appContext: AppContext(appName: "Tests", profile: .balanced),
            profile: .development,
            isFinal: true
        )

        do {
            _ = try await editor.edit(request)
            XCTFail("Expected non-loopback endpoint to be rejected")
        } catch OllamaEditorError.nonLoopbackEndpoint("https://example.com/api/generate") {
            // Expected.
        }
    }

    func testNonLoopbackEndpointCanFallBackToRuleEditor() async throws {
        let editor = OllamaSemanticEditor(
            endpoint: URL(string: "https://example.com/api/generate")!,
            model: "test",
            fallback: RuleBasedSemanticEditor()
        )

        let request = EditorRequest(
            stableText: "hello from local dictation",
            appContext: AppContext(appName: "Tests", profile: .balanced),
            profile: .development,
            isFinal: true
        )

        let result = try await editor.edit(request)
        XCTAssertEqual(result.text, "Hello from local dictation.")
    }
}
