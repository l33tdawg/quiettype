import Darwin
import AVFoundation
import Foundation
import LocalTypeCore

@main
struct LocalTypeVoiceBenchmarkCLI {
    fileprivate static let usage = """
    Usage:
      localtype-voice-benchmark <manifest.json> [--iterations N] [--output report.json]
      localtype-voice-benchmark compare <baseline.json> <candidate.json> [--output comparison.json]
      localtype-voice-benchmark live <audio.wav> [--endpoint ws://127.0.0.1:50060/v1/audio/live] [--manifest manifest.json] [--case id]

    Runs every WAV case against QuietType's loopback-only native speech engine.
    Compare applies the local accuracy and latency gates to two content-free reports.
    All reports omit transcript text and audio paths.
    """

    static func main() async {
        do {
            let rawArguments = Array(CommandLine.arguments.dropFirst())
            if rawArguments.first == "compare" {
                let arguments = try ComparisonArguments.parse(Array(rawArguments.dropFirst()))
                try compareReports(arguments)
                return
            }
            if rawArguments.first == "live" {
                try await runLiveReplay(Array(rawArguments.dropFirst()))
                return
            }

            let arguments = try Arguments.parse(rawArguments)
            if arguments.showHelp {
                print(usage)
                return
            }
            guard let manifestPath = arguments.manifestPath else {
                throw CLIError.missingManifest
            }

            let manifestURL = absoluteFileURL(for: manifestPath)
            let manifest = try loadManifest(at: manifestURL)
            let results = try await run(
                manifest: manifest,
                relativeTo: manifestURL.deletingLastPathComponent(),
                iterations: arguments.iterations
            )
            let report = VoiceFlowBenchmarkReport(caseResults: results)
            let data = try encode(report)

            if let outputPath = arguments.outputPath {
                let outputURL = absoluteFileURL(for: outputPath)
                try writeOwnerOnly(data, to: outputURL)
                writeStatus("Saved content-free report to \(outputURL.path)")
            } else {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }

            let failures = results.reduce(0) { $0 + $1.failureCount }
            if failures > 0 {
                throw CLIError.iterationsFailed(failures)
            }
        } catch {
            writeError(String(reflecting: error))
            Darwin.exit(2)
        }
    }

    private static func runLiveReplay(_ arguments: [String]) async throws {
        guard let audioPath = arguments.first else {
            throw CLIError.missingManifest
        }
        var endpoint = URL(string: "ws://127.0.0.1:50060/v1/audio/live")!
        if let endpointIndex = arguments.firstIndex(of: "--endpoint"),
           arguments.indices.contains(endpointIndex + 1),
           let value = URL(string: arguments[endpointIndex + 1]) {
            endpoint = value
        }

        let audio = try readMonoAudio(at: absoluteFileURL(for: audioPath))
        let client = WhisperKitLiveStreamClient(endpoint: endpoint)
        let frameSampleCount = max(1, audio.sampleRate / 4)
        let started = DispatchTime.now().uptimeNanoseconds
        var offset = 0
        while offset < audio.samples.count {
            let end = min(audio.samples.count, offset + frameSampleCount)
            try await client.append(
                AudioFrame(
                    samples: Array(audio.samples[offset..<end]),
                    sampleRate: audio.sampleRate,
                    timestamp: Double(offset) / Double(audio.sampleRate)
                )
            )
            let duration = Double(end - offset) / Double(audio.sampleRate)
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            offset = end
        }

        let released = DispatchTime.now().uptimeNanoseconds
        guard let result = await client.finish(timeoutSeconds: 90) else {
            let detail = await client.lastError() ?? "Live transcription returned no final result."
            throw CLIError.liveReplayFailed(detail)
        }
        let completed = DispatchTime.now().uptimeNanoseconds
        let releaseLatencyMS = Int(Double(completed - released) / 1_000_000)
        let totalMS = Int(Double(completed - started) / 1_000_000)
        writeStatus("Live release-to-final: \(releaseLatencyMS) ms; total: \(totalMS) ms; coverage: \(String(format: "%.3f", result.coveredDurationSeconds))s")
        if let manifestIndex = arguments.firstIndex(of: "--manifest"),
           arguments.indices.contains(manifestIndex + 1) {
            let manifestURL = absoluteFileURL(for: arguments[manifestIndex + 1])
            let manifest = try loadManifest(at: manifestURL)
            let requestedCaseID = optionValue("--case", in: arguments)
            let audioURL = absoluteFileURL(for: audioPath).standardizedFileURL
            let benchmarkCase = manifest.cases.first { candidate in
                if let requestedCaseID {
                    return candidate.id == requestedCaseID
                }
                return resolvedAudioURL(
                    candidate.audioPath,
                    relativeTo: manifestURL.deletingLastPathComponent()
                ) == audioURL
            }
            if let benchmarkCase {
                let score = VoiceFlowTextScorer.score(
                    reference: benchmarkCase.expectedText,
                    hypothesis: result.text,
                    requiredTerms: benchmarkCase.requiredTerms
                )
                writeStatus(
                    "Live accuracy: WER \(String(format: "%.2f", score.wordErrorRate * 100))%; required terms \(String(format: "%.2f", score.requiredTermAccuracy * 100))%"
                )
            } else {
                throw CLIError.liveReplayFailed("No matching benchmark case was found for the live replay.")
            }
        }
        print(result.text)
    }

