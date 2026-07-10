import Foundation

#if os(macOS)
import AppKit

public struct ClipboardTextInserter: TextInserting {
    public init() {}

    public func insert(_ text: String, into context: AppContext) async throws {
        guard !context.isSecureInput else {
            throw LocalTypeError.secureInputBlocked(context.appName)
        }

        guard let processIdentifier = context.processIdentifier else {
            throw LocalTypeError.insertionFailed("No target app was captured. Copy the transcript instead.")
        }

        let activated = await MainActor.run { () -> Bool in
            guard let application = NSRunningApplication(processIdentifier: processIdentifier),
                  !application.isTerminated,
                  application.bundleIdentifier != Bundle.main.bundleIdentifier else {
                return false
            }
            if let bundleIdentifier = context.bundleIdentifier,
               application.bundleIdentifier != bundleIdentifier {
                return false
            }
            return application.activate(options: [.activateIgnoringOtherApps])
        }
        guard activated else {
            throw LocalTypeError.insertionFailed("The captured target app is no longer available.")
        }
        guard try await Self.waitForFrontmostApplication(processIdentifier: processIdentifier) else {
            throw LocalTypeError.insertionFailed("The target app did not become active. Copy the transcript instead.")
        }

        let refreshedContext = try? await AccessibilityContextCollector(
            appName: context.appName,
            bundleIdentifier: context.bundleIdentifier,
            processIdentifier: context.processIdentifier
        ).currentContext()
        guard refreshedContext?.isSecureInput != true else {
            throw LocalTypeError.secureInputBlocked(context.appName)
        }
        try Task.checkCancellation()

        let targetIsStillFrontmost = await MainActor.run {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier
        }
        guard targetIsStillFrontmost else {
            throw LocalTypeError.insertionFailed("The active app changed. Copy the transcript instead.")
        }

        let writeResult = await MainActor.run { () -> (snapshot: [[String: Data]], changeCount: Int, posted: Bool) in
            let pasteboard = NSPasteboard.general
            let snapshot = Self.snapshot(pasteboard)

            pasteboard.clearContents()
            guard pasteboard.setString(text, forType: .string) else {
                return (snapshot, pasteboard.changeCount, false)
            }
            let changeCount = pasteboard.changeCount

            let source = CGEventSource(stateID: .combinedSessionState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)

            return (snapshot, changeCount, keyDown != nil && keyUp != nil)
        }

        guard writeResult.posted else {
            await MainActor.run {
                let pasteboard = NSPasteboard.general
                if pasteboard.changeCount == writeResult.changeCount {
                    Self.restore(writeResult.snapshot, to: pasteboard)
                }
            }
            throw LocalTypeError.insertionFailed("Could not post the paste command.")
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount == writeResult.changeCount else {
                return
            }
            Self.restore(writeResult.snapshot, to: pasteboard)
        }
    }

    private static func waitForFrontmostApplication(processIdentifier: Int32) async throws -> Bool {
        for attempt in 0..<6 {
            let isFrontmost = await MainActor.run {
                NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier
            }
            if isFrontmost {
                return true
            }
            if attempt < 5 {
                try await Task.sleep(nanoseconds: 40_000_000)
            }
        }
        return false
    }

    @MainActor
    private static func snapshot(_ pasteboard: NSPasteboard) -> [[String: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type.rawValue, $0) }
            })
        }
    }

    @MainActor
    private static func restore(_ snapshot: [[String: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = snapshot.compactMap { values -> NSPasteboardItem? in
            guard !values.isEmpty else {
                return nil
            }
            let item = NSPasteboardItem()
            for (rawType, data) in values {
                item.setData(data, forType: NSPasteboard.PasteboardType(rawType))
            }
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}

public enum MacOSAdapterError: Error, Equatable {
    case hotKeyRegistrationFailed(OSStatus)
}
#endif
