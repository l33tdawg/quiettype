import Foundation

#if os(macOS)
import AVFoundation
import ApplicationServices
import AppKit

public enum PermissionState: String, Codable, Equatable, Sendable {
    case granted
    case denied
    case notDetermined
    case unknown
}

public struct QuietTypePermissionSnapshot: Codable, Equatable, Sendable {
    public var microphone: PermissionState
    public var accessibility: PermissionState

    public init(microphone: PermissionState, accessibility: PermissionState) {
        self.microphone = microphone
        self.accessibility = accessibility
    }

    public var isReadyForDictation: Bool {
        microphone == .granted && accessibility == .granted
    }
}

public struct MacOSPermissionService: Sendable {
    public init() {}

    public func snapshot(promptForAccessibility: Bool = false) async -> QuietTypePermissionSnapshot {
        let microphone = await microphoneState()
        let accessibility = accessibilityState(prompt: promptForAccessibility)
        return QuietTypePermissionSnapshot(microphone: microphone, accessibility: accessibility)
    }

    public func requestMicrophone() async -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            return granted ? .granted : .denied
        @unknown default:
            return .unknown
        }
    }

    public func requestAccessibility() -> PermissionState {
        let state = accessibilityState(prompt: true)
        if state != .granted {
            openAccessibilitySettings()
        }
        return state
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func microphoneState() async -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unknown
        }
    }

    private func accessibilityState(prompt: Bool) -> PermissionState {
        if AXIsProcessTrusted() {
            return .granted
        }
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options) ? .granted : .denied
    }
}
#endif
