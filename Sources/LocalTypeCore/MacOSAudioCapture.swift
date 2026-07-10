import Foundation

#if os(macOS)
import AVFoundation

public final class AVAudioCaptureService {
    private let engine = AVAudioEngine()
    private let asynchronousFrameHandler: ((AudioFrame) async -> Void)?
    private let synchronousFrameHandler: ((AudioFrame) -> Void)?

    public init(frameHandler: @escaping (AudioFrame) async -> Void) {
        self.asynchronousFrameHandler = frameHandler
        self.synchronousFrameHandler = nil
    }

    public init(synchronousFrameHandler: @escaping (AudioFrame) -> Void) {
        self.asynchronousFrameHandler = nil
        self.synchronousFrameHandler = synchronousFrameHandler
    }

    public func start() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) {
            [asynchronousFrameHandler, synchronousFrameHandler] buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else {
                return
            }
            let count = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channel, count: count))
            let frame = AudioFrame(samples: samples, sampleRate: Int(inputFormat.sampleRate), timestamp: Date().timeIntervalSince1970)

            if let synchronousFrameHandler {
                synchronousFrameHandler(frame)
            } else if let asynchronousFrameHandler {
                Task {
                    await asynchronousFrameHandler(frame)
                }
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
#endif
