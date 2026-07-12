import Foundation

private final class LiveWebSocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var openingError: Error?
    private var waiter: CheckedContinuation<Void, Error>?

    func waitUntilOpen() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            defer { lock.unlock() }
            if isOpen {
                continuation.resume()
            } else if let openingError {
                continuation.resume(throwing: openingError)
            } else {
                waiter = continuation
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        lock.lock()
        isOpen = true
        let continuation = waiter
        waiter = nil
        lock.unlock()
        continuation?.resume()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        lock.lock()
        guard !isOpen else {
            lock.unlock()
            return
        }
        let error = AudioTranscriberError.requestFailed("Live transcription socket closed during its handshake.")
        openingError = error
        let continuation = waiter
        waiter = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}

public struct LiveTranscriptionResult: Equatable, Sendable {
    public var text: String
    public var coveredSampleCount: Int
    public var sampleRate: Int

    public init(text: String, coveredSampleCount: Int, sampleRate: Int) {
        self.text = text
        self.coveredSampleCount = coveredSampleCount
        self.sampleRate = sampleRate
    }

    public var coveredDurationSeconds: Double {
        Double(coveredSampleCount) / Double(max(sampleRate, 1))
    }
}

public actor WhisperKitLiveStreamClient {
    private struct Control: Encodable {
        var type: String
        var sampleRate: Int?

        enum CodingKeys: String, CodingKey {
            case type
            case sampleRate = "sample_rate"
        }
    }

    struct ServerEvent: Decodable, Equatable {
        var type: String
        var text: String?
        var coveredSamples: Int?
        var sampleRate: Int?
        var detail: String?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case coveredSamples = "covered_samples"
            case sampleRate = "sample_rate"
            case detail
        }
    }

    private let endpoint: URL
    private let session: URLSession
    private let webSocketDelegate: LiveWebSocketDelegate
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var activeSampleRate: Int?
    private var terminalResult: LiveTranscriptionResult?
    private var terminalReceived = false
    private var terminalWaiter: CheckedContinuation<LiveTranscriptionResult?, Never>?
    private var latestError: String?

    public init(
        endpoint: URL = URL(string: "ws://127.0.0.1:50060/v1/audio/live")!
    ) {
        let delegate = LiveWebSocketDelegate()
        self.endpoint = endpoint
        self.webSocketDelegate = delegate
        self.session = URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    public func append(_ frame: AudioFrame) async throws {
        if socket == nil {
            try await start(sampleRate: frame.sampleRate)
        }
        guard frame.sampleRate == activeSampleRate,
              let socket else {
            throw AudioTranscriberError.requestFailed("Live audio sample rate changed during dictation.")
        }
        let encoded = Self.encodePCM16(frame.samples)
        let maximumFrameBytes = 8 * 1024
        var offset = 0
        while offset < encoded.count {
            let end = min(encoded.count, offset + maximumFrameBytes)
            try await socket.send(.data(encoded.subdata(in: offset..<end)))
            offset = end
        }
    }

    public func flushAtSpeechBoundary() async {
        guard let socket else {
            return
        }
        try? await send(Control(type: "flush", sampleRate: nil), over: socket)
    }

    public func finish(timeoutSeconds: TimeInterval = 15) async -> LiveTranscriptionResult? {
        guard let socket else {
            return nil
        }

        // Cover the entire stop/final handshake. URLSessionWebSocketTask.send
        // can itself stall, so starting this only after `send` returns leaves
        // release-to-text waiting without a real deadline.
        let timeoutTask = Task { [weak self] in
            let nanoseconds = UInt64(max(0.1, timeoutSeconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await self?.timeoutFinish()
        }
        do {
            try await send(Control(type: "stop", sampleRate: nil), over: socket)
        } catch {
            timeoutTask.cancel()
            await cancel()
            return nil
        }
        let result = await waitForTerminal()
        timeoutTask.cancel()
        receiveTask?.cancel()
        receiveTask = nil
        socket.cancel(with: .normalClosure, reason: nil)
        self.socket = nil
        return result
    }

    private func timeoutFinish() {
        socket?.cancel(with: .goingAway, reason: nil)
        completeTerminal(nil)
    }

    public func cancel() async {
        if let socket {
            try? await send(Control(type: "cancel", sampleRate: nil), over: socket)
            socket.cancel(with: .goingAway, reason: nil)
        }
        receiveTask?.cancel()
        receiveTask = nil
        socket = nil
        activeSampleRate = nil
        completeTerminal(nil)
    }

    public func lastError() -> String? {
        latestError
    }

    private func start(sampleRate: Int) async throws {
        guard endpoint.scheme == "ws",
              ["127.0.0.1", "localhost", "::1"].contains(endpoint.host?.lowercased() ?? "") else {
            throw AudioTranscriberError.nonLoopbackEndpoint(endpoint.absoluteString)
        }

        let socket = session.webSocketTask(with: endpoint)
        self.socket = socket
        activeSampleRate = sampleRate
        terminalResult = nil
        terminalReceived = false
        latestError = nil
        socket.resume()
        do {
            try await webSocketDelegate.waitUntilOpen()
        } catch {
            throw AudioTranscriberError.requestFailed("Live socket open failed: \(error.localizedDescription)")
        }
        let openingMessage: URLSessionWebSocketTask.Message
        do {
            openingMessage = try await socket.receive()
        } catch {
            throw AudioTranscriberError.requestFailed("Live socket greeting failed: \(error.localizedDescription)")
        }
        guard case .string(let openingText) = openingMessage,
              let openingData = openingText.data(using: .utf8),
              let openingEvent = try? JSONDecoder().decode(ServerEvent.self, from: openingData),
              openingEvent.type == "connected" else {
            throw AudioTranscriberError.requestFailed("Live transcription socket did not complete its handshake.")
        }
        try await send(Control(type: "start", sampleRate: sampleRate), over: socket)
        let readyMessage = try await socket.receive()
        guard case .string(let readyText) = readyMessage,
              let readyData = readyText.data(using: .utf8),
              let readyEvent = try? JSONDecoder().decode(ServerEvent.self, from: readyData),
              readyEvent.type == "ready",
              readyEvent.sampleRate == sampleRate else {
            throw AudioTranscriberError.requestFailed("Live transcription server did not accept the audio format: \(readyMessage)")
        }
        receiveTask = Task { [weak self, weak socket] in
            guard let self, let socket else { return }
            await self.receiveMessages(from: socket)
        }
    }

    private func receiveMessages(from socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case .string(let text):
                    data = Data(text.utf8)
                case .data(let value):
                    data = value
                @unknown default:
                    continue
                }
                guard let event = try? JSONDecoder().decode(ServerEvent.self, from: data) else {
                    continue
                }
                switch event.type {
                case "final":
                    let text = event.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !text.isEmpty,
                          let coveredSamples = event.coveredSamples,
                          let sampleRate = event.sampleRate else {
                        completeTerminal(nil)
                        return
                    }
                    completeTerminal(
                        LiveTranscriptionResult(
                            text: text,
                            coveredSampleCount: coveredSamples,
                            sampleRate: sampleRate
                        )
                    )
                    return
                case "error":
                    latestError = event.detail ?? "Live transcription failed."
                    completeTerminal(nil)
                    return
                default:
                    continue
                }
            } catch {
                if !Task.isCancelled {
                    latestError = error.localizedDescription
                    completeTerminal(nil)
                }
                return
            }
        }
    }

    private func waitForTerminal() async -> LiveTranscriptionResult? {
        if terminalReceived {
            return terminalResult
        }
        return await withCheckedContinuation { continuation in
            terminalWaiter = continuation
        }
    }

    private func completeTerminal(_ result: LiveTranscriptionResult?) {
        guard !terminalReceived else {
            return
        }
        terminalReceived = true
        terminalResult = result
        terminalWaiter?.resume(returning: result)
        terminalWaiter = nil
    }

    private func send(_ control: Control, over socket: URLSessionWebSocketTask) async throws {
        let data = try JSONEncoder().encode(control)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    static func encodePCM16(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            var value = Int16(clamped * Float(Int16.max)).littleEndian
            Swift.withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data
    }
}