    private static func optionValue(_ option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func readMonoAudio(at url: URL) throws -> (samples: [Float], sampleRate: Int) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw CLIError.liveReplayFailed("Could not allocate an audio replay buffer.")
        }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData,
              buffer.frameLength > 0 else {
            throw CLIError.liveReplayFailed("The replay file is not readable as floating-point PCM.")
        }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        var samples = [Float](repeating: 0, count: frameCount)
        for channel in 0..<channelCount {
            for index in 0..<frameCount {
                samples[index] += channels[channel][index] / Float(channelCount)
            }
        }
        return (samples, Int(format.sampleRate.rounded()))
    }

    private static func loadManifest(at url: URL) throws -> VoiceFlowBenchmarkManifest {
        let manifest = try JSONDecoder().decode(
            VoiceFlowBenchmarkManifest.self,
            from: Data(contentsOf: url)
        )
        try manifest.validate()
        return manifest
    }

    private static func run(
        manifest: VoiceFlowBenchmarkManifest,
        relativeTo manifestDirectory: URL,
        iterations: Int
    ) async throws -> [VoiceFlowBenchmarkCaseResult] {
        var results: [VoiceFlowBenchmarkCaseResult] = []

        for benchmarkCase in manifest.cases {
            let audioURL = resolvedAudioURL(
                benchmarkCase.audioPath,
                relativeTo: manifestDirectory
            )
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: audioURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                throw CLIError.missingAudio(benchmarkCase.id)
            }

            writeStatus("Running \(benchmarkCase.id) locally (\(iterations)x)")
            let transcriber = WhisperKitServerTranscriber(
                timeoutSeconds: WhisperKitServerTranscriber.timeoutForFullAudio(
                    durationSeconds: benchmarkCase.durationSeconds
                )
            )
            let referenceScore = VoiceFlowTextScorer.score(
                reference: benchmarkCase.expectedText,
                hypothesis: "",
                requiredTerms: benchmarkCase.requiredTerms
            )
            var samples: [VoiceFlowBenchmarkSample] = []
            var failureCount = 0

            for iteration in 1...iterations {
                let started = DispatchTime.now().uptimeNanoseconds
                do {
                    let hypothesis = try await transcriber.transcribe(
                        audioFile: audioURL,
                        options: benchmarkCase.transcriptionOptions
                    )
                    let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - started
                    let latencyMS = max(0, Int((Double(elapsedNanoseconds) / 1_000_000).rounded()))
                    let score = VoiceFlowTextScorer.score(
                        reference: benchmarkCase.expectedText,
                        hypothesis: hypothesis,
                        requiredTerms: benchmarkCase.requiredTerms
                    )
                    samples.append(
                        VoiceFlowBenchmarkSample(
                            iteration: iteration,
                            latencyMS: latencyMS,
                            realTimeFactor: (Double(latencyMS) / 1_000) / benchmarkCase.durationSeconds,
                            wordErrorRate: score.wordErrorRate,
                            requiredTermAccuracy: score.requiredTermAccuracy
                        )
                    )
                    writeStatus("  iteration \(iteration): \(latencyMS) ms")
                } catch {
                    failureCount += 1
                    writeError("  \(benchmarkCase.id) iteration \(iteration) failed locally: \(error.localizedDescription)")
                }
            }

            results.append(
                VoiceFlowBenchmarkCaseResult(
                    id: benchmarkCase.id,
                    audioDurationMS: Int((benchmarkCase.durationSeconds * 1_000).rounded()),
                    requestedIterations: iterations,
                    failureCount: failureCount,
                    referenceWordCount: referenceScore.referenceWordCount,
                    requiredTermCount: referenceScore.requiredTermCount,
                    samples: samples
                )
            )
        }

        return results
    }

    private static func compareReports(_ arguments: ComparisonArguments) throws {
        if arguments.showHelp {
            print(usage)
            return
        }
        guard let baselinePath = arguments.baselinePath,
              let candidatePath = arguments.candidatePath else {
            throw CLIError.missingComparisonReports
        }

        let baseline = try loadBenchmarkReport(at: absoluteFileURL(for: baselinePath))
        let candidate = try loadBenchmarkReport(at: absoluteFileURL(for: candidatePath))
        let comparison = try VoiceFlowBenchmarkComparator.compare(
            baseline: baseline,
            candidate: candidate
        )
        let data = try encode(comparison)
        if let outputPath = arguments.outputPath {
            let outputURL = absoluteFileURL(for: outputPath)
            try writeOwnerOnly(data, to: outputURL)
            writeStatus("Saved content-free comparison to \(outputURL.path)")
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }

        let summary = comparison.summary
        writeStatus(
            "Compared \(summary.comparedCaseCount) cases: "
                + "\(summary.improvedCaseCount) improved, "
                + "\(summary.passedCaseCount) passed, "
                + "\(summary.regressedCaseCount) regressed, "
                + "\(summary.insufficientDataCaseCount) insufficient"
        )
        guard summary.passed else {
            throw CLIError.comparisonFailed(
                regressions: summary.regressedCaseCount,
                insufficient: summary.insufficientDataCaseCount,
                missing: summary.missingFromBaseline.count + summary.missingFromCandidate.count
            )
        }
    }

    private static func loadBenchmarkReport(at url: URL) throws -> VoiceFlowBenchmarkReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(VoiceFlowBenchmarkReport.self, from: Data(contentsOf: url))
    }

    private static func encode<T: Encodable>(_ report: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(report)
    }

    private static func writeOwnerOnly(_ data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            try OwnerOnlyFileSecurity.prepareDirectory(directory, fileManager: fileManager)
        } else if !isDirectory.boolValue {
            throw CLIError.invalidOutputDirectory
        }
        try data.write(to: url, options: .atomic)
        try OwnerOnlyFileSecurity.protectFile(url, fileManager: fileManager)
    }

    private static func resolvedAudioURL(_ path: String, relativeTo directory: URL) -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        if NSString(string: expanded).isAbsolutePath {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return directory.appendingPathComponent(expanded).standardizedFileURL
    }

    private static func absoluteFileURL(for path: String) -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        if NSString(string: expanded).isAbsolutePath {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(expanded)
            .standardizedFileURL
    }

    private static func writeStatus(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    }
}

