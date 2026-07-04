import Foundation

private struct ListCandidate {
    var intro: String?
    var items: [String]
    var numbered: Bool
}

public struct RuleBasedSemanticEditor: SemanticEditor {
    public init() {}

    public func edit(_ request: EditorRequest) async throws -> EditorResult {
        let started = Date()
        let combined = [request.rollingPolishedText, request.stableText, request.unstableTail]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")

        var text = combined
            .replacingOccurrences(of: #"\b(um|uh|like)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b(the)\s+\1\b"#, with: "$1", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        text = resolveSimpleCorrections(text)
        text = format(text, for: request.appContext.profile)

        guard !text.isEmpty else {
            throw LocalTypeError.editorReturnedEmptyText
        }

        return EditorResult(text: text, latencyMS: Int(Date().timeIntervalSince(started) * 1000))
    }

    private func resolveSimpleCorrections(_ text: String) -> String {
        if text.range(of: #"\bactually\s+no\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return text
        }

        var result = text
        let replacementPatterns = [
            #"\b(.+?)\s+sorry\s+(.+)$"#,
            #"\b(.+?)\s+actually\s+say\s+(.+)$"#,
            #"\b(.+?)\s+actually\s+(.+)$"#,
            #"\b(.+?)\s+make that\s+(.+)$"#
        ]

        for pattern in replacementPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                if let match = regex.firstMatch(in: result, range: range), match.numberOfRanges >= 3,
                   let prefixRange = Range(match.range(at: 1), in: result),
                   let replacementRange = Range(match.range(at: 2), in: result) {
                    let prefix = String(result[prefixRange])
                    let replacement = String(result[replacementRange])
                    result = mergeCorrection(prefix: prefix, replacement: replacement)
                }
            }
        }

