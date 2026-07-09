import Foundation

public struct OllamaSemanticEditor: SemanticEditor {
    private let endpoint: URL
    private let model: String
    private let timeoutSeconds: TimeInterval
    private let promptBuilder: EditorPromptBuilding
    private let fallback: SemanticEditor?

    public init(
        endpoint: URL = URL(string: "http://127.0.0.1:11434/api/generate")!,
        model: String,
        timeoutSeconds: TimeInterval = 2.0,
        promptBuilder: EditorPromptBuilding = PromptBuilder(),
        fallback: SemanticEditor? = RuleBasedSemanticEditor()
    ) {
        self.endpoint = endpoint
        self.model = model
        self.timeoutSeconds = timeoutSeconds
        self.promptBuilder = promptBuilder
        self.fallback = fallback
    }

    public func edit(_ request: EditorRequest) async throws -> EditorResult {
        guard endpoint.isLoopbackHTTP else {
            if let fallback {
                return try await fallback.edit(request)
            }
            throw OllamaEditorError.nonLoopbackEndpoint(endpoint.absoluteString)
        }

        let started = Date()
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutSeconds
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(
            OllamaGenerateRequest(
                model: model,
                prompt: promptBuilder.prompt(for: request),
                stream: false,
                options: OllamaOptions(
                    temperature: 0,
                    topP: 0.1,
                    numPredict: 512
                )
            )
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw OllamaEditorError.badResponse
            }

            let decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
            let text = decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else {
                throw LocalTypeError.editorReturnedEmptyText
            }

            return EditorResult(text: text, latencyMS: Int(Date().timeIntervalSince(started) * 1000))
        } catch {
            if let fallback {
                return try await fallback.edit(request)
            }
            throw error
        }
    }
}

public enum OllamaEditorError: Error, Equatable {
    case nonLoopbackEndpoint(String)
    case badResponse
}

private struct OllamaGenerateRequest: Encodable {
    var model: String
    var prompt: String
    var stream: Bool
    var options: OllamaOptions
}

private struct OllamaOptions: Encodable {
    var temperature: Double
    var topP: Double
    var numPredict: Int

    enum CodingKeys: String, CodingKey {
        case temperature
        case topP = "top_p"
        case numPredict = "num_predict"
    }
}

private struct OllamaGenerateResponse: Decodable {
    var response: String
}

private extension URL {
    var isLoopbackHTTP: Bool {
        guard scheme == "http", let host else {
            return false
        }

        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
}
