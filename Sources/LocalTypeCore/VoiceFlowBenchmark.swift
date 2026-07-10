import Foundation

public struct VoiceFlowBenchmarkManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var cases: [VoiceFlowBenchmarkCase]

    public init(schemaVersion: Int = 1, cases: [VoiceFlowBenchmarkCase]) {
        self.schemaVersion = schemaVersion
        self.cases = cases
    }

    public func validate() throws {
        guard schemaVersion == 1 else {
            throw VoiceFlowBenchmarkManifestError.unsupportedSchemaVersion(schemaVersion)
        }
        guard !cases.isEmpty else {
            throw VoiceFlowBenchmarkManifestError.emptySuite
        }

        var identifiers = Set<String>()
        for benchmarkCase in cases {
            let identifier = benchmarkCase.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty else {
                throw VoiceFlowBenchmarkManifestError.emptyCaseID
            }
            guard identifiers.insert(identifier).inserted else {
                throw VoiceFlowBenchmarkManifestError.duplicateCaseID(identifier)
            }
            guard !benchmarkCase.audioPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VoiceFlowBenchmarkManifestError.emptyAudioPath(identifier)
            }
            guard !benchmarkCase.expectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VoiceFlowBenchmarkManifestError.emptyExpectedText(identifier)
            }
            guard benchmarkCase.durationSeconds.isFinite, benchmarkCase.durationSeconds > 0 else {
                throw VoiceFlowBenchmarkManifestError.invalidDuration(identifier)
            }
        }
    }
}

public struct VoiceFlowBenchmarkCase: Codable, Equatable, Sendable {
    public var id: String
    public var audioPath: String
    public var expectedText: String
    public var durationSeconds: Double
    public var requiredTerms: [String]
    public var promptKeywords: [String]

    public init(
        id: String,
        audioPath: String,
        expectedText: String,
        durationSeconds: Double,
        requiredTerms: [String] = [],
        promptKeywords: [String] = []
    ) {
        self.id = id
        self.audioPath = audioPath
        self.expectedText = expectedText
        self.durationSeconds = durationSeconds
        self.requiredTerms = requiredTerms
        self.promptKeywords = promptKeywords
    }

    public var transcriptionOptions: AudioTranscriptionOptions {
        let keywords = promptKeywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !keywords.isEmpty else {
            return .none
        }
        return AudioTranscriptionOptions(initialPrompt: "Keywords: \(keywords.joined(separator: ", ")).")
    }
}

public enum VoiceFlowBenchmarkManifestError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case emptySuite
    case emptyCaseID
    case duplicateCaseID(String)
    case emptyAudioPath(String)
    case emptyExpectedText(String)
    case invalidDuration(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported benchmark schema version: \(version)."
        case .emptySuite:
            return "The benchmark manifest has no cases."
        case .emptyCaseID:
            return "Every benchmark case needs a non-empty id."
        case .duplicateCaseID(let id):
            return "Benchmark case id is duplicated: \(id)."
        case .emptyAudioPath(let id):
            return "Benchmark case \(id) has no audioPath."
        case .emptyExpectedText(let id):
            return "Benchmark case \(id) has no expectedText."
        case .invalidDuration(let id):
            return "Benchmark case \(id) needs a positive, finite durationSeconds value."
        }
    }
}

/// One content-free benchmark observation. Transcript and audio data never
/// become part of a report.
public struct VoiceFlowBenchmarkSample: Codable, Equatable, Sendable {
    public var iteration: Int
    public var latencyMS: Int
    public var realTimeFactor: Double
    public var wordErrorRate: Double
    public var requiredTermAccuracy: Double

    public init(
        iteration: Int,
        latencyMS: Int,
        realTimeFactor: Double,
        wordErrorRate: Double,
        requiredTermAccuracy: Double
    ) {
        self.iteration = iteration
        self.latencyMS = latencyMS
        self.realTimeFactor = realTimeFactor
        self.wordErrorRate = wordErrorRate
        self.requiredTermAccuracy = requiredTermAccuracy
    }
}

public struct VoiceFlowBenchmarkCaseResult: Codable, Equatable, Sendable {
    public var id: String
    public var audioDurationMS: Int
    public var requestedIterations: Int
    public var failureCount: Int
    public var referenceWordCount: Int
    public var requiredTermCount: Int
    public var firstRunLatencyMS: Int?
    public var steadyStateMedianLatencyMS: Int?
    public var medianLatencyMS: Int?
    public var p95LatencyMS: Int?
    public var meanRealTimeFactor: Double?
    public var meanWordErrorRate: Double?
    public var meanRequiredTermAccuracy: Double?
    public var samples: [VoiceFlowBenchmarkSample]

    public init(
        id: String,
        audioDurationMS: Int,
        requestedIterations: Int,
        failureCount: Int,
        referenceWordCount: Int,
        requiredTermCount: Int,
        samples: [VoiceFlowBenchmarkSample]
    ) {
        self.id = id
        self.audioDurationMS = audioDurationMS
        self.requestedIterations = requestedIterations
        self.failureCount = failureCount
        self.referenceWordCount = referenceWordCount
        self.requiredTermCount = requiredTermCount
        self.samples = samples
        firstRunLatencyMS = samples.first(where: { $0.iteration == 1 })?.latencyMS
        steadyStateMedianLatencyMS = Self.percentile(
            samples.filter { $0.iteration > 1 }.map(\.latencyMS),
            percentile: 0.5
        )
        medianLatencyMS = Self.percentile(samples.map(\.latencyMS), percentile: 0.5)
        p95LatencyMS = Self.percentile(samples.map(\.latencyMS), percentile: 0.95)
        meanRealTimeFactor = Self.mean(samples.map(\.realTimeFactor))
        meanWordErrorRate = Self.mean(samples.map(\.wordErrorRate))
        meanRequiredTermAccuracy = Self.mean(samples.map(\.requiredTermAccuracy))
    }

    private static func percentile(_ values: [Int], percentile: Double) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = max(0, Int(ceil(percentile * Double(sorted.count))) - 1)
        return sorted[min(rank, sorted.count - 1)]
    }

    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

public struct VoiceFlowBenchmarkReport: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var createdAt: Date
    public var localOnly: Bool
    public var engine: String
    public var caseResults: [VoiceFlowBenchmarkCaseResult]

    public init(
        schemaVersion: Int = 1,
        createdAt: Date = Date(),
        caseResults: [VoiceFlowBenchmarkCaseResult]
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        localOnly = true
        engine = "native-whisperkit-loopback"
        self.caseResults = caseResults
    }
}
