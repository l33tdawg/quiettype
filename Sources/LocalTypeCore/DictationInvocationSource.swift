public enum DictationInvocationSource: Sendable {
    case inAppControl
    case globalShortcut

    public var forcesPreviewOnly: Bool {
        self == .inAppControl
    }

    public var usesExternalApplicationTarget: Bool {
        self == .globalShortcut
    }
}