private struct ComparisonArguments {
    var baselinePath: String?
    var candidatePath: String?
    var outputPath: String?
    var showHelp = false

    static func parse(_ rawArguments: [String]) throws -> ComparisonArguments {
        var parsed = ComparisonArguments()
        var positional: [String] = []
        var index = 0

        while index < rawArguments.count {
            let argument = rawArguments[index]
            switch argument {
            case "-h", "--help":
                parsed.showHelp = true
                index += 1
            case "--output":
                guard index + 1 < rawArguments.count,
                      !rawArguments[index + 1].isEmpty else {
                    throw CLIError.missingOutputPath
                }
                parsed.outputPath = rawArguments[index + 1]
                index += 2
            default:
                if argument.hasPrefix("-") {
                    throw CLIError.unknownArgument(argument)
                }
                positional.append(argument)
                index += 1
            }
        }

        guard positional.count <= 2 else {
            throw CLIError.unexpectedArgument(positional[2])
        }
        parsed.baselinePath = positional.first
        parsed.candidatePath = positional.count > 1 ? positional[1] : nil
        return parsed
    }
}

private struct Arguments {
    var manifestPath: String?
    var iterations = 1
    var outputPath: String?
    var showHelp = false

    static func parse(_ rawArguments: [String]) throws -> Arguments {
        var parsed = Arguments()
        var index = 0

        while index < rawArguments.count {
            let argument = rawArguments[index]
            switch argument {
            case "-h", "--help":
                parsed.showHelp = true
                index += 1
            case "--iterations":
                guard index + 1 < rawArguments.count,
                      let value = Int(rawArguments[index + 1]),
                      value > 0 else {
                    throw CLIError.invalidIterations
                }
                parsed.iterations = value
                index += 2
            case "--output":
                guard index + 1 < rawArguments.count,
                      !rawArguments[index + 1].isEmpty else {
                    throw CLIError.missingOutputPath
                }
                parsed.outputPath = rawArguments[index + 1]
                index += 2
            default:
                if argument.hasPrefix("-") {
                    throw CLIError.unknownArgument(argument)
                }
                guard parsed.manifestPath == nil else {
                    throw CLIError.unexpectedArgument(argument)
                }
                parsed.manifestPath = argument
                index += 1
            }
        }

        return parsed
    }
}

