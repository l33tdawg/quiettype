import Foundation
import XCTest
@testable import LocalTypeCore

final class VoiceFlowBenchmarkTests: XCTestCase {
    func testManifestValidatesAndBuildsShortKeywordPrompt() throws {
        let benchmarkCase = VoiceFlowBenchmarkCase(
            id: "technical-terms",
            audioPath: "private/technical-terms.wav",
            expectedText: "SAGE uses CometBFT",
            durationSeconds: 2.4,
            requiredTerms: ["SAGE", "CometBFT"],
            promptKeywords: [" SAGE ", "CometBFT"]
        )
        let manifest = VoiceFlowBenchmarkManifest(cases: [benchmarkCase])

        XCTAssertNoThrow(try manifest.validate())
        XCTAssertEqual(
            benchmarkCase.transcriptionOptions.initialPrompt,
            "Keywords: SAGE, CometBFT."
        )
    }

    func testManifestRejectsDuplicateIDsAndInvalidDuration() {
        let valid = VoiceFlowBenchmarkCase(
            id: "same",
            audioPath: "one.wav",
            expectedText: "hello",
            durationSeconds: 1
        )
        var duplicate = valid
        duplicate.audioPath = "two.wav"
        XCTAssertThrowsError(
            try VoiceFlowBenchmarkManifest(cases: [valid, duplicate]).validate()
        ) { error in
            XCTAssertEqual(error as? VoiceFlowBenchmarkManifestError, .duplicateCaseID("same"))
        }

        var invalidDuration = valid
        invalidDuration.durationSeconds = 0
        XCTAssertThrowsError(
            try VoiceFlowBenchmarkManifest(cases: [invalidDuration]).validate()
        ) { error in
            XCTAssertEqual(error as? VoiceFlowBenchmarkManifestError, .invalidDuration("same"))
        }
    }

    func testReportStatisticsPreserveFirstRunAndExcludeContent() throws {
        let samples = [
            VoiceFlowBenchmarkSample(
                iteration: 1,
                latencyMS: 1_800,
                realTimeFactor: 0.9,
                wordErrorRate: 0.2,
                requiredTermAccuracy: 0.5
            ),
            VoiceFlowBenchmarkSample(
                iteration: 2,
                latencyMS: 400,
                realTimeFactor: 0.2,
                wordErrorRate: 0,
                requiredTermAccuracy: 1
            ),
            VoiceFlowBenchmarkSample(
                iteration: 3,
                latencyMS: 600,
                realTimeFactor: 0.3,
                wordErrorRate: 0.1,
                requiredTermAccuracy: 1
            )
        ]
        let result = VoiceFlowBenchmarkCaseResult(
            id: "case-01",
            audioDurationMS: 2_000,
            requestedIterations: 3,
            failureCount: 0,
            referenceWordCount: 5,
            requiredTermCount: 2,
            samples: samples
        )

        XCTAssertEqual(result.firstRunLatencyMS, 1_800)
        XCTAssertEqual(result.steadyStateMedianLatencyMS, 400)
        XCTAssertEqual(result.medianLatencyMS, 600)
        XCTAssertEqual(result.p95LatencyMS, 1_800)
        XCTAssertEqual(try XCTUnwrap(result.meanWordErrorRate), 0.1, accuracy: 0.0001)

        let report = VoiceFlowBenchmarkReport(
            createdAt: Date(timeIntervalSince1970: 1_000),
            caseResults: [result]
        )
        let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        XCTAssertTrue(json.contains("\"localOnly\":true"))
        XCTAssertFalse(json.contains("expectedText"))
        XCTAssertFalse(json.contains("audioPath"))
        XCTAssertFalse(json.contains("hypothesis"))
        XCTAssertFalse(json.contains("transcript"))
    }
}
