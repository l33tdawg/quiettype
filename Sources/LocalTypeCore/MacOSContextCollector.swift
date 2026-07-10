import Foundation

#if os(macOS)
import AppKit
import ApplicationServices
import Carbon

public struct AccessibilityContextCollector: ContextCollecting {
    private let appNameOverride: String?
    private let bundleIdentifierOverride: String?
    private let processIdentifierOverride: Int32?

    public init(
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        processIdentifier: Int32? = nil
    ) {
        self.appNameOverride = appName
        self.bundleIdentifierOverride = bundleIdentifier
        self.processIdentifierOverride = processIdentifier
    }

    public func currentContext() async throws -> AppContext {
        let workspace = NSWorkspace.shared
        let app = workspace.frontmostApplication
        let appName = appNameOverride ?? app?.localizedName ?? "Unknown"
        let bundleIdentifier = bundleIdentifierOverride ?? app?.bundleIdentifier
        let processIdentifier = processIdentifierOverride ?? app?.processIdentifier

        return AppContext(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            windowTitle: nil,
            selectedText: nil,
            nearbyText: nil,
            profile: Self.profile(for: appName),
            isSecureInput: Self.isSecureInput(processIdentifier: processIdentifier)
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

    private static func isSecureInput(processIdentifier: Int32?) -> Bool {
        if IsSecureEventInputEnabled() {
            return true
        }
        guard let processIdentifier else {
            return false
        }

        let application = AXUIElementCreateApplication(processIdentifier)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue else {
            return false
        }

        guard CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return false
        }
        let focusedElement = unsafeBitCast(focusedValue, to: AXUIElement.self)
        let role = stringAttribute(kAXRoleAttribute as CFString, from: focusedElement)
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: focusedElement)
        return role == "AXSecureTextField" || subrole == "AXSecureTextField"
    }

    private static func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
#endif
