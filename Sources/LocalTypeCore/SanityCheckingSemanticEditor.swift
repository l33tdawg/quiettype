import Foundation

public struct SanityCheckingSemanticEditor: SemanticEditor {
    private let primary: SemanticEditor
    private let sanityEditor: SemanticEditor?
    private let validator: SanityEditValidator

    public init(
        primary: SemanticEditor = RuleBasedSemanticEditor(),
        sanityEditor: SemanticEditor?,
        validator: SanityEditValidator = SanityEditValidator()
    ) {
        self.primary = primary
        self.sanityEditor = sanityEditor
        self.validator = validator
    }

    public func edit(_ request: EditorRequest) async throws -> EditorResult {
        let primaryResult = try await primary.edit(request)
        guard let sanityEditor else {
            return primaryResult
        }

        let rawTranscript = [request.stableText, request.unstableTail]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")

        let sanityRequest = EditorRequest(
            stableText: rawTranscript,
            unstableTail: primaryResult.text,
            rollingPolishedText: request.rollingPolishedText,
            appContext: request.appContext,
            profile: request.profile,
            isFinal: request.isFinal
        )

        do {
            let sanityResult = try await sanityEditor.edit(sanityRequest)
            guard let validatedText = validator.validatedText(
                candidate: sanityResult.text,
                draft: primaryResult.text,
                rawTranscript: rawTranscript,
                request: request
            ) else {
                return primaryResult
            }

            return EditorResult(
                text: validatedText,
                latencyMS: primaryResult.latencyMS + sanityResult.latencyMS
            )
        } catch {
            return primaryResult
        }
    }
}

public struct SanityEditValidator: Sendable {
    private let minimumLengthRatio: Double
    private let maximumLengthRatio: Double

    public init(minimumLengthRatio: Double = 0.55, maximumLengthRatio: Double = 1.65) {
        self.minimumLengthRatio = minimumLengthRatio
        self.maximumLengthRatio = maximumLengthRatio
    }

    public func validatedText(
        candidate: String,
        draft: String,
        rawTranscript: String,
        request: EditorRequest
    ) -> String? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let draftLength = semanticLength(draft)
        let candidateLength = semanticLength(trimmed)
        if draftLength > 0 {
            let ratio = Double(candidateLength) / Double(draftLength)
            guard ratio >= minimumLengthRatio, ratio <= maximumLengthRatio else {
                return nil
            }
        }

        guard preservesProtectedVocabulary(candidate: trimmed, draft: draft, profile: request.profile) else {
            return nil
        }

        guard preservesButBroDistinction(candidate: trimmed, draft: draft) else {
            return nil
        }

        guard !introducesUnsupportedList(candidate: trimmed, draft: draft, rawTranscript: rawTranscript) else {
            return nil
        }

        return trimmed
    }

    private func semanticLength(_ text: String) -> Int {
        text.filter { !$0.isWhitespace }.count
    }

    private func preservesProtectedVocabulary(candidate: String, draft: String, profile: DictationProfile) -> Bool {
        let candidateLower = candidate.lowercased()
        let draftLower = draft.lowercased()
        for entry in profile.vocabulary {
            let protectedTerms = Set([entry.term, entry.preferredSpelling])
            for term in protectedTerms where !term.isEmpty {
                let lowerTerm = term.lowercased()
                if draftLower.contains(lowerTerm), !candidateLower.contains(lowerTerm) {
                    return false
                }
            }
        }
        return true
    }

    /// A local LLM may repeat an earlier vocative "bro" by changing a later,
    /// correctly transcribed conjunction "but". Accept contextual bro-to-but
    /// cleanup, but never accept the opposite lexical drift from the draft.
    private func preservesButBroDistinction(candidate: String, draft: String) -> Bool {
        let draftButCount = wordCount("but", in: draft)
        let draftBroCount = wordCount("bro", in: draft)
        let candidateButCount = wordCount("but", in: candidate)
        let candidateBroCount = wordCount("bro", in: candidate)
        return !(candidateButCount < draftButCount && candidateBroCount > draftBroCount)
    }

    private func wordCount(_ word: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![A-Za-z0-9])\#(NSRegularExpression.escapedPattern(for: word))(?![A-Za-z0-9])"#,
            options: [.caseInsensitive]
        ) else {
            return 0
        }
        return regex.numberOfMatches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )
    }

    private func introducesUnsupportedList(candidate: String, draft: String, rawTranscript: String) -> Bool {
        guard looksLikeList(candidate), !looksLikeList(draft) else {
            return false
        }

        return !hasExplicitListIntent(rawTranscript)
    }

    private func looksLikeList(_ text: String) -> Bool {
        text.range(of: #"(?m)^\s*(?:[-*\x{2022}]|\d+[.)])\s+\S"#, options: .regularExpression) != nil
    }

    private func hasExplicitListIntent(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.range(of: #"\b(?:bullet|bulleted|numbered)\s+list\b"#, options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"\bnumber\s+(?:one|1)\b.*\bnumber\s+(?:two|2)\b"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }
}
