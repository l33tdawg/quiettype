import Foundation

#if os(macOS)
import AppKit
import Carbon

public enum HotKeyPhase: Equatable, Sendable {
    case pressed
    case released
}

public struct HotKeyDescriptor: Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let defaultPushToTalk = HotKeyDescriptor(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey)
    )

    public static let functionToggle = HotKeyDescriptor(
        keyCode: UInt32(kVK_Function),
        modifiers: 0
    )

    public static let controlShiftD = HotKeyDescriptor(
        keyCode: UInt32(kVK_ANSI_D),
        modifiers: UInt32(controlKey | shiftKey)
    )
}

public final class CarbonHotKeyController {
    private let descriptor: HotKeyDescriptor
    private let handler: @Sendable (HotKeyPhase) -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    public init(
        descriptor: HotKeyDescriptor = .defaultPushToTalk,
        handler: @escaping @Sendable (HotKeyPhase) -> Void
    ) {
        self.descriptor = descriptor
        self.handler = handler
    }

    deinit {
        unregister()
    }

    public func register() throws {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else {
                return noErr
            }
            let controller = Unmanaged<CarbonHotKeyController>.fromOpaque(userData).takeUnretainedValue()
            let kind = GetEventKind(event)
            controller.handler(kind == UInt32(kEventHotKeyReleased) ? .released : .pressed)
            return noErr
        }, eventTypes.count, &eventTypes, Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)

        guard handlerStatus == noErr else {
            throw MacOSAdapterError.hotKeyRegistrationFailed(handlerStatus)
        }

        let hotKeyID = EventHotKeyID(signature: OSType("LTYP".fourCharCode), id: 1)
        let status = RegisterEventHotKey(
            descriptor.keyCode,
            descriptor.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            throw MacOSAdapterError.hotKeyRegistrationFailed(status)
        }
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}

public final class FunctionKeyToggleMonitor {
    private let handler: @Sendable () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isFunctionDown = false

    public init(handler: @escaping @Sendable () -> Void) {
        self.handler = handler
    }

    deinit {
        unregister()
    }

    public func register() throws {
        guard globalMonitor == nil && localMonitor == nil else {
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }

        guard globalMonitor != nil || localMonitor != nil else {
            throw MacOSAdapterError.hotKeyRegistrationFailed(-1)
        }
    }

    public func unregister() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        isFunctionDown = false
    }

    private func handle(_ event: NSEvent) {
        let isDown = event.modifierFlags.contains(.function)
        defer {
            isFunctionDown = isDown
        }

        guard isDown, !isFunctionDown else {
            return
        }

        handler()
    }
}

private extension String {
    var fourCharCode: UInt32 {
        utf8.reduce(UInt32(0)) { ($0 << 8) + UInt32($1) }
    }
}
#endif
