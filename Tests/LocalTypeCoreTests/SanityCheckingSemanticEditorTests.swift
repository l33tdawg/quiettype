import XCTest
@testable import LocalTypeCore

final class SanityCheckingSemanticEditorTests: XCTestCase {
    func testAcceptsContextualCorrectionFromSanityPass() async throws {
        let editor = SanityCheckingSemanticEditor(
            primary: RuleBasedSemanticEditor(),
            sanityEditor: FixedSemanticEditor(
                text: "Let's do a deep dive into the heuristics and see how we can improve this paragraph breaking stuff and the logical sentence boundaries for long prose."
            )
        )

        let result = try await editor.edit(
            EditorRequest(
                stableText: "let's do a deep dive into the heuristics and see how we can improve this paragraph baking stuff and the logical sentence boundaries for long prose",
                appContext: AppContext(appName: "Slack", profile: .messaging),
                profile: .development,
                isFinal: true
            )
        )

        XCTAssertEqual(
            result.text,
            "Let's do a deep dive into the heuristics and see how we can improve this paragraph breaking stuff and the logical sentence boundaries for long prose."
        )
    }

    func testFallsBackWhenSanityPassIntroducesUnsupportedList() async throws {
        let editor = SanityCheckingSemanticEditor(
            primary: RuleBasedSemanticEditor(),
            sanityEditor: FixedSemanticEditor(
                text: """
                - I think we should detect the word number.
                - The next couple of items would probably be list items.
                """
            )
        )

        let result = try await editor.edit(
            EditorRequest(
                stableText: "I think we should detect instead for the utterance of the word like number followed by the numeral because I think that's probably what's a better indicator right so when I say I want to yeah it's obvious after that the next couple of items would probably be the items on the list right I mean that's kind of logical makes sense to me",
                appContext: AppContext(appName: "Slack", profile: .messaging),
                profile: .development,
                isFinal: true
            )
        )

        XCTAssertFalse(result.text.contains("\n- "))
        XCTAssertEqual(
            result.text,
            "I think we should detect instead for the utterance of the word like number followed by the numeral because I think that's probably what's a better indicator right so when I say I want to yeah it's obvious after that the next couple of items would probably be the items on the list right I mean that's kind of logical makes sense to me."
        )
    }

    func testFallsBackWhenSanityPassDropsProtectedVocabulary() async throws {
        let editor = SanityCheckingSemanticEditor(
            primary: RuleBasedSemanticEditor(),
            sanityEditor: FixedSemanticEditor(text: "Please check memory status.")
        )

        let result = try await editor.edit(
            EditorRequest(
                stableText: "please check SAGE memory status",
                appContext: AppContext(appName: "Slack", profile: .messaging),
                profile: .development,
                isFinal: true
            )
        )

        XCTAssertEqual(result.text, "Please check SAGE memory status.")
    }

    func testFallsBackWhenSanityPassThrows() async throws {
        let editor = SanityCheckingSemanticEditor(
            primary: RuleBasedSemanticEditor(),
            sanityEditor: ThrowingSemanticEditor()
        )

        let result = try await editor.edit(
            EditorRequest(
                stableText: "maybe we should replace it with something clearer",
                appContext: AppContext(appName: "Slack", profile: .messaging),
                profile: .development,
                isFinal: true
            )
        )

        XCTAssertEqual(result.text, "Maybe we should replace it with something clearer.")
    }
}

private struct FixedSemanticEditor: SemanticEditor {
    let text: String

    func edit(_ request: EditorRequest) async throws -> EditorResult {
        EditorResult(text: text, latencyMS: 7)
    }
}

private struct ThrowingSemanticEditor: SemanticEditor {
    func edit(_ request: EditorRequest) async throws -> EditorResult {
        throw TestSanityEditorError.failed
    }
}

private enum TestSanityEditorError: Error {
    case failed
}
