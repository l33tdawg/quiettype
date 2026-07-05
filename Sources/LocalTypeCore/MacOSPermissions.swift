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

    public func snapshot(promptForAccessibility: Bool = false, verifyMicrophoneAccess: Bool = false) async -> QuietTypePermissionSnapshot {
        let microphone = await microphoneState(verifyAccess: verifyMicrophoneAccess)
        let accessibility = accessibilityState(prompt: promptForAccessibility)
        return QuietTypePermissionSnapshot(microphone: microphone, accessibility: accessibility)
    }

    public func requestMicrophone() async -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            openMicrophoneSettings()
            return .denied
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            return granted ? .granted : .denied
        @unknown default:
            return .unknown
        }
    }

    public func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
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

    private func microphoneState(verifyAccess: Bool) async -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            if verifyAccess, canOpenMicrophoneInput() {
                return .granted
            }
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            if verifyAccess, canOpenMicrophoneInput() {
                return .granted
            }
            return .unknown
        }
    }

    private func canOpenMicrophoneInput() -> Bool {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            return false
        }

        input.installTap(onBus: 0, bufferSize: 128, format: format) { _, _ in }

        do {
            engine.prepare()
            try engine.start()
            input.removeTap(onBus: 0)
            engine.stop()
            return true
        } catch {
            input.removeTap(onBus: 0)
            engine.stop()
            return false
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
