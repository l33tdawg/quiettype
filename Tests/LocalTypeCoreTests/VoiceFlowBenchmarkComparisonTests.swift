import Foundation
import XCTest
@testable import LocalTypeCore

final class VoiceFlowBenchmarkComparisonTests: XCTestCase {
    func testImprovedCandidatePassesContentFreeGate() throws {
        let baseline = report(
            createdAt: Date(timeIntervalSince1970: 1_000),
            result: result(
                id: "clean-01",
                latencies: [1_000, 1_200],
                wordErrorRate: 0.10,
                termAccuracy: 0.90
            )
        )
        let candidate = report(
            createdAt: Date(timeIntervalSince1970: 2_000),
            result: result(
                id: "clean-01",
                latencies: [800, 900],
                wordErrorRate: 0.08,
                termAccuracy: 0.95
            )
        )

        let comparison = try VoiceFlowBenchmarkComparator.compare(
            baseline: baseline,
            candidate: candidate,
            createdAt: Date(timeIntervalSince1970: 3_000)
        )

        XCTAssertTrue(comparison.summary.passed)
        XCTAssertEqual(comparison.summary.improvedCaseCount, 1)
        XCTAssertEqual(comparison.caseComparisons.first?.status, .improved)
        XCTAssertEqual(
            try XCTUnwrap(comparison.caseComparisons.first?.medianLatencyChange),
            -0.2,
            accuracy: 0.0001
        )

        let json = String(decoding: try JSONEncoder().encode(comparison), as: UTF8.self)
        XCTAssertTrue(json.contains("\"localOnly\":true"))
        XCTAssertFalse(json.contains("expectedText"))
        XCTAssertFalse(json.contains("audioPath"))
        XCTAssertFalse(json.contains("hypothesis"))
        XCTAssertFalse(json.contains("transcript"))
    }

    func testAccuracyAndLatencyRegressionFailsGate() throws {
        let baseline = report(
            result: result(
                id: "technical-01",
                latencies: [1_000, 1_200],
                wordErrorRate: 0.05,
                termAccuracy: 1
            )
        )
        let candidate = report(
            result: result(
                id: "technical-01",
                latencies: [1_200, 1_400],
                wordErrorRate: 0.08,
                termAccuracy: 0.8,
                failureCount: 1
            )
        )

        let comparison = try VoiceFlowBenchmarkComparator.compare(
            baseline: baseline,
            candidate: candidate
        )
        let compared = try XCTUnwrap(comparison.caseComparisons.first)

        XCTAssertFalse(comparison.summary.passed)
        XCTAssertEqual(compared.status, .regressed)
        XCTAssertEqual(Set(compared.regressionReasons), Set([
            .failures,
            .wordErrorRate,
            .requiredTermAccuracy,
            .firstRunLatency,
            .medianLatency,
            .p95Latency
        ]))
    }

    func testMismatchedCorpusShapeFailsGate() throws {
        let baselineResult = result(
            id: "same-id",
            latencies: [500],
            wordErrorRate: 0,
            termAccuracy: 1
        )
        var candidateResult = baselineResult
        candidateResult.requestedIterations = 2
        candidateResult.audioDurationMS += 100
        candidateResult.referenceWordCount += 1

        let comparison = try VoiceFlowBenchmarkComparator.compare(
            baseline: report(result: baselineResult),
            candidate: report(result: candidateResult)
        )
        let compared = try XCTUnwrap(comparison.caseComparisons.first)

        XCTAssertFalse(comparison.summary.passed)
        XCTAssertEqual(compared.status, .regressed)
        XCTAssertEqual(Set(compared.regressionReasons), Set([
            .requestedIterations,
            .audioDuration,
            .referenceShape
        ]))
    }

    func testMissingAndEmptyCasesFailClosed() throws {
        let baseline = VoiceFlowBenchmarkReport(caseResults: [
            result(id: "empty", latencies: [], wordErrorRate: 0, termAccuracy: 1),
            result(id: "missing", latencies: [500], wordErrorRate: 0, termAccuracy: 1)
        ])
        let candidate = VoiceFlowBenchmarkReport(caseResults: [
            result(id: "empty", latencies: [], wordErrorRate: 0, termAccuracy: 1),
            result(id: "extra", latencies: [500], wordErrorRate: 0, termAccuracy: 1)
        ])

        let comparison = try VoiceFlowBenchmarkComparator.compare(
            baseline: baseline,
            candidate: candidate
        )

        XCTAssertFalse(comparison.summary.passed)
        XCTAssertEqual(comparison.summary.insufficientDataCaseCount, 1)
        XCTAssertEqual(comparison.summary.missingFromBaseline, ["extra"])
        XCTAssertEqual(comparison.summary.missingFromCandidate, ["missing"])
    }

    func testRejectsReportNotMarkedLocalOnly() {
        var baseline = report(result: result(
            id: "case",
            latencies: [500],
            wordErrorRate: 0,
            termAccuracy: 1
        ))
        baseline.localOnly = false

        XCTAssertThrowsError(
            try VoiceFlowBenchmarkComparator.compare(
                baseline: baseline,
                candidate: report(result: result(
                    id: "case",
                    latencies: [500],
                    wordErrorRate: 0,
                    termAccuracy: 1
                ))
            )
        ) { error in
            XCTAssertEqual(error as? VoiceFlowBenchmarkComparisonError, .nonLocalReport)
        }
    }

    func testRejectsUnknownReportSchema() {
        var baseline = report(result: result(
            id: "case",
            latencies: [500],
            wordErrorRate: 0,
            termAccuracy: 1
        ))
        baseline.schemaVersion = 2

        XCTAssertThrowsError(
            try VoiceFlowBenchmarkComparator.compare(
                baseline: baseline,
                candidate: report(result: result(
                    id: "case",
                    latencies: [500],
                    wordErrorRate: 0,
                    termAccuracy: 1
                ))
            )
        ) { error in
            XCTAssertEqual(
                error as? VoiceFlowBenchmarkComparisonError,
                .unsupportedReportSchema(2)
            )
        }
    }

    private func report(
        createdAt: Date = Date(timeIntervalSince1970: 1_000),
        result: VoiceFlowBenchmarkCaseResult
    ) -> VoiceFlowBenchmarkReport {
        VoiceFlowBenchmarkReport(createdAt: createdAt, caseResults: [result])
    }

    private func result(
        id: String,
        latencies: [Int],
        wordErrorRate: Double,
        termAccuracy: Double,
        failureCount: Int = 0
    ) -> VoiceFlowBenchmarkCaseResult {
        let samples = latencies.enumerated().map { index, latency in
            VoiceFlowBenchmarkSample(
                iteration: index + 1,
                latencyMS: latency,
                realTimeFactor: Double(latency) / 2_000,
                wordErrorRate: wordErrorRate,
                requiredTermAccuracy: termAccuracy
            )
        }
        return VoiceFlowBenchmarkCaseResult(
            id: id,
            audioDurationMS: 2_000,
            requestedIterations: max(1, latencies.count),
            failureCount: failureCount,
            referenceWordCount: 10,
            requiredTermCount: 2,
            samples: samples
        )
    }
}
