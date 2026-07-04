import Foundation

#if os(macOS)
import AppKit
import ApplicationServices

public struct AccessibilityContextCollector: ContextCollecting {
    public init() {}

    public func currentContext() async throws -> AppContext {
        let workspace = NSWorkspace.shared
        let app = workspace.frontmostApplication
        let appName = app?.localizedName ?? "Unknown"

        return AppContext(
            appName: appName,
            windowTitle: nil,
            selectedText: nil,
            nearbyText: nil,
            profile: Self.profile(for: appName),
            isSecureInput: false
        )
    }

    private static func profile(for appName: String) -> AppProfile {
        let lower = appName.lowercased()
        if lower.contains("slack") || lower.contains("teams") || lower.contains("messages") {
            return .messaging
        }
        if lower.contains("mail") || lower.contains("outlook") {
            return .email
        }
        if lower.contains("notes") {
            return .notes
        }
        if lower.contains("cursor") || lower.contains("code") || lower.contains("xcode") {
            return .codeEditor
        }
        if lower.contains("safari") || lower.contains("chrome") || lower.contains("firefox") {
            return .browser
        }
        return .balanced
    }
}
#endif