        return result
    }

    private func mergeCorrection(prefix: String, replacement: String) -> String {
        let prefixWords = prefix.split(separator: " ").map(String.init)
        let replacementWords = replacement.split(separator: " ").map(String.init)

        guard let firstReplacement = replacementWords.first?.lowercased(),
              let overlapIndex = prefixWords.lastIndex(where: { $0.lowercased() == firstReplacement }) else {
            return replacement
        }

        return (prefixWords.prefix(overlapIndex) + replacementWords).joined(separator: " ")
    }

    private func format(_ text: String, for profile: AppProfile) -> String {
        if let list = listCandidate(from: text, profile: profile) {
            return renderList(list)
        }

        var formatted = normalizeInlineNumbers(in: text)
        formatted = formatted.replacingOccurrences(of: " and ", with: " and ")
        formatted = formatted.prefix(1).uppercased() + formatted.dropFirst()

        if !formatted.hasSuffix(".") && !formatted.hasSuffix("?") && !formatted.hasSuffix("!") {
            formatted += "."
        }

        return formatted
    }

    private func listCandidate(from text: String, profile: AppProfile) -> ListCandidate? {
        guard profile != .codeEditor else {
            return nil
        }

        let lower = text.lowercased()
        let hasExplicitListIntent = [
            "shopping list",
            "grocery list",
            "todo list",
            "to do list",
            "task list",
            "numbered list",
            "make a list",
            "create a list",
            "list of",
            "grocery order"
        ].contains { lower.contains($0) }

        let hasGroceryContext = containsGroceryTerm(in: lower)
        let hasShoppingIntent = lower.contains("going shopping")
            || lower.contains("grocery order")
            || (hasGroceryContext && (
                lower.contains("need to buy")
                    || lower.contains("need to get")
                    || lower.contains("we need")
                    || lower.contains("pick up")
            ))

        let hasMessyGroceryIntent = lower.contains("what else")
            || lower.contains("might as well order")
            || (lower.contains("order") && containsGroceryTerm(in: lower))
            || (lower.contains("washing liquid") && containsGroceryTerm(in: lower))

        let hasNotesItemIntent = profile == .notes
            && (
                lower.contains(" add ")
                    || lower.hasPrefix("add ")
                    || lower.contains(" get ")
                    || lower.hasPrefix("get ")
                    || lower.contains(" buy ")
                    || lower.hasPrefix("buy ")
                    || lower.contains(" we need ")
                    || lower.hasPrefix("we need ")
            )

        guard hasExplicitListIntent || hasShoppingIntent || hasMessyGroceryIntent || hasNotesItemIntent else {
            return nil
        }

        let numbered = prefersNumberedList(text)
        let embedded = embeddedItemSegment(in: text, hasExplicitListIntent: hasExplicitListIntent || hasShoppingIntent)
        let body = stripListLeadIn(
            from: embedded.itemsText ?? normalizeGroceryDictationText(text, isGroceryContext: hasMessyGroceryIntent || hasShoppingIntent || hasExplicitListIntent),
            numbered: numbered
        )
        let items = splitListItems(from: body, numbered: numbered)

        let minimumItems = hasExplicitListIntent || hasShoppingIntent || hasMessyGroceryIntent ? 2 : 3
        guard items.count >= minimumItems else {
            return nil
        }

        return ListCandidate(intro: embedded.intro, items: items, numbered: numbered)
    }

    private func embeddedItemSegment(in text: String, hasExplicitListIntent: Bool) -> (intro: String?, itemsText: String?) {
        guard hasExplicitListIntent else {
            return (nil, nil)
        }

        let itemStartPatterns = [
            #"\b(?:i|we)\s+need(?:\s+to\s+(?:get|buy|order))?\b"#,
            #"\b(?:need\s+to\s+(?:get|buy|order)|should\s+get|have\s+to\s+get|pick\s+up)\b"#
        ]

        var latestMatch: (range: Range<String.Index>, pattern: String)?
        for pattern in itemStartPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                guard let swiftRange = Range(match.range, in: text) else {
                    continue
                }
                if latestMatch == nil || swiftRange.lowerBound > latestMatch!.range.lowerBound {
                    latestMatch = (swiftRange, pattern)
                }
            }
        }

        guard let latestMatch else {
            return (nil, nil)
        }

        let rawIntro = String(text[..<latestMatch.range.lowerBound])
        let rawItems = String(text[latestMatch.range.upperBound...])
        let intro = cleanEmbeddedIntro(rawIntro)
        let itemsText = trimFillerTail(rawItems)
        return (intro.isEmpty ? nil : intro, itemsText.isEmpty ? nil : itemsText)
    }

    private func cleanEmbeddedIntro(_ text: String) -> String {
        var result = text
        if let becauseRange = result.range(of: #"\bbecause\b"#, options: [.regularExpression, .caseInsensitive], range: nil, locale: nil) {
            result = String(result[..<becauseRange.lowerBound])
        }

        result = normalizeWhitespace(result)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-"))

        guard !result.isEmpty else {
            return ""
        }
        let lower = result.lowercased()
        if lower == "we are going shopping" || lower == "we're going shopping" || lower == "going shopping" {
            return ""
        }
        if !result.hasSuffix(".") && !result.hasSuffix("?") && !result.hasSuffix("!") {
            result += "."
        }
        return result.prefix(1).uppercased() + result.dropFirst()
    }

    private func trimFillerTail(_ text: String) -> String {
        var result = text
        let tailPatterns = [
            #"\bhang on\b.*$"#,
            #"\bhold on\b.*$"#,
            #"\bwait\b.*$"#,
            #"\bone second\b.*$"#,
            #"\b(?:i think|maybe|probably)\b\.?$"#
        ]

        for pattern in tailPatterns {
            result = result.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }

        return normalizeWhitespace(result)
    }

    private func normalizeGroceryDictationText(_ text: String, isGroceryContext: Bool) -> String {
        guard isGroceryContext else {
            return text
        }

        var result = text
        let replacements = [
            #"\bmake washing liquid\b"#: "dishwashing liquid",
            #"\bthe plates washing liquid\b"#: "dishwashing liquid",
            #"\bplates washing liquid\b"#: "dishwashing liquid",
            #"\bplate washing liquid\b"#: "dishwashing liquid",
            #"\bchisels\b"#: "chips",
            #"\bchisel\b"#: "chips",
            #"\bi have a\b"#: " ",
            #"\bno[,]?\s+i mean\b"#: " ",
            #"\bthe plates\b"#: " ",
            #"\bwhat else\b"#: " ",
            #"\balready\b"#: " ",
            #"\bmight as well order\b"#: " ",
            #"\border\b"#: " "
        ]

        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }

        return normalizeWhitespace(result)
    }

    private func stripListLeadIn(from text: String, numbered: Bool) -> String {
        var result = text
        let patterns = [
            #"\bfor the (?:shopping|grocery|todo|to do|task) list\b"#,
            #"\b(?:shopping|grocery|todo|to do|task) list(?: is| with| of)?\b"#,
            #"\b(?:make|create|write)(?: me)? a (?:numbered )?(?:shopping |grocery |todo |to do |task )?list(?: of| with)?\b"#,
            #"\blist of\b"#,
            #"\bwe(?: are|'re)? going shopping(?: and)?(?: we)?(?: need| need to get| need to buy| should get| have to get)?\b"#,
            #"^\s*(?:we )?(?:need to buy|need to get|should get|have to get|pick up|buy|get|add|we need|order)\b"#
        ]

        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }

        if numbered {
            result = result.replacingOccurrences(of: #"\bnumbered list\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
        }

        return normalizeWhitespace(result)
    }

    private func splitListItems(from text: String, numbered: Bool) -> [String] {
        var value = text
            .replacingOccurrences(of: #"\bactually no\s+([^,.;]+?)\s+(?=\w)"#, with: " | remove $1 | ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b(?:comma|then|plus|new line|newline|next line)\b"#, with: " | ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"[,\n;.!?]+"#, with: " | ", options: .regularExpression)

        if numbered {
            value = markNumberedItems(in: value)
        }

        value = value.replacingOccurrences(of: #"\s+\band\b\s+"#, with: " | ", options: [.regularExpression, .caseInsensitive])

        var rawItems = value
            .split(separator: "|")
            .map(String.init)

        if !numbered {
            rawItems = rawItems.flatMap(splitSpaceSeparatedItemsIfNeeded)
        }

        rawItems = applyRemoveDirectives(rawItems)

        return dedupeItems(rawItems)
            .map(cleanListItem)
            .filter { !$0.isEmpty }
    }

    private func splitSpaceSeparatedItemsIfNeeded(_ value: String) -> [String] {
        let normalized = normalizeWhitespace(value)
        let lower = normalized.lowercased()
        if lower.hasPrefix("remove ") || lower.hasPrefix("no ") {
            return [normalized]
        }

        let words = normalized
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard words.count > 1 else {
            return words
        }

        var items: [String] = []
        var index = 0
        while index < words.count {
            let remaining = words[index...].joined(separator: " ").lowercased()
            if let phrase = knownMultiwordItemPrefix(in: remaining) {
                items.append(phrase)
                index += phrase.split(separator: " ").count
            } else if index + 1 < words.count, isSpokenNumber(words[index]) {
                let numberedRemaining = words[(index + 1)...].joined(separator: " ").lowercased()
                if let phrase = knownMultiwordItemPrefix(in: numberedRemaining) {
                    items.append("\(words[index]) \(phrase)")
                    index += 1 + phrase.split(separator: " ").count
                } else {
                    items.append("\(words[index]) \(words[index + 1])")
                    index += 2
                }
            } else {
                items.append(words[index])
                index += 1
            }
        }

        return items
    }

    private func applyRemoveDirectives(_ items: [String]) -> [String] {
        var result: [String] = []
        for item in items {
            let normalized = normalizeWhitespace(item)
            let lower = normalized.lowercased()
            if lower.hasPrefix("remove ") || lower.hasPrefix("no ") {
                let target = lower
                    .replacingOccurrences(of: "remove ", with: "")
                    .replacingOccurrences(of: "no ", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                result.removeAll { $0.lowercased() == target }
            } else {
                result.append(normalized)
            }
        }
        return result
    }

    private func dedupeItems(_ items: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for item in items {
            let normalized = normalizeWhitespace(item)
            let key = normalized.lowercased()
            guard !key.isEmpty, !seen.contains(key), !isFillerListItem(key) else {
                continue
            }
            seen.insert(key)
            result.append(normalized)
        }

        return result
    }

    private func isFillerListItem(_ item: String) -> Bool {
        let fillers: Set<String> = [
            "already",
            "what else",
            "no",
            "i mean",
            "i have a",
            "might as well",
            "might",
            "as",
            "well",
            "order"
        ]
        return fillers.contains(item)
    }

    private func cleanListItem(_ item: String) -> String {
        var cleaned = normalizeWhitespace(item)
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))

        cleaned = normalizeInlineNumbers(in: cleaned)

        guard !cleaned.isEmpty else {
            return ""
        }

        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }

    private func renderList(_ candidate: ListCandidate) -> String {
        let list = candidate.items.enumerated()
            .map { index, item in
                candidate.numbered ? "\(index + 1). \(item)" : "- \(item)"
            }
            .joined(separator: "\n")

        if let intro = candidate.intro, !intro.isEmpty {
            return "\(intro)\n\nWe need:\n\(list)"
        }
        return list
    }

    private func prefersNumberedList(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("numbered list")
            || lower.contains("number one")
            || (lower.contains(" first ") && lower.contains(" second "))
            || (lower.hasPrefix("first ") && lower.contains(" second "))
    }

    private func markNumberedItems(in text: String) -> String {
        var result = text
        let markers = [
            #"\bnumber one\b"#,
            #"\bnumber two\b"#,
            #"\bnumber three\b"#,
            #"\bnumber four\b"#,
            #"\bnumber five\b"#,
            #"\bfirst\b"#,
            #"\bsecond\b"#,
            #"\bthird\b"#,
            #"\bfourth\b"#,
            #"\bfifth\b"#
        ]

        for marker in markers {
            result = result.replacingOccurrences(of: marker, with: " | ", options: [.regularExpression, .caseInsensitive])
        }

        return result
    }

    private func normalizeInlineNumbers(in text: String) -> String {
        var result = text
        for (word, number) in spokenNumberValues.sorted(by: { $0.key.count > $1.key.count }) {
            result = result.replacingOccurrences(
                of: #"\b\#(word)\s+(am|pm)\b"#,
                with: "\(number) $1",
                options: [.regularExpression, .caseInsensitive]
            )
            result = result.replacingOccurrences(
                of: #"\b\#(word)\s+([A-Za-z][A-Za-z-]*)\b"#,
                with: "\(number) $1",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        result = result.replacingOccurrences(of: #"\b([0-9]+)\s+(am|pm)\b"#, with: "$1 $2", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: " am", with: " AM", options: .caseInsensitive)
        result = result.replacingOccurrences(of: " pm", with: " PM", options: .caseInsensitive)
        return normalizeWhitespace(result)
    }

    private func knownMultiwordItemPrefix(in text: String) -> String? {
        knownMultiwordItems.first { text.hasPrefix($0) }
    }

    private func containsGroceryTerm(in text: String) -> Bool {
        groceryContextTerms.contains { term in
            text.contains(term)
        }
    }

    private func isSpokenNumber(_ word: String) -> Bool {
        spokenNumberValues[word.lowercased()] != nil
    }

    private func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private let spokenNumberValues: [String: Int] = [
    "zero": 0,
    "one": 1,
    "two": 2,
    "three": 3,
    "four": 4,
    "five": 5,
    "six": 6,
    "seven": 7,
    "eight": 8,
    "nine": 9,
    "ten": 10,
    "eleven": 11,
    "twelve": 12,
    "thirteen": 13,
    "fourteen": 14,
    "fifteen": 15,
    "sixteen": 16,
    "seventeen": 17,
    "eighteen": 18,
    "nineteen": 19,
    "twenty": 20
]

private let knownMultiwordItems = [
    "dishwashing liquid",
    "oat milk",
    "greek yogurt",
    "peanut butter",
    "ice cream",
    "orange juice",
    "apple juice",
    "paper towels",
    "toilet paper",
    "dish soap",
    "laundry detergent",
    "olive oil",
    "black beans",
    "green onions",
    "red onions",
    "chicken breast",
    "chicken breasts",
    "ground beef",
    "cream cheese",
    "coffee beans"
]

private let groceryContextTerms = [
    "dishwashing liquid",
    "washing liquid",
    "sponges",
    "sponge",
    "oat milk",
    "milk",
    "chips",
    "chisels",
    "snacks",
    "cabbage",
    "corn",
    "bread",
    "eggs",
    "yogurt"
]
