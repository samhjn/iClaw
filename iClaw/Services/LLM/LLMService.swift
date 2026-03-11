import Foundation

enum StreamChunk {
    case content(String)
    case toolCall(LLMToolCall)
    case done
    case error(String)
}

final class LLMService: @unchecked Sendable {
    let provider: LLMProvider

    private var baseURL: String { provider.endpoint }
    private var apiKey: String { provider.apiKey }
    private var model: String { provider.modelName }

    init(provider: LLMProvider) {
        self.provider = provider
    }

    // MARK: - Non-streaming

    func chatCompletion(
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]? = nil
    ) async throws -> LLMChatResponse {
        let request = LLMChatRequest(
            model: model,
            messages: messages,
            tools: tools,
            toolChoice: tools != nil ? .auto : nil,
            stream: false,
            maxTokens: provider.maxTokens,
            temperature: provider.temperature
        )

        let urlRequest = try buildRequest(body: request)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        return try JSONDecoder().decode(LLMChatResponse.self, from: data)
    }

    // MARK: - Streaming

    func chatCompletionStream(
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]? = nil
    ) async throws -> AsyncStream<StreamChunk> {
        let request = LLMChatRequest(
            model: model,
            messages: messages,
            tools: tools,
            toolChoice: tools != nil ? .auto : nil,
            stream: true,
            maxTokens: provider.maxTokens,
            temperature: provider.temperature
        )

        let urlRequest = try buildRequest(body: request)

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var body = ""
            for try await line in bytes.lines {
                body += line
            }
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        return AsyncStream { continuation in
            Task {
                var sseParser = SSEParser()
                var toolCallAccumulators: [Int: (id: String, name: String, arguments: String)] = [:]

                do {
                    for try await line in bytes.lines {
                        let events = sseParser.parse(chunk: line + "\n\n")

                        for event in events {
                            switch event {
                            case .message(let data):
                                guard let jsonData = data.data(using: .utf8) else { continue }
                                guard let chunk = try? JSONDecoder().decode(LLMChatResponse.self, from: jsonData) else { continue }

                                if let delta = chunk.choices.first?.delta {
                                    if let content = delta.content {
                                        continuation.yield(.content(content))
                                    }

                                    if let deltaToolCalls = delta.toolCalls {
                                        for dtc in deltaToolCalls {
                                            let idx = dtc.index
                                            if toolCallAccumulators[idx] == nil {
                                                toolCallAccumulators[idx] = (
                                                    id: dtc.id ?? "",
                                                    name: dtc.function?.name ?? "",
                                                    arguments: ""
                                                )
                                            }
                                            if let id = dtc.id, !id.isEmpty {
                                                toolCallAccumulators[idx]?.id = id
                                            }
                                            if let name = dtc.function?.name, !name.isEmpty {
                                                toolCallAccumulators[idx]?.name = name
                                            }
                                            if let args = dtc.function?.arguments {
                                                toolCallAccumulators[idx]?.arguments += args
                                            }
                                        }
                                    }
                                }

                                if chunk.choices.first?.finishReason == "tool_calls" {
                                    for (_, acc) in toolCallAccumulators.sorted(by: { $0.key < $1.key }) {
                                        let toolCall = LLMToolCall(
                                            id: acc.id,
                                            name: acc.name,
                                            arguments: acc.arguments
                                        )
                                        continuation.yield(.toolCall(toolCall))
                                    }
                                    toolCallAccumulators.removeAll()
                                }

                            case .done:
                                if !toolCallAccumulators.isEmpty {
                                    for (_, acc) in toolCallAccumulators.sorted(by: { $0.key < $1.key }) {
                                        let toolCall = LLMToolCall(
                                            id: acc.id,
                                            name: acc.name,
                                            arguments: acc.arguments
                                        )
                                        continuation.yield(.toolCall(toolCall))
                                    }
                                }
                                continuation.yield(.done)
                                continuation.finish()
                                return
                            }
                        }
                    }
                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Request building

    private func buildRequest<T: Encodable>(body: T) throws -> URLRequest {
        let endpoint = baseURL.hasSuffix("/")
            ? baseURL + "chat/completions"
            : baseURL + "/chat/completions"

        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidURL(endpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        if !apiKey.isEmpty {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)
        return request
    }
}

enum LLMError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .invalidResponse: return "Invalid response from server"
        case .apiError(let code, let msg): return "API Error (\(code)): \(msg)"
        case .decodingError(let msg): return "Decoding error: \(msg)"
        }
    }
}
