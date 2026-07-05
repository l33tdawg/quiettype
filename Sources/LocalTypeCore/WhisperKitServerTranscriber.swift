import Foundation

public struct WhisperKitServerTranscriber: AudioFileTranscribing {
    private let endpoint: URL
    private let model: String
    private let language: String?
    private let timeoutSeconds: TimeInterval

    public init(
        endpoint: URL = URL(string: "http://127.0.0.1:50060/v1/audio/transcriptions")!,
        model: String = "large-v3-v20240930_626MB",
        language: String? = "en",
        timeoutSeconds: TimeInterval = 8.0
    ) {
        self.endpoint = endpoint
        self.model = model
        self.language = language
        self.timeoutSeconds = timeoutSeconds
    }

    public func transcribe(audioFile: URL, options: AudioTranscriptionOptions) async throws -> String {
        guard endpoint.isLoopbackHTTP else {
            throw AudioTranscriberError.nonLoopbackEndpoint(endpoint.absoluteString)
        }

        let boundary = "QuietType-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try multipartBody(audioFile: audioFile, boundary: boundary, options: options)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AudioTranscriberError.badResponse(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AudioTranscriberError.badResponse(http.statusCode)
        }

        let transcript = try parseTranscript(from: data)
        guard !transcript.isEmpty else {
            throw AudioTranscriberError.emptyTranscript
        }
        guard !WhisperCommandASRBackend.isNoiseOnlyTranscript(transcript) else {
            throw AudioTranscriberError.noiseOnlyTranscript(transcript)
        }
        return transcript
    }

    private func multipartBody(audioFile: URL, boundary: String, options: AudioTranscriptionOptions) throws -> Data {
        var data = Data()
        data.appendMultipartField(name: "model", value: model, boundary: boundary)
        if let language {
            data.appendMultipartField(name: "language", value: language, boundary: boundary)
        }
        if let prompt = options.initialPrompt {
            data.appendMultipartField(name: "prompt", value: prompt, boundary: boundary)
        }
        data.appendMultipartField(name: "response_format", value: "json", boundary: boundary)
        data.appendMultipartFile(name: "file", filename: audioFile.lastPathComponent, contentType: "audio/wav", fileData: try Data(contentsOf: audioFile), boundary: boundary)
        data.appendString("--\(boundary)--\r\n")
        return data
    }

    private func parseTranscript(from data: Data) throws -> String {
        if let decoded = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) {
            return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private struct TranscriptionResponse: Decodable {
    var text: String
}

private extension Data {
    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendMultipartFile(name: String, filename: String, contentType: String, fileData: Data, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(contentType)\r\n\r\n")
        append(fileData)
        appendString("\r\n")
    }

    mutating func appendString(_ value: String) {
        append(contentsOf: value.utf8)
    }
}

private extension URL {
    var isLoopbackHTTP: Bool {
        guard scheme == "http", let host else {
            return false
        }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
}
