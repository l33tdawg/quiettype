import Foundation

public struct CorrectionEngine: Sendable {
    private let profile: DictationProfile

    public init(profile: DictationProfile) {
        self.profile = profile
    }

    public func apply(to transcript: String) -> String {
        var corrected = transcript

        for confusion in profile.confusions.sorted(by: { $0.heard.count > $1.heard.count }) {
            corrected = replacePhrase(confusion.heard, with: confusion.corrected, in: corrected)
        }

        for entry in profile.vocabulary {
            for spokenForm in entry.spokenForms.sorted(by: { $0.count > $1.count }) {
                corrected = replacePhrase(spokenForm, with: entry.preferredSpelling, in: corrected)
            }
        }

        return corrected
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func replacePhrase(_ phrase: String, with replacement: String, in text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: phrase.trimmingCharacters(in: .whitespacesAndNewlines))
            .replacingOccurrences(of: #"\ "#, with: #"\s+"#)
        guard !escaped.isEmpty else {
            return text
        }
        return text.replacingOccurrences(
            of: #"(?<![A-Za-z0-9])\#(escaped)(?![A-Za-z0-9])"#,
            with: replacement,
            options: [.regularExpression, .caseInsensitive, .diacriticInsensitive]
        )
    }
}
