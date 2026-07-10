import Darwin
import Foundation
import LocalTypeCore

@main
struct LocalTypeVoiceBenchmarkCLI {
    fileprivate static let usage = """
    Usage: localtype-voice-benchmark <manifest.json> [--iterations N] [--output report.json]

    Runs every WAV case against QuietType's loopback-only native speech engine.
    Reports contain measurements only; transcript text and audio paths are omitted.
    """

    static func main() async {
        do {
            let arguments = try Arguments.parse(Array(CommandLine.arguments.dropFirst()))
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
            writeError(error.localizedDescription)
            Darwin.exit(2)
        }
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

    private static func encode(_ report: VoiceFlowBenchmarkReport) throws -> Data {
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
        }
    }
}
