import Foundation

enum StreamChunk {
    case content(String)
    case thinking(String)
    case toolCall(LLMToolCall)
    case usage(LLMUsage)
    case done
    case error(String)
}

/// Thread-safe holder for the inner SSE-reading Task, allowing external cancellation
/// that bypasses AsyncStream's cooperative cancellation.
final class StreamCancelState: @unchecked Sendable {
    private let lock = NSLock()
    private var _innerTask: Task<Void, Never>?
    private var _cancelled = false

    var innerTask: Task<Void, Never>? {
        get { lock.withLock { _innerTask } }
        set {
            lock.withLock {
                _innerTask = newValue
                if _cancelled { newValue?.cancel() }
            }
        }
    }

    func cancel() {
        lock.withLock {
            _cancelled = true
            _innerTask?.cancel()
        }
    }
}

final class LLMService: @unchecked Sendable {
    let provider: LLMProvider
    private let modelNameOverride: String?
    private let thinkingLevelOverride: ThinkingLevel?

    private var baseURL: String { provider.endpoint }
    private var apiKey: String { provider.apiKey }
    private var model: String { modelNameOverride ?? provider.modelName }
    private var apiStyle: APIStyle { provider.apiStyle }

    /// Model capabilities resolved for the effective model.
    var effectiveCapabilities: ModelCapabilities {
        provider.capabilities(for: model)
    }

    /// Effective thinking level: agent override > model default from capabilities.
    var effectiveThinkingLevel: ThinkingLevel {
        thinkingLevelOverride ?? effectiveCapabilities.thinkingLevel
    }

    init(provider: LLMProvider, modelNameOverride: String? = nil, thinkingLevelOverride: ThinkingLevel? = nil) {
        self.provider = provider
        self.modelNameOverride = modelNameOverride
        self.thinkingLevelOverride = thinkingLevelOverride
    }

    // MARK: - Fetch available models

