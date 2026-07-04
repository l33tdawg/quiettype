import Foundation
import LocalTypeCore

@main
struct LocalTypeSessionCLI {
    static func main() async throws {
        let input = CommandLine.arguments.dropFirst().joined(separator: " ")
        guard !input.isEmpty else {
            print("Usage: localtype-session <raw dictation text>")
            return
        }

        let inserter = BufferingTextInserter()
        let controller = DictationSessionController(
            profile: .development,
            asrBackend: TranscriptASRBackend(transcript: input),
            contextCollector: StaticContextCollector(context: AppContext(appName: "CLI", profile: .balanced)),
            inserter: inserter,
            memoryStore: SQLiteMemoryStore(),
            semanticEditor: RuleBasedSemanticEditor()
        )

        try await controller.begin()
        let result = try await controller.finishAndInsert()

        print(result.text)
        if let latency = result.timing.keyReleaseToInsertMS {
            FileHandle.standardError.write(Data("key_release_to_insert_ms=\(latency)\n".utf8))
        }
    }
}
