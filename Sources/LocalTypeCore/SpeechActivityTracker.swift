import Foundation

public enum SpeechActivityState: String, Codable, Equatable, Sendable {
    case silence
    case speech
    case hangover
}

public struct SpeechActivityConfiguration: Codable, Equatable, Sendable {
    public var initialNoiseFloorRMS: Double
    public var minimumSpeechRMS: Double
    public var activationMultiplier: Double
    public var releaseMultiplier: Double
    public var activationDurationMS: Int
    public var hangoverDurationMS: Int
    public var noiseFloorRiseRate: Double
    public var noiseFloorFallRate: Double

    public init(
        initialNoiseFloorRMS: Double = 0.006,
        minimumSpeechRMS: Double = 0.0045,
        activationMultiplier: Double = 1.9,
        releaseMultiplier: Double = 1.35,
        activationDurationMS: Int = 90,
        hangoverDurationMS: Int = 650,
        noiseFloorRiseRate: Double = 0.015,
        noiseFloorFallRate: Double = 0.08
    ) {
        self.initialNoiseFloorRMS = max(0.0001, initialNoiseFloorRMS)
        self.minimumSpeechRMS = max(0.0001, minimumSpeechRMS)
        self.activationMultiplier = max(1.01, activationMultiplier)
        self.releaseMultiplier = min(max(1.0, releaseMultiplier), self.activationMultiplier)
        self.activationDurationMS = max(0, activationDurationMS)
        self.hangoverDurationMS = max(0, hangoverDurationMS)
        self.noiseFloorRiseRate = min(max(noiseFloorRiseRate, 0), 1)
        self.noiseFloorFallRate = min(max(noiseFloorFallRate, 0), 1)
    }

    public static let quietTypeDefault = SpeechActivityConfiguration()
}

public struct SpeechActivityUpdate: Codable, Equatable, Sendable {
    public var state: SpeechActivityState
    public var didStartSpeech: Bool
    public var didEndSpeech: Bool
    public var frameDurationMS: Int
    public var noiseFloorRMS: Double
    public var activationThresholdRMS: Double
    public var releaseThresholdRMS: Double

    public var isSpeechActive: Bool {
        state != .silence
    }
}

/// A lightweight, fully local energy tracker used for diagnostics and future
/// endpointing experiments. It does not discard audio or end dictation.
public struct SpeechActivityTracker: Sendable {
    public let configuration: SpeechActivityConfiguration
    public private(set) var state: SpeechActivityState = .silence
    public private(set) var noiseFloorRMS: Double

    private var candidateSpeechDurationMS = 0
    private var belowReleaseDurationMS = 0

    public init(configuration: SpeechActivityConfiguration = .quietTypeDefault) {
        self.configuration = configuration
        self.noiseFloorRMS = configuration.initialNoiseFloorRMS
    }

    public mutating func reset() {
        state = .silence
        noiseFloorRMS = configuration.initialNoiseFloorRMS
        candidateSpeechDurationMS = 0
        belowReleaseDurationMS = 0
    }

    public mutating func observe(rms: Double, frameDurationSeconds: Double) -> SpeechActivityUpdate {
        let safeRMS = min(max(rms.isFinite ? rms : 0, 0), 1)
        let frameDurationMS = max(0, Int((frameDurationSeconds * 1_000).rounded()))
        let activationThreshold = max(
            configuration.minimumSpeechRMS,
            noiseFloorRMS * configuration.activationMultiplier
        )
        let releaseThreshold = max(
            configuration.minimumSpeechRMS * 0.75,
            noiseFloorRMS * configuration.releaseMultiplier
        )
        var didStartSpeech = false
        var didEndSpeech = false

        switch state {
        case .silence:
            belowReleaseDurationMS = 0
            if safeRMS >= activationThreshold {
                candidateSpeechDurationMS += frameDurationMS
                if candidateSpeechDurationMS >= configuration.activationDurationMS {
                    state = .speech
                    candidateSpeechDurationMS = 0
                    didStartSpeech = true
                }
            } else {
                candidateSpeechDurationMS = 0
                updateNoiseFloor(toward: safeRMS)
            }

        case .speech:
            candidateSpeechDurationMS = 0
            if safeRMS >= releaseThreshold {
                belowReleaseDurationMS = 0
            } else {
                belowReleaseDurationMS = frameDurationMS
                state = .hangover
            }

        case .hangover:
            if safeRMS >= releaseThreshold {
                state = .speech
                belowReleaseDurationMS = 0
            } else {
                belowReleaseDurationMS += frameDurationMS
                if belowReleaseDurationMS >= configuration.hangoverDurationMS {
                    state = .silence
                    belowReleaseDurationMS = 0
                    didEndSpeech = true
                    updateNoiseFloor(toward: safeRMS)
                }
            }
        }

        return SpeechActivityUpdate(
            state: state,
            didStartSpeech: didStartSpeech,
            didEndSpeech: didEndSpeech,
            frameDurationMS: frameDurationMS,
            noiseFloorRMS: noiseFloorRMS,
            activationThresholdRMS: max(
                configuration.minimumSpeechRMS,
                noiseFloorRMS * configuration.activationMultiplier
            ),
            releaseThresholdRMS: max(
                configuration.minimumSpeechRMS * 0.75,
                noiseFloorRMS * configuration.releaseMultiplier
            )
        )
    }

    private mutating func updateNoiseFloor(toward rms: Double) {
        let target = min(max(rms, 0.0004), 0.08)
        let rate = target > noiseFloorRMS
            ? configuration.noiseFloorRiseRate
            : configuration.noiseFloorFallRate
        noiseFloorRMS = min(0.08, max(0.0004, (noiseFloorRMS * (1 - rate)) + (target * rate)))
    }
}
