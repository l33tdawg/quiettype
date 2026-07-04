import Foundation

#if os(macOS)
import AppKit

public struct ClipboardTextInserter: TextInserting {
    public init() {}

    public func insert(_ text: String, into context: AppContext) async throws {
        guard !context.isSecureInput else {
            throw LocalTypeError.secureInputBlocked(context.appName)
        }

        await MainActor.run {
            let pasteboard = NSPasteboard.general
            let previousString = pasteboard.string(forType: .string)

            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            let source = CGEventSource(stateID: .combinedSessionState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)

            if let previousString {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(previousString, forType: .string)
                }
            }
        }
    }
}

public enum MacOSAdapterError: Error, Equatable {
    case hotKeyRegistrationFailed(OSStatus)
}
#endif
