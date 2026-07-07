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

    func testPreservesLikeWhenItCarriesMeaningInProse() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Slack", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "there's a lot of space in the left bar that we should be able to make the icons bigger for home and review and maybe the text also more prominent so it looks like a real menu item and not just a subheading kind of thing", isFinal: true),
            context: context
        )

        XCTAssertTrue(result.text.localizedCaseInsensitiveContains("looks like a real menu item"))
    }

    func testProfanityFilterMasksExplicitWordsByDefault() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Slack", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "this is fucking annoying", isFinal: true),
            context: context
        )

        XCTAssertEqual(result.text, "This is f***ing annoying.")
    }

    func testProfanityFilterCanBeDisabled() async throws {
        let profile = DictationProfile(profanityFilterEnabled: false)
        let pipeline = DictationPipeline(profile: profile, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Slack", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "this is fucking annoying", isFinal: true),
            context: context
        )

        XCTAssertEqual(result.text, "This is fucking annoying.")
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

    func testFormatsBareNumberedMarkersAsNumberedList() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "number one review the article number two tighten the intro number three add one concrete example", isFinal: true),
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

    func testFormatsBareTwoItemNumberedMarkersAsNumberedList() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "number one review the article number two tighten the intro", isFinal: true),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            1. Review the article
            2. Tighten the intro
            """
        )
    }

    func testFormatsBulletListIntentAsBullets() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "bullet list bullet point review the article bullet point tighten the intro bullet point add one concrete example", isFinal: true),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            - Review the article
            - Tighten the intro
            - Add 1 concrete example
            """
        )
    }

    func testFormatsExplicitBulletListWithBareItems() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "bullet list apples bananas carrots", isFinal: true),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            - Apples
            - Bananas
            - Carrots
            """
        )
    }

    func testFormatsBareBulletMarkersAsBullets() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "bullet review the article bullet tighten the intro bullet add one concrete example", isFinal: true),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            - Review the article
            - Tighten the intro
            - Add 1 concrete example
            """
        )
    }

    func testFormatsNumberedMarkersBeyondFive() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "number one alpha number two beta number three gamma number four delta number five epsilon number six zeta", isFinal: true),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            1. Alpha
            2. Beta
            3. Gamma
            4. Delta
            5. Epsilon
            6. Zeta
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

    func testGroupsDigitQuantityItemsInsteadOfBulletingEveryWord() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "shopping list 1 apples 2 onions 3 cucumber 4 garlic", isFinal: true),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            - 1 apples
            - 2 onions
            - 3 cucumber
            - 4 garlic
            """
        )
    }

    func testDoesNotTreatOrdinaryNumberedNotesAsShoppingList() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "review 2 options and 3 risks before the meeting", isFinal: true),
            context: context
        )

        XCTAssertEqual(result.text, "Review 2 options and 3 risks before the meeting.")
    }

    func testDropsConversationalLeadInAndTailAroundDigitQuantityList() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "so let's do a menu 1 apples 2 onions 3 cucumber 4 garlic that's it from the supermarket", isFinal: true),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            - 1 apples
            - 2 onions
            - 3 cucumber
            - 4 garlic
            """
        )
    }

    func testFormatsSetupVoiceTrainingShoppingSentenceAsQuantityList() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "for the shopping list get three apples two bananas oat milk dishwashing liquid and greek yogurt", isFinal: true),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            - 3 apples
            - 2 bananas
            - Oat milk
            - Dishwashing liquid
            - Greek yogurt
            """
        )
    }

    func testFormatsOrdinalNumberedListWithoutDroppingItemVerbs() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "numbered list first add milk second review the article third make the examples concrete", isFinal: true),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            1. Add milk
            2. Review the article
            3. Make the examples concrete
            """
        )
    }

    func testFinishWithEmptyTailPreservesStableListFormatting() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        _ = try await pipeline.processStableSegment(
            StableSegment(text: "shopping list milk eggs bread and greek yogurt", isFinal: false),
            context: context
        )
        let result = try await pipeline.finish(unstableTail: "", context: context)

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

    func testTreatsSpokenNewLineAsListDelimiter() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "shopping list new line eggs new line oat milk new line dishwashing liquid", isFinal: true),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            - Eggs
            - Oat milk
            - Dishwashing liquid
            """
        )
    }

    func testDoesNotConvertApprovalRequestIntoShoppingList() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Slack", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "need to get approval from Alice and Bob before we ship", isFinal: true),
            context: context
        )

        XCTAssertEqual(result.text, "Need to get approval from Alice and Bob before we ship.")
    }

    func testFormatsSpokenParagraphBreaksInProse() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "first thought the settings page should feel calmer new paragraph second thought the memory status belongs below the dictation controls",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            First thought the settings page should feel calmer.

            Second thought the memory status belongs below the dictation controls.
            """
        )
    }

    func testGroupsLongProseIntoLogicalParagraphs() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "the launch is close but the settings page still feels cluttered the key problem is that readiness memory and updates are competing with the actual controls the next step is to put dictation controls first and move status information into compact cards below finally keep the release notes focused on the version and the memory recovery fix",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            The launch is close but the settings page still feels cluttered.

            The key problem is that readiness memory and updates are competing with the actual controls.

            The next step is to put dictation controls first and move status information into compact cards below.

            Finally keep the release notes focused on the version and the memory recovery fix.
            """
        )
    }

    func testPreservesParagraphBreaksAcrossStableSegments() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        _ = try await pipeline.processStableSegment(
            StableSegment(
                text: "first thought the settings page should feel calmer new paragraph second thought the memory status belongs below the dictation controls",
                isFinal: false
            ),
            context: context
        )
        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "the next step is to keep updates in a compact version card",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            First thought the settings page should feel calmer.

            Second thought the memory status belongs below the dictation controls.

            The next step is to keep updates in a compact version card.
            """
        )
    }

    func testFormatsEmailIntoGreetingBodyAndSignoffParagraphs() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Mail", profile: .email)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "hi Maya comma thanks for meeting today period please send the Utimaco quote and the CSe100 data sheet before Friday period I will review the Ed25519 signing requirements after that period best comma Lee",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            Hi Maya,

            Thanks for meeting today. Please send the Utimaco quote and the CSe100 data sheet before Friday. I will review the Ed25519 signing requirements after that.

            Best, Lee.
            """
        )
    }

    func testFormatsExplicitEmailParagraphGreeting() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Mail", profile: .email)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "hi Maya comma new paragraph thanks for meeting today period new paragraph best comma Lee",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            Hi Maya,

            Thanks for meeting today.

            Best, Lee.
            """
        )
    }

    func testKeepsEmailBodyAfterGreetingInExplicitParagraph() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Mail", profile: .email)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "hi Maya comma thanks for meeting today new paragraph best comma Lee",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            Hi Maya,

            Thanks for meeting today.

            Best, Lee.
            """
        )
    }

    func testDoesNotSplitAbbreviationsOrDecimalTimesIntoParagraphs() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "meet Dr. Smith at 3.30 p.m. tomorrow", isFinal: true),
            context: context
        )

        XCTAssertEqual(result.text, "Meet Dr. Smith at 3.30 p.m. tomorrow.")
    }

    func testAppliesBritishSpellingPreference() async throws {
        let profile = DictationProfile(spellingPreference: .british)
        let pipeline = DictationPipeline(profile: profile, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .balanced)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "my favorite color is gray and we should organize the notes", isFinal: true),
            context: context
        )

        XCTAssertEqual(result.text, "My favourite colour is grey and we should organise the notes.")
    }

    func testAppliesAmericanSpellingPreference() async throws {
        let profile = DictationProfile(spellingPreference: .american)
        let pipeline = DictationPipeline(profile: profile, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .balanced)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "my favourite colour is grey and we should organise the notes", isFinal: true),
            context: context
        )

        XCTAssertEqual(result.text, "My favorite color is gray and we should organize the notes.")
    }

    func testRemovesCancelledGroceryItems() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "for the shopping list get milk eggs bread bananas actually no bananas apples and greek yogurt", isFinal: true),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            - Milk
            - Eggs
            - Bread
            - Apples
            - Greek yogurt
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
