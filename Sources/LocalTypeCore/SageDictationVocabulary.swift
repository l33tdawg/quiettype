import Foundation

/// Mines exact spellings for likely coined terms from text already recalled from
/// the owner's local SAGE memory.
///
/// This intentionally ignores ordinary prose. Only shapes that speech
/// recognizers commonly split or normalize are retained: internal capitals,
/// longer all-caps names, and dotted or hyphenated identifiers.
public enum SageDictationVocabulary {
    /// Bounds the deterministic correction work added to every transcript.
    public static let defaultLimit = 64

    static let shortestTerm = 3

    /// Converts remembered text into the vocabulary memories already understood
    /// by `ProfileMemoryCompiler`.
    public static func memories(
        fromRemembered texts: [String],
        limit: Int = defaultLimit
    ) -> [DictationMemory] {
        ranked(fromRemembered: texts, limit: limit).map { term, confidence in
            DictationMemory(
                type: .vocabulary,
                payload: [
                    "term": term,
                    "preferred": term,
                    "category": "sage_memory"
                ],
                source: "SAGE remembered vocabulary",
                confidence: confidence
            )
        }
    }

    /// Returns owner-approved text from local review memories.
    ///
    /// Raw ASR is deliberately excluded: mining it would reinforce the
    /// recognizer's mistakes. The polished text is the spelling evidence.
    public static func rememberedTexts(from memories: [DictationMemory]) -> [String] {
        memories.compactMap { memory in
            guard memory.type == .transcriptNote || memory.type == .voiceNote else {
                return nil
            }
            return memory.payload["polished_text"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }
    }

    static func ranked(
        fromRemembered texts: [String],
        limit: Int = defaultLimit
    ) -> [(term: String, confidence: Double)] {
        var counts: [String: Int] = [:]
        var spelling: [String: String] = [:]

        for text in texts {
            var seenInMemory: Set<String> = []
            for term in coinages(in: text) {
                let key = term.lowercased()
                guard seenInMemory.insert(key).inserted else {
                    continue
                }
                counts[key, default: 0] += 1
                if spelling[key] == nil {
                    spelling[key] = term
                }
            }
        }

        let ordered = counts.keys.sorted { left, right in
            if counts[left] != counts[right] {
                return counts[left, default: 0] > counts[right, default: 0]
            }
            if left.count != right.count {
                return left.count > right.count
            }
            return left < right
        }

        let top = ordered.prefix(max(0, limit))
        let highestCount = Double(top.first.flatMap { counts[$0] } ?? 1)
        return top.compactMap { key in
            guard let term = spelling[key] else {
                return nil
            }
            let share = Double(counts[key, default: 1]) / max(1, highestCount)
            return (term, 0.5 + (0.5 * share))
        }
    }

    static func coinages(in text: String) -> [String] {
        var found: [String] = []
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ",;:!?()[]{}\"'“”‘’"))

        for raw in text.components(separatedBy: separators) {
            var token = raw
            while let last = token.last, last == "." || last == "-" {
                token.removeLast()
            }
            guard token.count >= shortestTerm, isCoinage(token) else {
                continue
            }
            found.append(token)
        }
        return found
    }

    static func isCoinage(_ token: String) -> Bool {
        guard token.count >= shortestTerm else {
            return false
        }

        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-."))
        guard token.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              token.contains(where: \.isLetter) else {
            return false
        }

        let letters = token.filter(\.isLetter)
        let uppercase = letters.filter(\.isUppercase)

        if uppercase.count == letters.count, letters.count >= 4 {
            return true
        }

        if token.dropFirst().contains(where: \.isUppercase) {
            return true
        }

        if token.contains("-") || token.contains(".") {
            let parts = token.split(whereSeparator: { $0 == "-" || $0 == "." })
            return parts.count >= 2 && parts.allSatisfy { $0.count >= 2 }
        }

        return false
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
