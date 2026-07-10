import Foundation

public struct VoiceFlowBenchmarkComparisonThresholds: Codable, Equatable, Sendable {
    public var wordErrorRateTolerance: Double
    public var requiredTermAccuracyTolerance: Double
    public var latencyRegressionTolerance: Double
    public var meaningfulLatencyImprovement: Double

    public init(
        wordErrorRateTolerance: Double = 0.005,
        requiredTermAccuracyTolerance: Double = 0.001,
        latencyRegressionTolerance: Double = 0.05,
        meaningfulLatencyImprovement: Double = 0.15
    ) {
        self.wordErrorRateTolerance = max(0, wordErrorRateTolerance)
        self.requiredTermAccuracyTolerance = max(0, requiredTermAccuracyTolerance)
        self.latencyRegressionTolerance = max(0, latencyRegressionTolerance)
        self.meaningfulLatencyImprovement = max(0, meaningfulLatencyImprovement)
    }

    public static let quietTypeDefault = VoiceFlowBenchmarkComparisonThresholds()
}

public enum VoiceFlowBenchmarkComparisonStatus: String, Codable, Equatable, Sendable {
    case improved
    case passed
    case regressed
    case insufficientData
}

public enum VoiceFlowBenchmarkRegressionReason: String, Codable, Equatable, Sendable {
    case requestedIterations
    case audioDuration
    case referenceShape
    case failures
    case wordErrorRate
    case requiredTermAccuracy
    case firstRunLatency
    case medianLatency
    case p95Latency
}

public struct VoiceFlowBenchmarkCaseComparison: Codable, Equatable, Sendable {
    public var id: String
    public var status: VoiceFlowBenchmarkComparisonStatus
    public var regressionReasons: [VoiceFlowBenchmarkRegressionReason]
    public var failureCountDelta: Int
    public var wordErrorRateDelta: Double?
    public var requiredTermAccuracyDelta: Double?
    public var firstRunLatencyChange: Double?
    public var medianLatencyChange: Double?
    public var p95LatencyChange: Double?
    public var realTimeFactorDelta: Double?
}

public struct VoiceFlowBenchmarkComparisonSummary: Codable, Equatable, Sendable {
    public var passed: Bool
    public var comparedCaseCount: Int
    public var improvedCaseCount: Int
    public var passedCaseCount: Int
    public var regressedCaseCount: Int
    public var insufficientDataCaseCount: Int
    public var missingFromBaseline: [String]
    public var missingFromCandidate: [String]
}

/// Content-free comparison output. It contains neutral case identifiers and
/// numeric deltas only, never audio paths, references, or hypotheses.
public struct VoiceFlowBenchmarkComparisonReport: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var createdAt: Date
    public var localOnly: Bool
    public var baselineCreatedAt: Date
    public var candidateCreatedAt: Date
    public var thresholds: VoiceFlowBenchmarkComparisonThresholds
    public var summary: VoiceFlowBenchmarkComparisonSummary
    public var caseComparisons: [VoiceFlowBenchmarkCaseComparison]
}

public enum VoiceFlowBenchmarkComparisonError: Error, Equatable, LocalizedError {
    case unsupportedReportSchema(Int)
    case nonLocalReport
    case duplicateCaseID(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedReportSchema(let version):
            return "Unsupported benchmark report schema version: \(version)."
        case .nonLocalReport:
            return "Benchmark comparison accepts local-only reports."
        case .duplicateCaseID(let id):
            return "Benchmark report contains a duplicate case id: \(id)."
        }
    }
}

public enum VoiceFlowBenchmarkComparator {
    public static func compare(
        baseline: VoiceFlowBenchmarkReport,
        candidate: VoiceFlowBenchmarkReport,
        thresholds: VoiceFlowBenchmarkComparisonThresholds = .quietTypeDefault,
        createdAt: Date = Date()
    ) throws -> VoiceFlowBenchmarkComparisonReport {
        guard baseline.schemaVersion == 1 else {
            throw VoiceFlowBenchmarkComparisonError.unsupportedReportSchema(baseline.schemaVersion)
        }
        guard candidate.schemaVersion == 1 else {
            throw VoiceFlowBenchmarkComparisonError.unsupportedReportSchema(candidate.schemaVersion)
        }
        guard baseline.localOnly, candidate.localOnly else {
            throw VoiceFlowBenchmarkComparisonError.nonLocalReport
        }
        let baselineByID = try indexed(baseline.caseResults)
        let candidateByID = try indexed(candidate.caseResults)
        let baselineIDs = Set(baselineByID.keys)
        let candidateIDs = Set(candidateByID.keys)
        let commonIDs = baselineIDs.intersection(candidateIDs).sorted()
        let comparisons = commonIDs.map { id in
            compareCase(
                baseline: baselineByID[id]!,
                candidate: candidateByID[id]!,
                thresholds: thresholds
            )
        }
        let regressedCount = comparisons.filter { $0.status == .regressed }.count
        let insufficientCount = comparisons.filter { $0.status == .insufficientData }.count
        let missingFromBaseline = candidateIDs.subtracting(baselineIDs).sorted()
        let missingFromCandidate = baselineIDs.subtracting(candidateIDs).sorted()
        let passed = regressedCount == 0
            && insufficientCount == 0
            && missingFromBaseline.isEmpty
            && missingFromCandidate.isEmpty

        return VoiceFlowBenchmarkComparisonReport(
            schemaVersion: 1,
            createdAt: createdAt,
            localOnly: true,
            baselineCreatedAt: baseline.createdAt,
            candidateCreatedAt: candidate.createdAt,
            thresholds: thresholds,
            summary: VoiceFlowBenchmarkComparisonSummary(
                passed: passed,
                comparedCaseCount: comparisons.count,
                improvedCaseCount: comparisons.filter { $0.status == .improved }.count,
                passedCaseCount: comparisons.filter { $0.status == .passed }.count,
                regressedCaseCount: regressedCount,
                insufficientDataCaseCount: insufficientCount,
                missingFromBaseline: missingFromBaseline,
                missingFromCandidate: missingFromCandidate
            ),
            caseComparisons: comparisons
        )
    }

