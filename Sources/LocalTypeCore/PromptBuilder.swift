import Foundation

public protocol EditorPromptBuilding: Sendable {
    func prompt(for request: EditorRequest) -> String
}

public struct PromptBuilder: EditorPromptBuilding {
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
        - Profanity filter: \(request.profile.profanityFilterEnabled ? "mask explicit profanity unless it is clearly part of a quoted technical/security string." : "off; preserve profanity if the user said it.")

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

public struct SanityPromptBuilder: EditorPromptBuilding {
    public init() {}

    public func prompt(for request: EditorRequest) -> String {
        let vocabulary = request.profile.vocabulary
            .map { "- \($0.preferredSpelling): spoken as \($0.spokenForms.joined(separator: ", "))" }
            .joined(separator: "\n")

        return """
        You are QuietType's local-only dictation sanity pass. Return only the corrected final text.

        Job:
        - Start from the rule-based draft.
        - Fix only obvious ASR context mistakes, punctuation, sentence boundaries, and paragraph boundaries.
        - Preserve the user's meaning, tone, profanity setting, terminology, and order of ideas.
        - Do not add facts, examples, names, greetings, signoffs, or new claims.
        - Do not remove content unless it is a repeated filler or clear false start.
        - Do not convert prose into bullets or numbered lists unless the raw transcript explicitly asks for a list or says number one, number two, etc.
        - Prefer leaving text unchanged when the correction is uncertain.
        - Profanity filter: \(request.profile.profanityFilterEnabled ? "mask explicit profanity unless it is clearly part of a quoted technical/security string." : "off; preserve profanity if the user said it.")

        App profile: \(request.appContext.profile.rawValue)
        Active app: \(request.appContext.appName)

        User vocabulary:
        \(vocabulary.isEmpty ? "- none" : vocabulary)

        Already polished text before this segment:
        \(request.rollingPolishedText.isEmpty ? "(empty)" : request.rollingPolishedText)

        Raw transcript for this segment:
        \(request.stableText.isEmpty ? "(empty)" : request.stableText)

        Rule-based draft:
        \(request.unstableTail)
        """
    }
}
