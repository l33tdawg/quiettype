import Foundation

public actor DictationPipeline {
    private let profile: DictationProfile
    private let correctionEngine: CorrectionEngine
    private let semanticEditor: SemanticEditor
    private var stableText: String = ""
    private var rollingPolishedText: String = ""

    public init(profile: DictationProfile, semanticEditor: SemanticEditor) {
        self.profile = profile
        self.correctionEngine = CorrectionEngine(profile: profile)
        self.semanticEditor = semanticEditor
    }

    public func processStableSegment(_ segment: StableSegment, context: AppContext) async throws -> EditorResult {
        let corrected = correctionEngine.apply(to: segment.text)
        stableText = [stableText, corrected].filter { !$0.isEmpty }.joined(separator: " ")

        let request = EditorRequest(
            stableText: corrected,
            rollingPolishedText: rollingPolishedText,
            appContext: context,
            profile: profile,
            isFinal: segment.isFinal
        )
        let result = try await semanticEditor.edit(request)
        rollingPolishedText = result.text
        return result
    }

    public func finish(unstableTail: String, context: AppContext) async throws -> EditorResult {
        guard !context.isSecureInput else {
            throw LocalTypeError.secureInputBlocked(context.appName)
        }

        let correctedTail = correctionEngine.apply(to: unstableTail)
        if correctedTail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !rollingPolishedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return EditorResult(text: rollingPolishedText, latencyMS: 0)
        }

        let request = EditorRequest(
            stableText: "",
            unstableTail: correctedTail,
            rollingPolishedText: rollingPolishedText,
            appContext: context,
            profile: profile,
            isFinal: true
        )
        let result = try await semanticEditor.edit(request)
        rollingPolishedText = result.text
        return result
    }
}
