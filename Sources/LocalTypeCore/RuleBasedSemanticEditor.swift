import Foundation

private struct ListCandidate {
    var intro: String?
    var items: [String]
    var numbered: Bool
}

public struct RuleBasedSemanticEditor: SemanticEditor {
    private static let paragraphBreakToken = "<<<QUIETTYPE_PARAGRAPH_BREAK>>>"

    public init() {}

    public func edit(_ request: EditorRequest) async throws -> EditorResult {
        let started = Date()
        let combined = [request.rollingPolishedText, request.stableText, request.unstableTail]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")

        var text = combined
            .replacingOccurrences(of: #"\b(um|uh)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b(the)\s+\1\b"#, with: "$1", options: [.regularExpression, .caseInsensitive])
        text = normalizeWhitespacePreservingParagraphs(text)

        text = resolveSimpleCorrections(text)
        text = repairButMisheardAsBro(text)
        text = format(text, for: request.appContext.profile)
        text = applySpellingPreference(text, request.profile.spellingPreference)
        if request.profile.profanityFilterEnabled {
            text = applyProfanityFilter(text)
        }

        guard !text.isEmpty else {
            throw LocalTypeError.editorReturnedEmptyText
        }

        return EditorResult(text: text, latencyMS: Int(Date().timeIntervalSince(started) * 1000))
    }

    /// Whisper occasionally hears the conjunction "but" as "bro". Keep this
    /// deliberately narrow so genuine vocatives such as "thanks bro" and
    /// "bro just check this" remain untouched.
    private func repairButMisheardAsBro(_ text: String) -> String {
        var result = text
        let conjunctionPatterns = [
            (#"\bbro\s+just\s+left\b"#, "but just left"),
            (#"\bbro\s+that\s+was\b"#, "but that was"),
            (#"\bbro\s+far\s+from\b"#, "but far from")
        ]
        for (pattern, replacement) in conjunctionPatterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        result = result.replacingOccurrences(
            of: #"\b[Bb]ro\s+(\p{Lu}[\p{L}'’\-]*)\s+at\s+the\b"#,
            with: "but $1 at the",
            options: .regularExpression
        )
        return result
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
        formatted = formatProse(formatted, for: profile)

        return formatted
    }

    private func formatProse(_ text: String, for profile: AppProfile) -> String {
        let punctuated = applySpokenPunctuation(to: text)
        let explicitParagraphs = splitExplicitParagraphs(punctuated)
        if explicitParagraphs.count > 1 {
            if profile == .email {
                return explicitParagraphs
                    .map { formatParagraph($0, profile: profile) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
            }
            return explicitParagraphs
                .flatMap { formatInferredParagraphs($0, profile: profile) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }

        let existingParagraphs = splitExistingParagraphs(punctuated)
        if existingParagraphs.count > 1 {
            return existingParagraphs
                .flatMap { formatInferredParagraphs($0, profile: profile) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }

        return formatInferredParagraphs(punctuated, profile: profile)
            .joined(separator: "\n\n")
    }

    private func formatInferredParagraphs(_ text: String, profile: AppProfile) -> [String] {
        let inferred = inferSentences(in: text, profile: profile)
        let sentences = splitSentences(in: inferred).map(formatSentence).filter { !$0.isEmpty }
        guard !sentences.isEmpty else {
            return [formatSentence(text)]
        }

        return groupSentencesIntoParagraphs(sentences, profile: profile)
            .map { $0.joined(separator: " ") }
    }

    private func applySpokenPunctuation(to text: String) -> String {
        var result = " \(text) "
        let replacements = [
            (#"\s+(?:new paragraph|next paragraph)\s+"#, " \(Self.paragraphBreakToken) "),
            (#"\s+period\s+"#, ". "),
            (#"\s+full stop\s+"#, ". "),
            (#"\s+question mark\s+"#, "? "),
            (#"\s+exclamation mark\s+"#, "! "),
            (#"\s+exclamation point\s+"#, "! "),
            (#"\s+colon\s+"#, ": "),
            (#"\s+semicolon\s+"#, "; "),
            (#"\s+comma\s+"#, ", ")
        ]

        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }

        return normalizeWhitespacePreservingParagraphs(result)
    }

    private func splitExplicitParagraphs(_ text: String) -> [String] {
        text.components(separatedBy: Self.paragraphBreakToken)
            .map(normalizeWhitespace)
            .filter { !$0.isEmpty }
    }

    private func splitExistingParagraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .map(normalizeWhitespace)
            .filter { !$0.isEmpty }
    }

    private func formatParagraph(_ text: String, profile: AppProfile) -> String {
        if profile == .email {
            if let greeting = formatEmailGreetingOnly(text) {
                return greeting
            }
            if let split = splitEmailGreeting(formatSentence(text)) {
                return [split.greeting, split.body].joined(separator: "\n\n")
            }
        }

        let sentences = splitSentences(in: inferSentences(in: text, profile: profile))
            .map(formatSentence)
            .filter { !$0.isEmpty }
        if sentences.isEmpty {
            return formatSentence(text)
        }
        return sentences.joined(separator: " ")
    }

    private func formatEmailGreetingOnly(_ text: String) -> String? {
        let normalized = normalizeWhitespace(text)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        guard let regex = try? NSRegularExpression(pattern: #"^(hi|hello|hey)\s+([^,]+),?$"#, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        guard let match = regex.firstMatch(in: normalized, range: range),
              let salutationRange = Range(match.range(at: 1), in: normalized),
              let nameRange = Range(match.range(at: 2), in: normalized) else {
            return nil
        }
        let salutation = String(normalized[salutationRange])
        let name = normalizeWhitespace(String(normalized[nameRange]))
        return "\(salutation.prefix(1).uppercased() + salutation.dropFirst().lowercased()) \(name),"
    }

    private func inferSentences(in text: String, profile: AppProfile) -> String {
        var result = normalizeWhitespacePreservingParagraphs(text)
        guard !result.contains(Self.paragraphBreakToken), result.count >= 120 || profile == .email else {
            return result
        }

        guard let regex = try? NSRegularExpression(pattern: inferredBoundaryPattern, options: [.caseInsensitive]) else {
            return result
        }

        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        let matches = regex.matches(in: result, range: range)
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result),
                  let cueRange = Range(match.range(at: 1), in: result),
                  shouldInferSentenceBoundary(before: matchRange, cue: String(result[cueRange]), in: result) else {
                continue
            }
            result.replaceSubrange(matchRange, with: ". \(result[cueRange])")
        }
        return normalizeWhitespacePreservingParagraphs(result)
    }

    private var inferredBoundaryPattern: String {
        #"(?<![.!?])\s+(the main issue is|the key problem is|the next step is|separately|finally|for the [a-z ]{3,40} section|on the [a-z ]{3,40} side)\b"#
    }

    private func shouldInferSentenceBoundary(before matchRange: Range<String.Index>, cue: String, in text: String) -> Bool {
        let prior = inferredBoundaryPriorText(before: matchRange.lowerBound, in: text)
        guard wordCount(in: prior) >= 6 else {
            return false
        }
        guard !endsWithOpenConnector(prior) else {
            return false
        }

        let normalizedCue = normalizeWhitespace(cue).lowercased()
        if normalizedCue == "separately" || normalizedCue == "finally" {
            return wordCount(in: prior) >= 8
        }
        return true
    }

    private func inferredBoundaryPriorText(before index: String.Index, in text: String) -> String {
        var start = index
        while start > text.startIndex {
            let previous = text.index(before: start)
            if ".!?".contains(text[previous]) {
                break
            }
            start = previous
        }
        return normalizeWhitespace(String(text[start..<index]))
    }

    private func endsWithOpenConnector(_ text: String) -> Bool {
        let lower = normalizeWhitespace(text).lowercased()
        let suffixes = [
            " and",
            " or",
            " but",
            " so",
            " because",
            " that",
            " to",
            " for",
            " with",
            " if",
            " when",
            " while",
            " where",
            " maybe",
            " probably",
            " i think",
            " i guess",
            " it seems",
            " not sure"
        ]
        return suffixes.contains { lower == String($0.dropFirst()) || lower.hasSuffix($0) }
    }

    private func splitSentences(in text: String) -> [String] {
        let normalized = normalizeWhitespace(text)
        guard !normalized.isEmpty else {
            return []
        }

        var sentences: [String] = []
        var current = ""
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let character = normalized[index]
            current.append(character)

            if (character == "." || character == "?" || character == "!"),
               shouldSplitSentence(at: index, in: normalized) {
                sentences.append(current)
                current = ""
            }
            index = normalized.index(after: index)
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sentences.append(current)
        }
        return sentences
    }

    private func shouldSplitSentence(at index: String.Index, in text: String) -> Bool {
        let character = text[index]
        guard character == "." else {
            return true
        }

        if isDecimalPeriod(at: index, in: text) || isProtectedAbbreviationPeriod(at: index, in: text) {
            return false
        }
        return true
    }

    private func isDecimalPeriod(at index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else {
            return false
        }
        let previous = text[text.index(before: index)]
        let nextIndex = text.index(after: index)
        guard nextIndex < text.endIndex else {
            return false
        }
        return previous.isNumber && text[nextIndex].isNumber
    }

    private func isProtectedAbbreviationPeriod(at index: String.Index, in text: String) -> Bool {
        let token = tokenBeforePeriod(at: index, in: text).lowercased()
        if ["dr", "mr", "mrs", "ms", "prof", "sr", "jr", "st", "vs", "etc"].contains(token) {
            return true
        }
        if token.count == 1 {
            return true
        }
        let prefix = String(text[..<text.index(after: index)]).lowercased()
        return prefix.hasSuffix("a.m.") || prefix.hasSuffix("p.m.")
    }

    private func tokenBeforePeriod(at index: String.Index, in text: String) -> String {
        var start = index
        while start > text.startIndex {
            let previous = text.index(before: start)
            let character = text[previous]
            guard character.isLetter || character == "." else {
                break
            }
            start = previous
        }
        return String(text[start..<index])
    }

    private func formatSentence(_ text: String) -> String {
        var sentence = normalizeWhitespace(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else {
            return ""
        }

        sentence = sentence.prefix(1).uppercased() + sentence.dropFirst()
        if !sentence.hasSuffix(".") && !sentence.hasSuffix("?") && !sentence.hasSuffix("!") {
            sentence += "."
        }
        return sentence
    }

    private func groupSentencesIntoParagraphs(_ sentences: [String], profile: AppProfile) -> [[String]] {
        guard sentences.count > 1 else {
            return [sentences]
        }

        if profile == .email {
            return groupEmailSentences(sentences)
        }

        let hasCueParagraph = sentences.dropFirst().contains(where: shouldStartNewParagraph)
        guard hasCueParagraph else {
            return [sentences]
        }

        var paragraphs: [[String]] = []
        var current: [String] = []
        for sentence in sentences {
            if shouldStartNewParagraph(with: sentence), !current.isEmpty {
                paragraphs.append(current)
                current = [sentence]
            } else {
                current.append(sentence)
            }
        }
        if !current.isEmpty {
            paragraphs.append(current)
        }
        return paragraphs
    }

    private func groupEmailSentences(_ sentences: [String]) -> [[String]] {
        var remaining = sentences
        var paragraphs: [[String]] = []

        if let first = remaining.first,
           let split = splitEmailGreeting(first) {
            paragraphs.append([split.greeting])
            remaining[0] = split.body
        }

        var body: [String] = []
        for sentence in remaining {
            if isEmailSignoff(sentence) {
                if !body.isEmpty {
                    paragraphs.append(body)
                    body.removeAll()
                }
                paragraphs.append([sentence])
            } else {
                body.append(sentence)
            }
        }
        if !body.isEmpty {
            paragraphs.append(body)
        }

        return paragraphs.isEmpty ? [sentences] : paragraphs
    }

    private func splitEmailGreeting(_ sentence: String) -> (greeting: String, body: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(Hi|Hello|Hey)\s+([^,]+),\s+(.+)$"#, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(sentence.startIndex..<sentence.endIndex, in: sentence)
        guard let match = regex.firstMatch(in: sentence, range: range),
              let salutationRange = Range(match.range(at: 1), in: sentence),
              let nameRange = Range(match.range(at: 2), in: sentence),
              let bodyRange = Range(match.range(at: 3), in: sentence) else {
            return nil
        }

        let salutation = String(sentence[salutationRange])
        let name = normalizeWhitespace(String(sentence[nameRange]))
        let greeting = "\(salutation.prefix(1).uppercased() + salutation.dropFirst().lowercased()) \(name),"
        return (greeting, formatSentence(String(sentence[bodyRange])))
    }

    private func isEmailSignoff(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        return lower.hasPrefix("best,")
            || lower.hasPrefix("thanks,")
            || lower.hasPrefix("thank you,")
            || lower.hasPrefix("regards,")
    }

    private func shouldStartNewParagraph(with sentence: String) -> Bool {
        let lower = sentence.lowercased()
        return lower.hasPrefix("the main issue")
            || lower.hasPrefix("the key problem")
            || lower.hasPrefix("the next step")
            || lower.hasPrefix("separately")
            || lower.hasPrefix("finally")
            || lower.hasPrefix("for the ")
            || lower.hasPrefix("on the ")
    }

    private func wordCount(in text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber }.count
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
            "bullet list",
            "bulleted list",
            "bullet point",
            "bullet points",
            "make a list",
            "create a list",
            "list of",
            "grocery order"
        ].contains { lower.contains($0) }
        let hasBulletMarkers = lower.contains("bullet point")
            || lower.contains("bullet points")
            || bareBulletMarkerCount(in: text) >= 2
        let hasBulletListIntent = lower.contains("bullet list")
            || lower.contains("bulleted list")
            || lower.contains("bullet point")
            || lower.contains("bullet points")
            || hasBulletMarkers

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

        let hasDigitQuantitySequence = digitQuantityMarkerCount(in: text) >= 2
        let hasStructuredQuantityIntent = hasDigitQuantitySequence
            && (hasExplicitListIntent || hasGroceryContext || lower.contains("menu"))
        let hasNumberedMarkerIntent = numberedMarkerCount(in: text, includeOrdinals: false) >= 2

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

        guard hasExplicitListIntent || hasShoppingIntent || hasMessyGroceryIntent || hasNotesItemIntent || hasStructuredQuantityIntent || hasNumberedMarkerIntent || hasBulletListIntent else {
            return nil
        }

        let numbered = prefersNumberedList(text)
        let embedded = embeddedItemSegment(in: text, hasExplicitListIntent: hasExplicitListIntent || hasShoppingIntent)
        var body = stripListLeadIn(
            from: embedded.itemsText ?? normalizeGroceryDictationText(text, isGroceryContext: hasMessyGroceryIntent || hasShoppingIntent || hasExplicitListIntent),
            numbered: numbered
        )
        if numbered {
            body = stripLeadingTextBeforeFirstNumberedMarker(in: body)
        }
        let allowsBareWordItems = hasShoppingIntent
            || hasMessyGroceryIntent
            || hasGroceryContext
            || hasStructuredQuantityIntent
            || hasBulletListIntent
            || lower.contains("shopping list")
            || lower.contains("grocery list")
            || lower.contains("grocery order")
        let items = splitListItems(from: body, numbered: numbered, splitSpaceSeparated: allowsBareWordItems && !hasBulletMarkers)

        let minimumItems = hasExplicitListIntent || hasShoppingIntent || hasMessyGroceryIntent || hasStructuredQuantityIntent || hasNumberedMarkerIntent || hasBulletListIntent ? 2 : 3
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
            #"\b(?:bullet|bulleted) list(?: is| with| of)?\b"#,
            #"\b(?:make|create|write)(?: me)? a (?:numbered |bullet |bulleted )?(?:shopping |grocery |todo |to do |task )?list(?: of| with)?\b"#,
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

    private func digitQuantityMarkerCount(in text: String) -> Int {
        let regex = try? NSRegularExpression(pattern: #"\b\d+\b"#)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex?.numberOfMatches(in: text, range: range) ?? 0
    }

    private func bareBulletMarkerCount(in text: String) -> Int {
        let regex = try? NSRegularExpression(pattern: #"\bbullet\b"#, options: [.caseInsensitive])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex?.numberOfMatches(in: text, range: range) ?? 0
    }

    private func splitListItems(from text: String, numbered: Bool, splitSpaceSeparated: Bool = true) -> [String] {
        var value = text
            .replacingOccurrences(of: #"\bactually no\s+([^,.;]+?)\s+(?=\w)"#, with: " | remove $1 | ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b(?:comma|then|plus|new line|newline|next line|bullet point|bullet)\b"#, with: " | ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"[,\n;.!?]+"#, with: " | ", options: .regularExpression)

        if numbered {
            value = markNumberedItems(in: value)
        }

        value = value.replacingOccurrences(of: #"\s+\band\b\s+"#, with: " | ", options: [.regularExpression, .caseInsensitive])

        var rawItems = value
            .split(separator: "|")
            .map(String.init)

        if !numbered && splitSpaceSeparated {
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

        if let numberedItems = splitImplicitQuantityItems(words) {
            return numberedItems
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

    private func splitImplicitQuantityItems(_ words: [String]) -> [String]? {
        guard words.contains(where: isNumericMarker) else {
            return nil
        }

        let leadingStopWords: Set<String> = [
            "so",
            "let's",
            "lets",
            "do",
            "a",
            "an",
            "the",
            "menu",
            "list",
            "items",
            "item",
            "following",
            "with"
        ]

        var items: [String] = []
        var currentQuantity: String?
        var currentWords: [String] = []
        var sawQuantity = false

        func flush() {
            guard let quantity = currentQuantity else {
                currentWords.removeAll()
                return
            }
            let itemWords = trimTrailingFillerWords(currentWords)
            if !itemWords.isEmpty {
                items.append(([quantity] + itemWords).joined(separator: " "))
            }
            currentQuantity = nil
            currentWords.removeAll()
        }

        for word in words {
            let normalizedWord = normalizeToken(word)
            if isNumericMarker(word) {
                flush()
                currentQuantity = normalizeQuantity(word)
                sawQuantity = true
            } else if currentQuantity == nil {
                if !leadingStopWords.contains(normalizedWord) {
                    continue
                }
            } else {
                currentWords.append(word)
            }
        }
        flush()

        guard sawQuantity, items.count >= 2 else {
            return nil
        }
        return items
    }

    private func trimTrailingFillerWords(_ words: [String]) -> [String] {
        let trailingFillers: Set<String> = [
            "that's",
            "thats",
            "it",
            "from",
            "the",
            "supermarket",
            "store",
            "shop",
            "please",
            "thanks",
            "thank",
            "you"
        ]

        var result = words
        while let last = result.last, trailingFillers.contains(normalizeToken(last)) {
            result.removeLast()
        }
        return result
    }

    private func isNumericMarker(_ word: String) -> Bool {
        Int(normalizeToken(word)) != nil
    }

    private func normalizeQuantity(_ word: String) -> String {
        normalizeToken(word)
    }

    private func normalizeToken(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines)).lowercased()
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
            || numberedMarkerCount(in: text, includeOrdinals: false) >= 2
    }

    private func markNumberedItems(in text: String) -> String {
        var result = text
        let markers = [
            #"\bnumber\s+(?:one|1)\b"#,
            #"\bnumber\s+(?:two|2)\b"#,
            #"\bnumber\s+(?:three|3)\b"#,
            #"\bnumber\s+(?:four|4)\b"#,
            #"\bnumber\s+(?:five|5)\b"#,
            #"\bnumber\s+(?:six|6)\b"#,
            #"\bnumber\s+(?:seven|7)\b"#,
            #"\bnumber\s+(?:eight|8)\b"#,
            #"\bnumber\s+(?:nine|9)\b"#,
            #"\bnumber\s+(?:ten|10)\b"#,
            #"\bfirst\b"#,
            #"\bsecond\b"#,
            #"\bthird\b"#,
            #"\bfourth\b"#,
            #"\bfifth\b"#,
            #"\bsixth\b"#,
            #"\bseventh\b"#,
            #"\beighth\b"#,
            #"\bninth\b"#,
            #"\btenth\b"#
        ]

        for marker in markers {
            result = result.replacingOccurrences(of: marker, with: " | ", options: [.regularExpression, .caseInsensitive])
        }

        return result
    }

    private func numberedMarkerCount(in text: String, includeOrdinals: Bool) -> Int {
        numberedMarkerRanges(in: text, includeOrdinals: includeOrdinals).count
    }

    private func numberedMarkerRanges(in text: String, includeOrdinals: Bool) -> [Range<String.Index>] {
        let spokenMarkers = [
            "one", "1",
            "two", "2",
            "three", "3",
            "four", "4",
            "five", "5",
            "six", "6",
            "seven", "7",
            "eight", "8",
            "nine", "9",
            "ten", "10"
        ].joined(separator: "|")
        let ordinalMarkers = [
            "first",
            "second",
            "third",
            "fourth",
            "fifth",
            "sixth",
            "seventh",
            "eighth",
            "ninth",
            "tenth"
        ].joined(separator: "|")
        let pattern = includeOrdinals
            ? #"\b(?:number\s+(?:"# + spokenMarkers + #")|"# + ordinalMarkers + #")\b"#
            : #"\bnumber\s+(?:"# + spokenMarkers + #")\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex
            .matches(in: text, range: range)
            .compactMap { Range($0.range, in: text) }
    }

    private func stripLeadingTextBeforeFirstNumberedMarker(in text: String) -> String {
        let includeOrdinals = text.range(of: #"\bnumbered list\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        guard let firstMarker = numberedMarkerRanges(in: text, includeOrdinals: includeOrdinals).first else {
            return text
        }
        return normalizeWhitespace(String(text[firstMarker.lowerBound...]))
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
        result = result.replacingOccurrences(
            of: #"\b([0-9]+)\s*am\b"#,
            with: "$1 AM",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"\b([0-9]+)\s*pm\b"#,
            with: "$1 PM",
            options: [.regularExpression, .caseInsensitive]
        )
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

    private func normalizeWhitespacePreservingParagraphs(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: #"\n\s*\n+"#, with: " \(Self.paragraphBreakToken) ", options: .regularExpression)
        result = result
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: " \(Self.paragraphBreakToken) ", with: Self.paragraphBreakToken)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    private func applySpellingPreference(_ text: String, _ preference: SpellingPreference) -> String {
        switch preference {
        case .system:
            return text
        case .british:
            return replaceSpellingVariants(in: text, variants: americanToBritishSpelling)
        case .american:
            return replaceSpellingVariants(in: text, variants: britishToAmericanSpelling)
        }
    }

    private func applyProfanityFilter(_ text: String) -> String {
        var result = text
        let replacements = [
            ("motherfucking", "m************"),
            ("motherfucker", "m***********"),
            ("bullshit", "b*******"),
            ("fucking", "f***ing"),
            ("fucked", "f***ed"),
            ("fucker", "f***er"),
            ("asshole", "a******"),
            ("bastard", "b******"),
            ("bitch", "b****"),
            ("fuck", "f***"),
            ("shit", "s***"),
            ("damn", "d***")
        ]

        for (word, masked) in replacements {
            result = result.replacingOccurrences(
                of: #"\b\#(word)\b"#,
                with: masked,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return result
    }

    private func replaceSpellingVariants(in text: String, variants: [String: String]) -> String {
        var result = text
        for (source, target) in variants.sorted(by: { $0.key.count > $1.key.count }) {
            guard let regex = try? NSRegularExpression(
                pattern: #"\b\#(NSRegularExpression.escapedPattern(for: source))\b"#,
                options: [.caseInsensitive]
            ) else {
                continue
            }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            let matches = regex.matches(in: result, range: range)
            for match in matches.reversed() {
                guard let swiftRange = Range(match.range, in: result) else {
                    continue
                }
                let original = String(result[swiftRange])
                result.replaceSubrange(swiftRange, with: matchCase(of: original, replacement: target))
            }
        }
        return result
    }

    private func matchCase(of original: String, replacement: String) -> String {
        if original.uppercased() == original {
            return replacement.uppercased()
        }
        if original.prefix(1).uppercased() == original.prefix(1) {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
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

private let americanToBritishSpelling: [String: String] = [
    "analyze": "analyse",
    "analyzed": "analysed",
    "analyzing": "analysing",
    "behavior": "behaviour",
    "behaviors": "behaviours",
    "canceled": "cancelled",
    "canceling": "cancelling",
    "center": "centre",
    "centers": "centres",
    "color": "colour",
    "colors": "colours",
    "defense": "defence",
    "favorite": "favourite",
    "favorites": "favourites",
    "gray": "grey",
    "honor": "honour",
    "honors": "honours",
    "organize": "organise",
    "organized": "organised",
    "organizing": "organising",
    "organization": "organisation",
    "organizations": "organisations",
    "theater": "theatre",
    "theaters": "theatres",
    "traveled": "travelled",
    "traveling": "travelling"
]

private let britishToAmericanSpelling: [String: String] = Dictionary(
    uniqueKeysWithValues: americanToBritishSpelling.map { ($0.value, $0.key) }
)
