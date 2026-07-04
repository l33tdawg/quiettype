import Foundation

public struct PromptBuilder: Sendable {
    public init() {}

    public func prompt(for request: EditorRequest) -> String {
        let vocabulary = request.profile.vocabulary
            .map { "- \($0.preferredSpelling): spoken as \($0.spokenForms.joined(separator: ", "))" }
            .joined(separator: "\n")

        return """
        You are a local-only dictation editor. Return only the final text to insert.

        Rules:
        - Preserve the user's meaning.
        - Do not add facts, names, claims, greetings, or signoffs unless explicitly spoken.
        - Remove fillers, repeated words, and false starts.
        - Resolve corrections such as "sorry", "actually", "no", and "make that".
        - Add punctuation and paragraphing.
        - Preserve technical terms, acronyms, code identifiers, and symbols.
        - For lists, use bullets only when the speech clearly enumerates items or the app profile prefers structure.

        App profile: \(request.appContext.profile.rawValue)
        Active app: \(request.appContext.appName)

        User vocabulary:
        \(vocabulary.isEmpty ? "- none" : vocabulary)

        Already polished text:
        \(request.rollingPolishedText.isEmpty ? "(empty)" : request.rollingPolishedText)

        Stable transcript:
        \(request.stableText)

        Unstable final tail:
        \(request.unstableTail.isEmpty ? "(none)" : request.unstableTail)
        """
    }
}
