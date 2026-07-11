import XCTest
@testable import LocalTypeCore

final class VoiceFlowCaptureSuiteTests: XCTestCase {
    func testStandardSuiteHasUniquePromptsAndRequiredCoverage() {
        let suite = VoiceFlowCaptureSuite.quietTypeStandard
        let identifiers = suite.prompts.map(\.id)
        let categories = Set(suite.prompts.map(\.category))

        XCTAssertEqual(suite.schemaVersion, 1)
        XCTAssertEqual(suite.prompts.count, 30)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertTrue(suite.prompts.allSatisfy { !$0.expectedText.isEmpty })
        XCTAssertTrue(categories.isSuperset(of: [
            "Clean speech",
            "Technical vocabulary",
            "Corrections and restarts",
            "Pause survival",
            "Delivery variation",
            "Background noise",
            "Numbers and formatting",
            "Casing regressions",
            "FN tail latency",
            "Long form"
        ]))
    }

    func testKeywordPromptCreatesPairedCasesForTheSameLocalAudio() throws {
        let prompt = try XCTUnwrap(
            VoiceFlowCaptureSuite.quietTypeStandard.prompts.first {
                !$0.keywordComparisonTerms.isEmpty
            }
        )

        let cases = prompt.benchmarkCases(
            audioPath: "audio/technical.wav",
            durationSeconds: 4.2
        )

        XCTAssertEqual(cases.count, 2)
        XCTAssertEqual(cases[0].audioPath, cases[1].audioPath)
        XCTAssertNil(cases[0].transcriptionOptions.initialPrompt)
        XCTAssertNotNil(cases[1].transcriptionOptions.initialPrompt)
        XCTAssertTrue(cases[0].id.hasSuffix("-baseline"))
        XCTAssertTrue(cases[1].id.hasSuffix("-keywords"))
    }

    func testCompleteCapturedSuiteBuildsValidManifest() throws {
        let suite = VoiceFlowCaptureSuite.quietTypeStandard
        let cases = suite.prompts.flatMap { prompt in
            prompt.benchmarkCases(
                audioPath: "audio/\(prompt.id).wav",
                durationSeconds: 3
            )
        }
        let manifest = VoiceFlowBenchmarkManifest(cases: cases)

        XCTAssertNoThrow(try manifest.validate())
        XCTAssertGreaterThan(cases.count, suite.prompts.count)
    }
}
