import Foundation

#if os(macOS)
import AVFoundation

public final class AVAudioCaptureService {
    private let engine = AVAudioEngine()
    private let sampleRate: Double
    private let frameHandler: (AudioFrame) async -> Void

    public init(sampleRate: Double = 16_000, frameHandler: @escaping (AudioFrame) async -> Void) {
        self.sampleRate = sampleRate
        self.frameHandler = frameHandler
    }

    public func start() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [frameHandler] buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else {
                return
            }
            let count = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channel, count: count))
            let frame = AudioFrame(samples: samples, sampleRate: Int(inputFormat.sampleRate), timestamp: Date().timeIntervalSince1970)

            Task {
                await frameHandler(frame)
            }
        }

        engine.prepare()
        try engine.start()
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
#endif
