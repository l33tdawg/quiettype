import Foundation

public struct UpdateDownloadProgress: Equatable, Sendable {
    public var bytesDownloaded: Int64
    public var totalBytesExpected: Int64?

    public init(bytesDownloaded: Int64, totalBytesExpected: Int64?) {
        self.bytesDownloaded = max(0, bytesDownloaded)
        if let totalBytesExpected, totalBytesExpected > 0 {
            self.totalBytesExpected = totalBytesExpected
        } else {
            self.totalBytesExpected = nil
        }
    }

    public var fractionCompleted: Double? {
        guard let totalBytesExpected else {
            return nil
        }
        return min(max(Double(bytesDownloaded) / Double(totalBytesExpected), 0), 1)
    }

    public var displayText: String {
        let downloaded = Self.formatBytes(bytesDownloaded)
        guard let totalBytesExpected,
              let fractionCompleted else {
            return "\(downloaded) downloaded"
        }
        let percentage = min(100, max(0, Int((fractionCompleted * 100).rounded(.down))))
        return "\(percentage)% · \(downloaded) of \(Self.formatBytes(totalBytesExpected))"
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let value = Double(max(0, bytes))
        let units: [(threshold: Double, divisor: Double, suffix: String)] = [
            (1_073_741_824, 1_073_741_824, "GB"),
            (1_048_576, 1_048_576, "MB"),
            (1_024, 1_024, "KB")
        ]
        for unit in units where value >= unit.threshold {
            let scaled = value / unit.divisor
            if scaled >= 10 || scaled.rounded() == scaled {
                return "\(Int(scaled.rounded())) \(unit.suffix)"
            }
            return String(format: "%.1f %@", scaled, unit.suffix)
        }
        return "\(Int64(value)) B"
    }
}
