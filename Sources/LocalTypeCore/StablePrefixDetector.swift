import Foundation

public struct StablePrefixDetector: Sendable {
    private let minimumSharedSuffixDrop: Int

    public init(minimumSharedSuffixDrop: Int = 2) {
        self.minimumSharedSuffixDrop = minimumSharedSuffixDrop
    }

    public func stablePrefix(previousPartial: String, currentPartial: String) -> String {
        let previousWords = previousPartial.split(separator: " ").map(String.init)
        let currentWords = currentPartial.split(separator: " ").map(String.init)
        var shared: [String] = []

        for (left, right) in zip(previousWords, currentWords) {
            guard left.caseInsensitiveCompare(right) == .orderedSame else {
                break
            }
            shared.append(right)
        }

        let stableCount = max(0, shared.count - minimumSharedSuffixDrop)
        return shared.prefix(stableCount).joined(separator: " ")
    }
}
