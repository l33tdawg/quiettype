import Foundation

public struct QuietTypeReleaseVersion: Comparable, Equatable, Sendable {
    public enum Channel: Int, Comparable, Sendable {
        case beta = 0
        case releaseCandidate = 1
        case stable = 2

        public static func < (lhs: Channel, rhs: Channel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let major: Int
    public let minor: Int
    public let patch: Int
    public let channel: Channel
    public let prereleaseNumber: Int

    public init(
        major: Int,
        minor: Int,
        patch: Int,
        channel: Channel,
        prereleaseNumber: Int
    ) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.channel = channel
        self.prereleaseNumber = prereleaseNumber
    }

    public static func parse(_ value: String) -> QuietTypeReleaseVersion? {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("quiettype-") {
            normalized.removeFirst("quiettype-".count)
        }
        let artifactSuffix = "-macos-arm64.dmg"
        if normalized.hasSuffix(artifactSuffix) {
            normalized.removeLast(artifactSuffix.count)
        }
        if normalized.hasPrefix("v") {
            normalized.removeFirst()
        }

        let parts = normalized.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let versionParts = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard versionParts.count == 3,
              let major = Int(versionParts[0]), major >= 0,
              let minor = Int(versionParts[1]), minor >= 0,
              let patch = Int(versionParts[2]), patch >= 0 else {
            return nil
        }

        guard parts.count == 2 else {
            return QuietTypeReleaseVersion(
                major: major,
                minor: minor,
                patch: patch,
                channel: .stable,
                prereleaseNumber: 0
            )
        }

        let prereleaseParts = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        guard prereleaseParts.count == 2,
              let prereleaseNumber = Int(prereleaseParts[1]),
              prereleaseNumber > 0 else {
            return nil
        }

        let channel: Channel
        switch prereleaseParts[0] {
        case "beta":
            channel = .beta
        case "rc":
            channel = .releaseCandidate
        default:
            return nil
        }

        return QuietTypeReleaseVersion(
            major: major,
            minor: minor,
            patch: patch,
            channel: channel,
            prereleaseNumber: prereleaseNumber
        )
    }

    public var displayLabel: String {
        let version = "v\(major).\(minor).\(patch)"
        switch channel {
        case .beta:
            return "\(version) beta.\(prereleaseNumber)"
        case .releaseCandidate:
            return "\(version) RC\(prereleaseNumber)"
        case .stable:
            return version
        }
    }

    public static func < (lhs: QuietTypeReleaseVersion, rhs: QuietTypeReleaseVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.channel != rhs.channel { return lhs.channel < rhs.channel }
        return lhs.prereleaseNumber < rhs.prereleaseNumber
    }
}