    private static func indexed(
        _ results: [VoiceFlowBenchmarkCaseResult]
    ) throws -> [String: VoiceFlowBenchmarkCaseResult] {
        var indexed: [String: VoiceFlowBenchmarkCaseResult] = [:]
        for result in results {
            guard indexed[result.id] == nil else {
                throw VoiceFlowBenchmarkComparisonError.duplicateCaseID(result.id)
            }
            indexed[result.id] = result
        }
        return indexed
    }

    private static func compareCase(
        baseline: VoiceFlowBenchmarkCaseResult,
        candidate: VoiceFlowBenchmarkCaseResult,
        thresholds: VoiceFlowBenchmarkComparisonThresholds
    ) -> VoiceFlowBenchmarkCaseComparison {
        let wordErrorRateDelta = delta(candidate.meanWordErrorRate, baseline.meanWordErrorRate)
        let requiredTermAccuracyDelta = delta(
            candidate.meanRequiredTermAccuracy,
            baseline.meanRequiredTermAccuracy
        )
        let firstRunLatencyChange = relativeChange(
            candidate.firstRunLatencyMS,
            baseline.firstRunLatencyMS
        )
        let medianLatencyChange = relativeChange(
            candidate.medianLatencyMS,
            baseline.medianLatencyMS
        )
        let p95LatencyChange = relativeChange(
            candidate.p95LatencyMS,
            baseline.p95LatencyMS
        )
        let realTimeFactorDelta = delta(
            candidate.meanRealTimeFactor,
            baseline.meanRealTimeFactor
        )
        let failureDelta = candidate.failureCount - baseline.failureCount
        var structuralReasons: [VoiceFlowBenchmarkRegressionReason] = []
        if candidate.requestedIterations != baseline.requestedIterations {
            structuralReasons.append(.requestedIterations)
        }
        if candidate.audioDurationMS != baseline.audioDurationMS {
            structuralReasons.append(.audioDuration)
        }
        if candidate.referenceWordCount != baseline.referenceWordCount
            || candidate.requiredTermCount != baseline.requiredTermCount {
            structuralReasons.append(.referenceShape)
        }

        guard !baseline.samples.isEmpty,
              !candidate.samples.isEmpty,
              wordErrorRateDelta != nil,
              requiredTermAccuracyDelta != nil,
              firstRunLatencyChange != nil,
              medianLatencyChange != nil,
              p95LatencyChange != nil else {
            return VoiceFlowBenchmarkCaseComparison(
                id: baseline.id,
                status: .insufficientData,
                regressionReasons: structuralReasons,
                failureCountDelta: failureDelta,
                wordErrorRateDelta: wordErrorRateDelta,
                requiredTermAccuracyDelta: requiredTermAccuracyDelta,
                firstRunLatencyChange: firstRunLatencyChange,
                medianLatencyChange: medianLatencyChange,
                p95LatencyChange: p95LatencyChange,
                realTimeFactorDelta: realTimeFactorDelta
            )
        }

        var reasons = structuralReasons
        if failureDelta > 0 {
            reasons.append(.failures)
        }
        if wordErrorRateDelta! > thresholds.wordErrorRateTolerance {
            reasons.append(.wordErrorRate)
        }
        if requiredTermAccuracyDelta! < -thresholds.requiredTermAccuracyTolerance {
            reasons.append(.requiredTermAccuracy)
        }
        if firstRunLatencyChange! > thresholds.latencyRegressionTolerance {
            reasons.append(.firstRunLatency)
        }
        if medianLatencyChange! > thresholds.latencyRegressionTolerance {
            reasons.append(.medianLatency)
        }
        if p95LatencyChange! > thresholds.latencyRegressionTolerance {
            reasons.append(.p95Latency)
        }

        let improved = wordErrorRateDelta! < -thresholds.wordErrorRateTolerance
            || requiredTermAccuracyDelta! > thresholds.requiredTermAccuracyTolerance
            || firstRunLatencyChange! < -thresholds.meaningfulLatencyImprovement
            || medianLatencyChange! < -thresholds.meaningfulLatencyImprovement
            || p95LatencyChange! < -thresholds.meaningfulLatencyImprovement
        let status: VoiceFlowBenchmarkComparisonStatus = !reasons.isEmpty
            ? .regressed
            : improved ? .improved : .passed

        return VoiceFlowBenchmarkCaseComparison(
            id: baseline.id,
            status: status,
            regressionReasons: reasons,
            failureCountDelta: failureDelta,
            wordErrorRateDelta: wordErrorRateDelta,
            requiredTermAccuracyDelta: requiredTermAccuracyDelta,
            firstRunLatencyChange: firstRunLatencyChange,
            medianLatencyChange: medianLatencyChange,
            p95LatencyChange: p95LatencyChange,
            realTimeFactorDelta: realTimeFactorDelta
        )
    }

    private static func delta(_ candidate: Double?, _ baseline: Double?) -> Double? {
        guard let candidate, let baseline else { return nil }
        return candidate - baseline
    }

    private static func relativeChange(_ candidate: Int?, _ baseline: Int?) -> Double? {
        guard let candidate, let baseline, baseline > 0 else { return nil }
        return Double(candidate - baseline) / Double(baseline)
    }
}