private enum CLIError: Error, LocalizedError {
    case missingManifest
    case invalidIterations
    case missingOutputPath
    case unknownArgument(String)
    case unexpectedArgument(String)
    case missingAudio(String)
    case invalidOutputDirectory
    case iterationsFailed(Int)
    case missingComparisonReports
    case comparisonFailed(regressions: Int, insufficient: Int, missing: Int)
    case liveReplayFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            return "Missing benchmark manifest.\n\(LocalTypeVoiceBenchmarkCLI.usage)"
        case .invalidIterations:
            return "--iterations must be a positive integer."
        case .missingOutputPath:
            return "--output needs a file path."
        case .unknownArgument(let argument):
            return "Unknown option: \(argument)."
        case .unexpectedArgument(let argument):
            return "Unexpected argument: \(argument)."
        case .missingAudio(let id):
            return "Benchmark audio is missing for case \(id)."
        case .invalidOutputDirectory:
            return "The report output parent is not a directory."
        case .iterationsFailed(let count):
            return "\(count) local benchmark iteration(s) failed."
        case .missingComparisonReports:
            return "Compare needs baseline and candidate report paths.\n\(LocalTypeVoiceBenchmarkCLI.usage)"
        case .comparisonFailed(let regressions, let insufficient, let missing):
            return "Comparison gate failed: \(regressions) regression(s), \(insufficient) insufficient case(s), and \(missing) missing case(s)."
        case .liveReplayFailed(let detail):
            return detail
        }
    }
}
