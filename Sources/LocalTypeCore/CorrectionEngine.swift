import Foundation

public struct CorrectionEngine: Sendable {
    private let profile: DictationProfile

    public init(profile: DictationProfile) {
        self.profile = profile
    }

    public func apply(to transcript: String) -> String {
        var corrected = transcript

        for confusion in profile.confusions.sorted(by: { $0.heard.count > $1.heard.count }) {
            corrected = corrected.replacingOccurrences(
                of: confusion.heard,
                with: confusion.corrected,
                options: [.caseInsensitive, .diacriticInsensitive]
            )
        }

        for entry in profile.vocabulary {
            for spokenForm in entry.spokenForms.sorted(by: { $0.count > $1.count }) {
                corrected = corrected.replacingOccurrences(
                    of: spokenForm,
                    with: entry.preferredSpelling,
                    options: [.caseInsensitive, .diacriticInsensitive]
                )
            }
        }

        return corrected
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
