import Foundation

enum StreamChunk {
    case content(String)
    case thinking(String)
    case toolCall(LLMToolCall)
    case done
    case error(String)
}

final class LLMService: @unchecked Sendable {
    let provider: LLMProvider
    private let modelNameOverride: String?

    private var baseURL: String { provider.endpoint }
    private var apiKey: String { provider.apiKey }
    private var model: String { modelNameOverride ?? provider.modelName }

    init(provider: LLMProvider, modelNameOverride: String? = nil) {
        self.provider = provider
        self.modelNameOverride = modelNameOverride
    }

    // MARK: - Fetch available models

    static func fetchModels(endpoint: String, apiKey: String) async throws -> [String] {
        let modelsEndpoint = endpoint.hasSuffix("/")
            ? endpoint + "models"
            : endpoint + "/models"

        guard let url = URL(string: modelsEndpoint) else {
            throw LLMError.invalidURL(modelsEndpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("iClaw/1.0 (https://iclaw.shadow.mov)", forHTTPHeaderField: "User-Agent")
        request.addValue("https://iclaw.shadow.mov", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("iClaw", forHTTPHeaderField: "X-Title")
        if !apiKey.isEmpty {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        let modelsResponse = try JSONDecoder().decode(ModelsListResponse.self, from: data)
        return modelsResponse.data
            .map(\.id)
            .sorted()
    }

    // MARK: - Non-streaming

    func chatCompletion(
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]? = nil
    ) async throws -> LLMChatResponse {
        let modalities: [String]? = provider.supportsImageGeneration ? ["image", "text"] : nil
        let request = LLMChatRequest(
            model: model,
            messages: messages,
            tools: tools?.isEmpty == true ? nil : tools,
            toolChoice: (tools != nil && tools?.isEmpty == false) ? .auto : nil,
            stream: false,
            maxTokens: provider.maxTokens,
            temperature: provider.temperature,
            modalities: modalities
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
        let modalities: [String]? = provider.supportsImageGeneration ? ["image", "text"] : nil
        let request = LLMChatRequest(
            model: model,
            messages: messages,
            tools: tools?.isEmpty == true ? nil : tools,
            toolChoice: (tools != nil && tools?.isEmpty == false) ? .auto : nil,
            stream: true,
            maxTokens: provider.maxTokens,
            temperature: provider.temperature,
            modalities: modalities
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
            print("[LLMService] Stream error \(httpResponse.statusCode): \(body.prefix(300))")
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        return AsyncStream { continuation in
            Task {
                var sseParser = SSEParser()
                var toolCallAccumulators: [Int: (id: String, name: String, arguments: String)] = [:]

                do {
                    for try await line in bytes.lines {
                        // Use chunk-based parsing: append "\n\n" to each line so the
                        // SSE parser immediately recognizes it as a complete event block.
                        // This is more reliable than line-based parsing because some
                        // providers/URLSession may not yield empty separator lines.
                        let events = sseParser.parse(chunk: line + "\n\n")

                        for event in events {
                            switch event {
                            case .message(let data):
                                guard let jsonData = data.data(using: .utf8) else { continue }
                                guard let chunk = try? JSONDecoder().decode(LLMChatResponse.self, from: jsonData) else { continue }

                                if let delta = chunk.choices.first?.delta {
                                    if let reasoning = delta.reasoningContent {
                                        continuation.yield(.thinking(reasoning))
                                    }

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

                                // Emit tool calls on any finish reason that indicates tool usage
                                if let reason = chunk.choices.first?.finishReason,
                                   isToolCallFinishReason(reason),
                                   !toolCallAccumulators.isEmpty {
                                    emitToolCalls(&toolCallAccumulators, continuation: continuation)
                                }

                            case .done:
                                // Also emit any remaining tool calls on stream end
                                if !toolCallAccumulators.isEmpty {
                                    emitToolCalls(&toolCallAccumulators, continuation: continuation)
                                }
                                continuation.yield(.done)
                                continuation.finish()
                                return
                            }
                        }
                    }

                    // Stream ended without [DONE] — still emit remaining data
                    if !toolCallAccumulators.isEmpty {
                        emitToolCalls(&toolCallAccumulators, continuation: continuation)
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

    // MARK: - Helpers

    private func isToolCallFinishReason(_ reason: String) -> Bool {
        reason == "tool_calls" || reason == "tool_call" || reason == "function_call"
    }

    private func emitToolCalls(
        _ accumulators: inout [Int: (id: String, name: String, arguments: String)],
        continuation: AsyncStream<StreamChunk>.Continuation
    ) {
        for (_, acc) in accumulators.sorted(by: { $0.key < $1.key }) {
            // Generate a fallback ID if the provider didn't send one
            let callId = acc.id.isEmpty ? "call_\(UUID().uuidString.prefix(8))" : acc.id
            let toolCall = LLMToolCall(
                id: callId,
                name: acc.name,
                arguments: acc.arguments
            )
            continuation.yield(.toolCall(toolCall))
        }
        accumulators.removeAll()
    }

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
        request.addValue("iClaw/1.0 (https://iclaw.shadow.mov)", forHTTPHeaderField: "User-Agent")
        request.addValue("https://iclaw.shadow.mov", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("iClaw", forHTTPHeaderField: "X-Title")

        if !apiKey.isEmpty {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(body)
        request.httpBody = bodyData

        #if DEBUG
        if let bodyStr = String(data: bodyData, encoding: .utf8) {
            let preview = bodyStr.prefix(500)
            print("[LLMService] POST \(endpoint) body=\(preview)...")
        }
        #endif

        return request
    }
}

// MARK: - Models API response types

struct ModelsListResponse: Codable {
    let data: [ModelInfo]

    struct ModelInfo: Codable {
        let id: String
        let created: Int?
        let ownedBy: String?

        enum CodingKeys: String, CodingKey {
            case id, created
            case ownedBy = "owned_by"
        }
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