    static func fetchModels(endpoint: String, apiKey: String, apiStyle: APIStyle = .openAI) async throws -> [String] {
        let modelsEndpoint: String
        switch apiStyle {
        case .openAI:
            modelsEndpoint = endpoint.hasSuffix("/") ? endpoint + "models" : endpoint + "/models"
        case .anthropic:
            modelsEndpoint = endpoint.hasSuffix("/") ? endpoint + "models" : endpoint + "/models"
        }

        guard let url = URL(string: modelsEndpoint) else {
            throw LLMError.invalidURL(modelsEndpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("iClaw/1.0 (https://iclaw.shadow.mov)", forHTTPHeaderField: "User-Agent")
        request.addValue("https://iclaw.shadow.mov", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("iClaw", forHTTPHeaderField: "X-Title")

        switch apiStyle {
        case .openAI:
            if !apiKey.isEmpty {
                request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        case .anthropic:
            if !apiKey.isEmpty {
                request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
            }
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
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

        switch apiStyle {
        case .openAI:
            let modelsResponse = try JSONDecoder().decode(ModelsListResponse.self, from: data)
            return modelsResponse.data.map(\.id).sorted()
        case .anthropic:
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["data"] as? [[String: Any]] {
                return models.compactMap { $0["id"] as? String }.sorted()
            }
            return []
        }
    }

    // MARK: - Non-streaming

    func chatCompletion(
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]? = nil
    ) async throws -> LLMChatResponse {
        switch apiStyle {
        case .openAI:
            return try await openAIChatCompletion(messages: messages, tools: tools)
        case .anthropic:
            return try await anthropicChatCompletion(messages: messages, tools: tools)
        }
    }

    // MARK: - Streaming

    func chatCompletionStream(
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]? = nil
    ) async throws -> (stream: AsyncStream<StreamChunk>, cancel: @Sendable () -> Void) {
        switch apiStyle {
        case .openAI:
            return try await openAIChatCompletionStream(messages: messages, tools: tools)
        case .anthropic:
            return try await anthropicChatCompletionStream(messages: messages, tools: tools)
        }
    }

    // MARK: - OpenAI Implementation

    private func openAIChatCompletion(
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]?
    ) async throws -> LLMChatResponse {
        let caps = effectiveCapabilities
        let modalities: [String]? = caps.supportsImageGeneration ? ["image", "text"] : nil
        let thinkingLevel = effectiveThinkingLevel
        let request = LLMChatRequest(
            model: model,
            messages: messages,
            tools: tools?.isEmpty == true ? nil : tools,
            toolChoice: (tools != nil && tools?.isEmpty == false) ? .auto : nil,
            stream: false,
            maxTokens: provider.maxTokens,
            temperature: provider.temperature,
            modalities: modalities,
            reasoningEffort: thinkingLevel.openAIReasoningEffort
        )

        let urlRequest = try buildOpenAIRequest(body: request)
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

    private func openAIChatCompletionStream(
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]?
    ) async throws -> (stream: AsyncStream<StreamChunk>, cancel: @Sendable () -> Void) {
        let caps = effectiveCapabilities
        let modalities: [String]? = caps.supportsImageGeneration ? ["image", "text"] : nil
        let thinkingLevel = effectiveThinkingLevel
        let request = LLMChatRequest(
            model: model,
            messages: messages,
            tools: tools?.isEmpty == true ? nil : tools,
            toolChoice: (tools != nil && tools?.isEmpty == false) ? .auto : nil,
            stream: true,
            streamOptions: LLMStreamOptions(includeUsage: true),
            maxTokens: provider.maxTokens,
            temperature: provider.temperature,
            modalities: modalities,
            reasoningEffort: thinkingLevel.openAIReasoningEffort
        )

        let urlRequest = try buildOpenAIRequest(body: request)
        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            var body = ""
            for try await line in bytes.lines { body += line }
            print("[LLMService] OpenAI stream error \(httpResponse.statusCode): \(body.prefix(300))")
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        let cancelState = StreamCancelState()
        let stream = AsyncStream<StreamChunk> { continuation in
            let innerTask = Task {
                var sseParser = SSEParser()
                var toolCallAccumulators: [Int: (id: String, name: String, arguments: String)] = [:]

                do {
                    for try await line in bytes.lines {
                        guard !Task.isCancelled else { break }
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

                                if let usage = chunk.usage,
                                   (usage.promptTokens != nil || usage.completionTokens != nil || usage.totalTokens != nil) {
                                    continuation.yield(.usage(usage))
                                }

                                if let reason = chunk.choices.first?.finishReason,
                                   isToolCallFinishReason(reason),
                                   !toolCallAccumulators.isEmpty {
                                    emitToolCalls(&toolCallAccumulators, continuation: continuation)
                                }

                            case .done:
                                if !toolCallAccumulators.isEmpty {
                                    emitToolCalls(&toolCallAccumulators, continuation: continuation)
                                }
                                continuation.yield(.done)
                                continuation.finish()
                                return
                            }
                        }
                    }

                    if !toolCallAccumulators.isEmpty {
                        emitToolCalls(&toolCallAccumulators, continuation: continuation)
                    }
                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        continuation.yield(.error(error.localizedDescription))
                    }
                    continuation.finish()
                }
            }
            cancelState.innerTask = innerTask
            continuation.onTermination = { @Sendable _ in
                innerTask.cancel()
            }
        }
        return (stream, { cancelState.cancel() })
    }

    // MARK: - Anthropic Implementation

    private func anthropicChatCompletion(
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]?
    ) async throws -> LLMChatResponse {
        let anthropicReq = buildAnthropicBody(messages: messages, tools: tools, stream: false)
        let urlRequest = try buildAnthropicURLRequest(body: anthropicReq)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        let anthropicResp = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        return convertAnthropicResponse(anthropicResp)
    }

    private func anthropicChatCompletionStream(
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]?
    ) async throws -> (stream: AsyncStream<StreamChunk>, cancel: @Sendable () -> Void) {
        let anthropicReq = buildAnthropicBody(messages: messages, tools: tools, stream: true)
        let urlRequest = try buildAnthropicURLRequest(body: anthropicReq)
        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            var body = ""
            for try await line in bytes.lines { body += line }
            print("[LLMService] Anthropic stream error \(httpResponse.statusCode): \(body.prefix(300))")
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        let cancelState = StreamCancelState()
        let stream = AsyncStream<StreamChunk> { continuation in
            let innerTask = Task {
                var sseParser = SSEParser()
                var toolCallAccumulators: [Int: (id: String, name: String, arguments: String)] = [:]
                var activeBlockTypes: [Int: String] = [:]

                do {
                    for try await line in bytes.lines {
                        guard !Task.isCancelled else { break }
                        let events = sseParser.parse(chunk: line + "\n\n")

                        for event in events {
                            switch event {
                            case .message(let data):
                                guard let jsonData = data.data(using: .utf8),
                                      let streamEvent = try? JSONDecoder().decode(AnthropicStreamEvent.self, from: jsonData)
                                else { continue }

                                switch streamEvent.type {
                                case "message_start":
                                    if let msgUsage = streamEvent.message?.usage,
                                       (msgUsage.inputTokens != nil || msgUsage.outputTokens != nil) {
                                        continuation.yield(.usage(LLMUsage(
                                            promptTokens: msgUsage.inputTokens,
                                            completionTokens: msgUsage.outputTokens,
                                            totalTokens: nil
                                        )))
                                    }

                                case "content_block_start":
                                    if let idx = streamEvent.index, let block = streamEvent.contentBlock {
                                        activeBlockTypes[idx] = block.type
                                        if block.type == "tool_use" {
                                            toolCallAccumulators[idx] = (
                                                id: block.id ?? "call_\(UUID().uuidString.prefix(8))",
                                                name: block.name ?? "",
                                                arguments: ""
                                            )
                                        }
                                    }

                                case "content_block_delta":
                                    if let idx = streamEvent.index, let delta = streamEvent.delta {
                                        let blockType = activeBlockTypes[idx] ?? delta.type
                                        switch delta.type {
                                        case "text_delta":
                                            if blockType == "thinking" {
                                                if let text = delta.text { continuation.yield(.thinking(text)) }
                                            } else {
                                                if let text = delta.text { continuation.yield(.content(text)) }
                                            }
                                        case "thinking_delta":
                                            if let text = delta.thinking { continuation.yield(.thinking(text)) }
                                        case "input_json_delta":
                                            if let json = delta.partialJson {
                                                toolCallAccumulators[idx]?.arguments += json
                                            }
                                        default:
                                            break
                                        }
                                    }

                                case "content_block_stop":
                                    break

                                case "message_delta":
                                    if let usage = streamEvent.usage,
                                       (usage.inputTokens != nil || usage.outputTokens != nil) {
                                        continuation.yield(.usage(LLMUsage(
                                            promptTokens: usage.inputTokens,
                                            completionTokens: usage.outputTokens,
                                            totalTokens: nil
                                        )))
                                    }
                                    if let stopReason = streamEvent.delta?.stopReason,
                                       (stopReason == "tool_use" || stopReason == "tool_calls"),
                                       !toolCallAccumulators.isEmpty {
                                        emitToolCalls(&toolCallAccumulators, continuation: continuation)
                                    }

                                case "message_stop":
                                    if !toolCallAccumulators.isEmpty {
                                        emitToolCalls(&toolCallAccumulators, continuation: continuation)
                                    }
                                    continuation.yield(.done)
                                    continuation.finish()
                                    return

                                case "error":
                                    let errMsg = data
                                    continuation.yield(.error(errMsg))
                                    continuation.finish()
                                    return

                                default:
                                    break
                                }

                            case .done:
                                if !toolCallAccumulators.isEmpty {
                                    emitToolCalls(&toolCallAccumulators, continuation: continuation)
                                }
                                continuation.yield(.done)
                                continuation.finish()
                                return
                            }
                        }
                    }

                    if !toolCallAccumulators.isEmpty {
                        emitToolCalls(&toolCallAccumulators, continuation: continuation)
                    }
                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        continuation.yield(.error(error.localizedDescription))
                    }
                    continuation.finish()
                }
            }
            cancelState.innerTask = innerTask
            continuation.onTermination = { @Sendable _ in
                innerTask.cancel()
            }
        }
        return (stream, { cancelState.cancel() })
    }

    // MARK: - Anthropic Helpers

    private func buildAnthropicBody(
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]?,
        stream: Bool
    ) -> AnthropicRequest {
        let caps = effectiveCapabilities

        var systemBlocks: [AnthropicSystemBlock] = []
        var anthropicMessages: [AnthropicMessage] = []

        for msg in messages {
            switch msg.role {
            case "system":
                if let content = msg.content, !content.isEmpty {
                    systemBlocks.append(AnthropicSystemBlock(type: "text", text: content))
                }
            case "user":
                var blocks: [AnthropicContentBlock] = []
                if let parts = msg.contentParts, !parts.isEmpty {
                    for part in parts {
                        switch part {
                        case .text(let text):
                            if !text.isEmpty { blocks.append(.text(text)) }
                        case .imageURL(let url, _):
                            if let parsed = parseBase64DataURI(url) {
                                blocks.append(.image(mediaType: parsed.mediaType, data: parsed.data))
                            }
                        }
                    }
                } else if let content = msg.content, !content.isEmpty {
                    blocks.append(.text(content))
                }
                if !blocks.isEmpty {
                    anthropicMessages.append(AnthropicMessage(role: "user", content: blocks))
                }
            case "assistant":
                var blocks: [AnthropicContentBlock] = []
                if let content = msg.content, !content.isEmpty {
                    blocks.append(.text(content))
                }
                if let toolCalls = msg.toolCalls {
                    for tc in toolCalls {
                        blocks.append(.toolUse(id: tc.id, name: tc.function.name, input: tc.function.arguments))
                    }
                }
                if !blocks.isEmpty {
                    anthropicMessages.append(AnthropicMessage(role: "assistant", content: blocks))
                }
            case "tool":
                let toolUseId = msg.toolCallId ?? ""
                let block: AnthropicContentBlock

                if let parts = msg.contentParts,
                   parts.contains(where: { if case .imageURL = $0 { return true }; return false }) {
                    var blocks: [AnthropicToolResultBlock] = []
                    for part in parts {
                        switch part {
                        case .text(let text):
                            if !text.isEmpty { blocks.append(.text(text)) }
                        case .imageURL(let url, _):
                            if let parsed = parseBase64DataURI(url) {
                                blocks.append(.image(mediaType: parsed.mediaType, data: parsed.data))
                            }
                        }
                    }
                    block = .toolResultRich(toolUseId: toolUseId, blocks: blocks)
                } else {
                    let content = msg.content ?? ""
                    block = .toolResult(toolUseId: toolUseId, content: content)
                }

                // Anthropic tool results must be in a "user" message
                let isToolResultBlock: (AnthropicContentBlock) -> Bool = {
                    switch $0 {
                    case .toolResult, .toolResultRich: return true
                    default: return false
                    }
                }
                if let last = anthropicMessages.last, last.role == "user",
                   last.content.allSatisfy(isToolResultBlock) {
                    var merged = last.content
                    merged.append(block)
                    anthropicMessages[anthropicMessages.count - 1] = AnthropicMessage(role: "user", content: merged)
                } else {
                    anthropicMessages.append(AnthropicMessage(role: "user", content: [block]))
                }
            default:
                break
            }
        }

        // Merge consecutive same-role messages (Anthropic requires alternating roles)
        anthropicMessages = mergeConsecutiveRoles(anthropicMessages)

        var anthropicTools: [AnthropicTool]? = nil
        if let tools = tools, !tools.isEmpty {
            anthropicTools = tools.map {
                AnthropicTool(name: $0.function.name, description: $0.function.description, inputSchema: $0.function.parameters)
            }
        }

        let thinkingLevel = effectiveThinkingLevel
        var thinking: AnthropicThinking? = nil
        var maxTokens = provider.maxTokens
        if thinkingLevel.isEnabled {
            let budgetTokens = thinkingLevel.anthropicBudgetTokens
            thinking = .enabled(budget: budgetTokens)
            // Anthropic requires max_tokens > budget_tokens
            maxTokens = max(maxTokens, budgetTokens + 1)
        }

        // Anthropic requires temperature to be exactly 1 when extended thinking is enabled
        let temperature = thinking != nil ? 1.0 : provider.temperature

        return AnthropicRequest(
            model: model,
            maxTokens: maxTokens,
            system: systemBlocks.isEmpty ? nil : systemBlocks,
            messages: anthropicMessages,
            tools: anthropicTools,
            stream: stream,
            temperature: temperature,
            thinking: thinking
        )
    }

    private func mergeConsecutiveRoles(_ messages: [AnthropicMessage]) -> [AnthropicMessage] {
        var result: [AnthropicMessage] = []
        for msg in messages {
            if let last = result.last, last.role == msg.role {
                var merged = last.content
                merged.append(contentsOf: msg.content)
                result[result.count - 1] = AnthropicMessage(role: msg.role, content: merged)
            } else {
                result.append(msg)
            }
        }
        return result
    }

    private func parseBase64DataURI(_ uri: String) -> (mediaType: String, data: String)? {
        // Parse "data:image/jpeg;base64,/9j/4AAQ..."
        guard uri.hasPrefix("data:") else { return nil }
        let withoutPrefix = String(uri.dropFirst(5))
        guard let semicolonIdx = withoutPrefix.firstIndex(of: ";") else { return nil }
        let mediaType = String(withoutPrefix[withoutPrefix.startIndex..<semicolonIdx])
        let afterSemicolon = String(withoutPrefix[withoutPrefix.index(after: semicolonIdx)...])
        guard afterSemicolon.hasPrefix("base64,") else { return nil }
        let data = String(afterSemicolon.dropFirst(7))
        return (mediaType, data)
    }

    private func convertAnthropicResponse(_ resp: AnthropicResponse) -> LLMChatResponse {
        var content = ""
        var toolCalls: [LLMToolCall] = []

        for block in resp.content {
            switch block.type {
            case "text":
                content += block.text ?? ""
            case "tool_use":
                let args = block.input?.jsonString ?? "{}"
                toolCalls.append(LLMToolCall(
                    id: block.id ?? "call_\(UUID().uuidString.prefix(8))",
                    name: block.name ?? "",
                    arguments: args
                ))
            default:
                break
            }
        }

        let message = LLMChatMessage(
            role: "assistant",
            content: content.isEmpty ? nil : content,
            toolCalls: toolCalls.isEmpty ? nil : toolCalls
        )
        let choice = LLMChoice(index: 0, message: message, delta: nil, finishReason: resp.stopReason)
        let usage = LLMUsage(
            promptTokens: resp.usage?.inputTokens,
            completionTokens: resp.usage?.outputTokens,
            totalTokens: nil
        )
        return LLMChatResponse(id: resp.id, choices: [choice], usage: usage)
    }

    private func buildAnthropicURLRequest<T: Encodable>(body: T) throws -> URLRequest {
        let messagesEndpoint = baseURL.hasSuffix("/")
            ? baseURL + "messages"
            : baseURL + "/messages"

        guard let url = URL(string: messagesEndpoint) else {
            throw LLMError.invalidURL(messagesEndpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("iClaw/1.0 (https://iclaw.shadow.mov)", forHTTPHeaderField: "User-Agent")

        if !apiKey.isEmpty {
            request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(body)
        request.httpBody = bodyData

        #if DEBUG
        if let bodyStr = String(data: bodyData, encoding: .utf8) {
            print("[LLMService] POST \(messagesEndpoint) body=\(bodyStr.prefix(500))...")
        }
        #endif

        return request
    }

    // MARK: - OpenAI Helpers

    private func isToolCallFinishReason(_ reason: String) -> Bool {
        reason == "tool_calls" || reason == "tool_call" || reason == "function_call"
    }

    private func emitToolCalls(
        _ accumulators: inout [Int: (id: String, name: String, arguments: String)],
        continuation: AsyncStream<StreamChunk>.Continuation
    ) {
        for (_, acc) in accumulators.sorted(by: { $0.key < $1.key }) {
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

    private func buildOpenAIRequest<T: Encodable>(body: T) throws -> URLRequest {
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
            print("[LLMService] POST \(endpoint) body=\(bodyStr.prefix(500))...")
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
