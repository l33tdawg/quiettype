import XCTest
@testable import LocalTypeCore

final class DictationPipelineTests: XCTestCase {
    func testBlocksSecureInput() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Password Manager", profile: .balanced, isSecureInput: true)

        do {
            _ = try await pipeline.finish(unstableTail: "hello", context: context)
            XCTFail("Expected secure input to be blocked")
        } catch LocalTypeError.secureInputBlocked("Password Manager") {
            // Expected.
        }
    }

    func testFormatsNotesShoppingList() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "for the shopping list get milk eggs bread apples and greek yogurt", isFinal: true),
            context: context
        )

        XCTAssertTrue(result.text.contains("- Milk"))
        XCTAssertTrue(result.text.contains("- Eggs"))
        XCTAssertTrue(result.text.contains("- Greek"))
    }

    func testFormatsShoppingIntentAsBulletsOutsideNotes() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Messages", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "we are going shopping we need milk eggs bread and greek yogurt", isFinal: true),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            - Milk
            - Eggs
            - Bread
            - Greek yogurt
            """
        )
    }

    func testFormatsExplicitNumberedList() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "make a numbered list number one review the article number two tighten the intro number three add one concrete example", isFinal: true),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            1. Review the article
            2. Tighten the intro
            3. Add 1 concrete example
            """
        )
    }

    func testNormalizesSpokenNumbersInLists() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "shopping list three apples two bananas and one orange juice", isFinal: true),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            - 3 apples
            - 2 bananas
            - 1 orange juice
            """
        )
    }

    func testExtractsEmbeddedGroceryItemsFromConversationalRequest() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Messages", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "once you make the booking can you also see if we can make a grocery order because we need some couple of things I think I need cabbage corn and milk hang on",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            Once you make the booking can you also see if we can make a grocery order.

            We need:
            - Cabbage
            - Corn
            - Milk
            """
        )
    }

    func testCleansMessyGroceryCorrectionsAndDuplicates() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Messages", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "I have a make washing liquid, sponges. Make washing liquid? No, I mean the plates. Plates washing liquid. Sponges. Sponges already. What else? Oat milk. Already. Might as well order chisels, snacks. Chisels and snacks.",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            - Dishwashing liquid
            - Sponges
            - Oat milk
            - Chips
            - Snacks
            """
        )
    }
}
