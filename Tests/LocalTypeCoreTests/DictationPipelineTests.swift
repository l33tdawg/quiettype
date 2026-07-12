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

    func testPreservesOrdinaryActuallyWithoutDroppingEarlierLongTranscript() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Messages", profile: .messaging)
        let raw = "Given extended DMT there is a new technology called DMTX where DMT is fed directly into the bloodstream by drip. It is possible to keep the individual in the peak DMT state for hours. With DMTX these volunteers actually could be kept in the peak state for hours. Unlike LSD nobody rapidly builds up tolerance."

        let result = try await pipeline.processStableSegment(
            StableSegment(text: raw, isFinal: true),
            context: context
        )

        XCTAssertTrue(result.text.hasPrefix("Given extended DMT"), result.text)
        XCTAssertTrue(result.text.contains("volunteers actually could be kept"), result.text)
        XCTAssertTrue(result.text.hasSuffix("nobody rapidly builds up tolerance."), result.text)
    }

    func testAppliesExplicitSorryCorrectionWithoutDroppingSentencePrefix() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Messages", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "Schedule the benchmark review for Thursday, sorry, Friday at three pm and invite the performance team",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            "Schedule the benchmark review for Friday at 3 PM and invite the performance team."
        )
    }

    func testPreservesSemanticSorryWithoutTreatingItAsCorrection() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Messages", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "I am sorry this took longer than expected", isFinal: true),
            context: context
        )

        XCTAssertEqual(result.text, "I am sorry this took longer than expected.")
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

    func testFormatsDigitNumberedMarkersAsNumberedList() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "number 1 investigate the typing reminder number 2 improve the glass overlay", isFinal: true),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            1. Investigate the typing reminder
            2. Improve the glass overlay
            """
        )
    }

    func testDropsLeadInBeforeNumberedMarkers() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "so I have a couple of items for you to take a look at number 1 this detect typing popup please investigate it number 2 the glass overlay looks better but can we improve it further because I don't see it really implemented in version 18",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            1. This detect typing popup please investigate it
            2. The glass overlay looks better but can we improve it further because I don't see it really implemented in version 18
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

    func testDoesNotSplitTaskBoardProseIntoSingleWordBullets() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Slack", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "also it seems when I assign a task to an agent click Send expect that the card would move into in progress but doesn't just disappears from to do list instead of being moved",
                isFinal: true
            ),
            context: context
        )

        XCTAssertFalse(result.text.contains("\n- "))
        XCTAssertEqual(
            result.text,
            "Also it seems when I assign a task to an agent click Send expect that the card would move into in progress but doesn't just disappears from to do list instead of being moved."
        )
    }

    func testDoesNotFormatDiscussionAboutListsAsList() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Slack", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "I think we should detect instead for the utterance of the word like number followed by the numeral because I think that's probably what's a better indicator right so when I say I want to yeah it's obvious after that the next couple of items would probably be the items on the list right I mean that's kind of logical makes sense to me",
                isFinal: true
            ),
            context: context
        )

        XCTAssertFalse(result.text.contains("\n- "))
        XCTAssertFalse(result.text.contains("\n1. "))
        XCTAssertEqual(
            result.text,
            "I think we should detect instead for the utterance of the word like number followed by the numeral because I think that's probably what's a better indicator right so when I say I want to yeah it's obvious after that the next couple of items would probably be the items on the list right I mean that's kind of logical makes sense to me."
        )
    }

    func testDoesNotSplitMaybeWeShouldIntoStandaloneSentence() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Slack", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "did we address the review section and the fact that on the main page that box doesn't really make sense question mark maybe we should replace it with something else or remove it altogether",
                isFinal: true
            ),
            context: context
        )

        XCTAssertFalse(result.text.contains("Maybe."))
        XCTAssertFalse(result.text.contains("\n\nWe should"))
        XCTAssertEqual(
            result.text,
            "Did we address the review section and the fact that on the main page that box doesn't really make sense? Maybe we should replace it with something else or remove it altogether."
        )
    }

    func testDoesNotInferSentenceBoundaryBeforeInlinePlease() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Slack", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "before you merge the update can you please check the release notes and make sure the download links point to beta nineteen",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            "Before you merge the update can you please check the release notes and make sure the download links point to beta nineteen."
        )
    }

    func testDoesNotCreateParagraphsWithoutTopicShiftCues() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Slack", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "the review number on the overview page is confusing because users do not know whether it means edits corrections or transcript notes and the label does not explain why it matters so maybe we should remove that card or replace it with something clearer like sessions today or words saved this week",
                isFinal: true
            ),
            context: context
        )

        XCTAssertFalse(result.text.contains("\n\n"))
        XCTAssertFalse(result.text.contains("Maybe."))
        XCTAssertEqual(
            result.text,
            "The review number on the overview page is confusing because users do not know whether it means edits corrections or transcript notes and the label does not explain why it matters so maybe we should remove that card or replace it with something clearer like sessions today or words saved this week."
        )
    }

    func testRestoresCapitalizedSentenceBoundariesFromObservedLiveTranscript() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Messages", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "Just trying the new version seems to be quite stable so far No major bugs seen What do you think should we call this 1.0.0 final?",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            "Just trying the new version seems to be quite stable so far. No major bugs seen. What do you think should we call this 1.0.0 final?"
        )
    }

    func testDoesNotSplitCapitalizedQuestionWordsInsideTitles() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "the report is called No Major Bugs Seen the appendix is What We Know Today and the memo is titled Why this happens",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            "The report is called No Major Bugs Seen the appendix is What We Know Today and the memo is titled Why this happens."
        )
    }

    func testRuleEditorDoesNotGuessContextualASRConfusion() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Slack", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "let's do a deep dive into the heuristics and see how we can improve this paragraph baking stuff and the logical sentence boundaries for long prose",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            "Let's do a deep dive into the heuristics and see how we can improve this paragraph baking stuff and the logical sentence boundaries for long prose."
        )
    }

    func testKeepsRealBakingWhenContextIsFood() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "we should improve the baking process for sourdough and write down the oven temperature after each test",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            "We should improve the baking process for sourdough and write down the oven temperature after each test."
        )
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

    func testGroupsObservedExplanatorySpeechIntoLogicalParagraphs() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Messages", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "Japanese or Hebrew, yet these descriptions fail to fully convey the complexity and novelty of this perceived script. What's clear is that it has some visual similarity to scripts we're familiar with, and it's distinctly of unknown origin. Here's where my work in language and semiotics comes in, and the question that I have for anyone who's experienced this phenomenon. I've developed a sound meaning-based writing system called the Abazi, also known as the Universal Language of energy and it looks like this the script identifies the 24 basic sound components of language and their 120 vowel articulations as expressions of the fundamental behaviors of energy that create reality you can think of these symbols as choreography notations for the eternal dance of the cosmos and their designs are a synthesis of 6 000 plus years of semantics wisdom my question for the world is this. Are these the symbols you've been seeing? I'm not going to do the experiment myself because I do not promote drug use of any kind.",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            Japanese or Hebrew, yet these descriptions fail to fully convey the complexity and novelty of this perceived script. What's clear is that it has some visual similarity to scripts we're familiar with, and it's distinctly of unknown origin.

            Here's where my work in language and semiotics comes in, and the question that I have for anyone who's experienced this phenomenon.

            I've developed a sound meaning-based writing system called the Abazi, also known as the Universal Language of energy and it looks like this. The script identifies the 24 basic sound components of language and their 120 vowel articulations as expressions of the fundamental behaviors of energy that create reality. You can think of these symbols as choreography notations for the eternal dance of the cosmos and their designs are a synthesis of 6 000 plus years of semantics wisdom.

            My question for the world is this. Are these the symbols you've been seeing?

            I'm not going to do the experiment myself because I do not promote drug use of any kind.
            """
        )
    }

    func testStartsParagraphWhenLongExplanationSwitchesToSpeakersView() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Messages", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "The same iconography. People paint their visions after ayahuasca sessions. People were painting in Europe, in the cave of Lascaux, for example. And of course they had access to psilocybe mushrooms in prehistoric Europe. There's a remarkable commonality in the imagery that is painted. I like to give credit where credit is due, and there are two names that need to be mentioned here. One is the late great Terence McKenna and his book Food of the Gods, where he proposed the idea very strongly that it was our ancestral encounters with psychedelics that made us fully human. That's what switched on the modern human mind.",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            The same iconography. People paint their visions after ayahuasca sessions. People were painting in Europe, in the cave of Lascaux, for example. And of course they had access to psilocybe mushrooms in prehistoric Europe. There's a remarkable commonality in the imagery that is painted.

            I like to give credit where credit is due, and there are 2 names that need to be mentioned here. One is the late great Terence McKenna and his book Food of the Gods, where he proposed the idea very strongly that it was our ancestral encounters with psychedelics that made us fully human. That's what switched on the modern human mind.
            """
        )
    }

    func testKeepsContinuingFirstPersonSentencesInOneParagraph() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Messages", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "I tested the latest build. It handled the long recording correctly. I also checked the shorter sample and found no regression.",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            "I tested the latest build. It handled the long recording correctly. I also checked the shorter sample and found no regression."
        )
    }

    func testGroupsObservedDMTXExplanationAtStudyAndInterpretationTransitions() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Safari", profile: .balanced)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "Given extended DMT, there's a new technology, DMTX, where the DMT is fed directly into the bloodstream by drip. And it's possible to keep the individual in the peak DMT state, which normally when you smoke or vape DMT, you're looking if you're lucky at 10 minutes, or if you're unlucky, if it's a bad journey, because those 10 minutes can seem like forever, but with the DMTX, with the drip feeding of DMT into the bloodstream, these volunteers actually could be kept in the peak state for hours. And unlike LSD, where you rapidly build up tolerance, nobody ever builds up tolerance to DMT. It always hits you with the same power, even if you took it yesterday and the day before, and you're taking it tomorrow as well, it's still going to have that same power. There's no tolerance there. So that's how they can use that lack of tolerance to keep the volunteers in this state. And then when they debrief those volunteers, they're also putting them in MRI scanners and looking at what's happening in the brain. But when they debrief them, they're all talking about encounters with sentient others. They're exchanging their experiences, and it's all about encounters with sentient others who wish to teach them moral lessons. Now, to me, that's wild. What is going on here? How do we account for this? Yeah, I get the notion of hallucinations and brightly colored visuals, but the moral lessons that come with it, those are very old.",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            """
            Given extended DMT, there's a new technology, DMTX, where the DMT is fed directly into the bloodstream by drip. And it's possible to keep the individual in the peak DMT state, which normally when you smoke or vape DMT, you're looking if you're lucky at 10 minutes, or if you're unlucky, if it's a bad journey, because those 10 minutes can seem like forever, but with the DMTX, with the drip feeding of DMT into the bloodstream, these volunteers actually could be kept in the peak state for hours. And unlike LSD, where you rapidly build up tolerance, nobody ever builds up tolerance to DMT. It always hits you with the same power, even if you took it yesterday and the day before, and you're taking it tomorrow as well, it's still going to have that same power. There's no tolerance there. So that's how they can use that lack of tolerance to keep the volunteers in this state.

            And then when they debrief those volunteers, they're also putting them in MRI scanners and looking at what's happening in the brain. But when they debrief them, they're all talking about encounters with sentient others. They're exchanging their experiences, and it's all about encounters with sentient others who wish to teach them moral lessons.

            Now, to me, that's wild. What is going on here? How do we account for this? Yeah, I get the notion of hallucinations and brightly colored visuals, but the moral lessons that come with it, those are very old.
            """
        )
    }

    func testDoesNotSplitExplanatoryCuesAfterOpenConnectors() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "the diagram remains accurate because the script identifies each sound and you can think of the output as one continuous map",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            "The diagram remains accurate because the script identifies each sound and you can think of the output as one continuous map."
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

    func testAMPMNormalizationDoesNotCorruptNames() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Messages", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "send Amy and Amanda the notes at three pm", isFinal: true),
            context: context
        )

        XCTAssertEqual(result.text, "Send Amy and Amanda the notes at 3 PM.")
    }

    func testKeepsBroLowercaseMidSentenceWhileNormalizingTime() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Messages", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "thanks bro for checking with Amy at nine am", isFinal: true),
            context: context
        )

        XCTAssertEqual(result.text, "Thanks bro for checking with Amy at 9 AM.")
    }

    func testRepairsButMisheardAsBroInObservedFootballContexts() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "Neil has been with Sevilla for the last three years bro just left them this summer period Odegaard harassed a little deeper comma bro that was very composed indeed",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            "Neil has been with Sevilla for the last 3 years but just left them this summer. Odegaard harassed a little deeper, but that was very composed indeed."
        )
    }

    func testPreservesGenuineBroVocativesNearSimilarWords() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Messages", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "bro just check this and tell me comma bro comma that was amazing", isFinal: true),
            context: context
        )

        XCTAssertEqual(result.text, "Bro just check this and tell me, bro, that was amazing.")
    }

    func testRepairsButMisheardAsBroInAdditionalFootballContexts() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "That was excellent from Rhys James never less than solid and sturdy comma bro Bellingham at the double today period England inching towards the semi-finals comma bro far from there",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            "That was excellent from Rhys James never less than solid and sturdy, but Bellingham at the double today. England inching towards the semi-finals, but far from there."
        )
    }

    func testRepairsButMisheardAsBroBeforeNoLongerBaseVerb() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "It is one where you contribute to judgement tastes and decisions bro no longer carry coordination overhead",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            "It is one where you contribute to judgement tastes and decisions but no longer carry coordination overhead."
        )
    }

    func testPreservesGrammaticalOneWhileNormalizingActualQuantities() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Notes", profile: .notes)

        let result = try await pipeline.processStableSegment(
            StableSegment(
                text: "One is the primary option. This one was tested first. It is one where the user stays in control. One of the other options took three years. There are two names to review at three pm.",
                isFinal: true
            ),
            context: context
        )

        XCTAssertEqual(
            result.text,
            "One is the primary option. This one was tested first. It is one where the user stays in control. One of the other options took 3 years. There are 2 names to review at 3 PM."
        )
    }

    func testPreservesGenuineBroBeforeNoLongerThirdPersonVerb() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Messages", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "my bro no longer needs help and bro no longer works there", isFinal: true),
            context: context
        )

        XCTAssertEqual(result.text, "My bro no longer needs help and bro no longer works there.")
    }

    func testRepairsLatestVersionMisheardAsBajunAtSentenceStart() async throws {
        let context = AppContext(appName: "Notes", profile: .notes)

        for raw in [
            "It says Bajun is pretty good",
            "It has Bajun is pretty good",
            "The update landed period it says Bajun is pretty good"
        ] {
            let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
            let result = try await pipeline.processStableSegment(
                StableSegment(text: raw, isFinal: true),
                context: context
            )
            let expected = raw.hasPrefix("The update")
                ? "The update landed. Latest version is pretty good."
                : "Latest version is pretty good."
            XCTAssertEqual(result.text, expected, raw)
        }
    }

    func testPreservesGenuineBajunReferences() async throws {
        let context = AppContext(appName: "Messages", profile: .messaging)

        for raw in [
            "Bajun is pretty good",
            "It says Bajun plays pretty well",
            "I think it says Bajun is pretty good"
        ] {
            let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
            let result = try await pipeline.processStableSegment(
                StableSegment(text: raw, isFinal: true),
                context: context
            )
            XCTAssertTrue(result.text.localizedCaseInsensitiveContains("Bajun"), raw)
        }
    }

    func testPreservesBroBeforeNamesOutsideAtTheConstruction() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Messages", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "bro James can you check this", isFinal: true),
            context: context
        )

        XCTAssertEqual(result.text, "Bro James can you check this.")
    }

    func testNormalizesAttachedMeridiemReturnedByASR() async throws {
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        let context = AppContext(appName: "Messages", profile: .messaging)

        let result = try await pipeline.processStableSegment(
            StableSegment(text: "meet Amy at 3pm and call Amanda at 9am", isFinal: true),
            context: context
        )

        XCTAssertEqual(result.text, "Meet Amy at 3 PM and call Amanda at 9 AM.")
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
