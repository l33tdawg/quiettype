import Foundation

public struct VoiceFlowTextScore: Codable, Equatable, Sendable {
    public var referenceWordCount: Int
    public var hypothesisWordCount: Int
    public var wordErrorCount: Int
    public var wordErrorRate: Double
    public var requiredTermCount: Int
    public var matchedRequiredTermCount: Int
    public var requiredTermAccuracy: Double
}

public enum VoiceFlowTextScorer {
    public static func score(
        reference: String,
        hypothesis: String,
        requiredTerms: [String] = []
    ) -> VoiceFlowTextScore {
        let referenceWords = normalizedWords(reference)
        let hypothesisWords = normalizedWords(hypothesis)
        let errorCount = editDistance(referenceWords, hypothesisWords)
        let wordErrorRate = referenceWords.isEmpty
            ? (hypothesisWords.isEmpty ? 0 : 1)
            : Double(errorCount) / Double(referenceWords.count)
        let normalizedHypothesis = " \(hypothesisWords.joined(separator: " ")) "
        let normalizedTerms = requiredTerms
            .map(normalizedWords)
            .filter { !$0.isEmpty }
        let matchedTerms = normalizedTerms.filter { termWords in
            normalizedHypothesis.contains(" \(termWords.joined(separator: " ")) ")
        }.count

        return VoiceFlowTextScore(
            referenceWordCount: referenceWords.count,
            hypothesisWordCount: hypothesisWords.count,
            wordErrorCount: errorCount,
            wordErrorRate: wordErrorRate,
            requiredTermCount: normalizedTerms.count,
            matchedRequiredTermCount: matchedTerms,
            requiredTermAccuracy: normalizedTerms.isEmpty
                ? 1
                : Double(matchedTerms) / Double(normalizedTerms.count)
        )
    }

    private static func normalizedWords(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map { word in
                word.unicodeScalars
                    .filter { CharacterSet.alphanumerics.contains($0) }
                    .map(String.init)
                    .joined()
            }
            .filter { !$0.isEmpty }
    }

    private static func editDistance(_ lhs: [String], _ rhs: [String]) -> Int {
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }

        var previous = Array(0...rhs.count)
        for (leftIndex, leftWord) in lhs.enumerated() {
            var current = Array(repeating: 0, count: rhs.count + 1)
            current[0] = leftIndex + 1
            for (rightIndex, rightWord) in rhs.enumerated() {
                let substitution = previous[rightIndex] + (leftWord == rightWord ? 0 : 1)
                let insertion = current[rightIndex] + 1
                let deletion = previous[rightIndex + 1] + 1
                current[rightIndex + 1] = min(substitution, insertion, deletion)
            }
            previous = current
        }
        return previous[rhs.count]
    }
}
