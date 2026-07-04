import Foundation
import LocalTypeCore

@main
struct LocalTypeCLI {
    static func main() async throws {
        let input = CommandLine.arguments.dropFirst().joined(separator: " ")
        guard !input.isEmpty else {
            print("Usage: localtype <raw dictation text>")
            return
        }

        let context = AppContext(appName: "CLI", profile: .balanced)
        let pipeline = DictationPipeline(profile: .development, semanticEditor: RuleBasedSemanticEditor())
        _ = try await pipeline.processStableSegment(StableSegment(text: input, isFinal: true), context: context)
        let result = try await pipeline.finish(unstableTail: "", context: context)
        print(result.text)
    }
}
