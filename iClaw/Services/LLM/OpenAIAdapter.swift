import Foundation

/// OpenAI-compatible API adapter.
///
/// Handles request/response formatting for OpenAI, OpenRouter,
/// and other OpenAI-compatible endpoints.
final class OpenAIAdapter: LLMAPIAdapter, @unchecked Sendable {
    /// Encoder with `.sortedKeys` so request bodies are byte-identical across
    /// runs. Required for prompt-caching providers (DeepSeek, etc.) — Swift
    /// `Dictionary` iteration order is non-deterministic, so without this,
    /// `JSONSchema.properties` and similar dict-backed fields scramble between
    /// requests and defeat the cache.
    private static let stableEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    let context: LLMAdapterContext
    /// Accumulator for streaming tool calls. Reset per stream session.
    private var toolAccum = ToolCallAccumulator()

    init(context: LLMAdapterContext) {
        self.context = context
    }

    // MARK: - Non-streaming

    func buildChatRequest(
        model: String,
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]?,
        maxTokens: Int,
        temperature: Double,
        capabilities: ModelCapabilities,
        thinkingLevel: ThinkingLevel
    ) throws -> URLRequest {
        let modalities: [String]? = capabilities.imageGenerationMode == .chatInline ? ["image", "text"] : nil
        let request = LLMChatRequest(
            model: model,
            messages: messages,
            tools: tools?.isEmpty == true ? nil : tools,
            toolChoice: (tools != nil && tools?.isEmpty == false) ? .auto : nil,
            stream: false,
            maxTokens: maxTokens,
            temperature: temperature,
            modalities: modalities,
            reasoningEffort: thinkingLevel.openAIReasoningEffort
        )

        let bodyData = try Self.stableEncoder.encode(request)
        return try APIRequestBuilder.jsonPOST(
            base: context.baseURL,
            path: "/chat/completions",
            apiKey: context.apiKey,
            style: .openAI,
            body: bodyData
        )
    }

    func parseChatResponse(data: Data) throws -> LLMChatResponse {
        try JSONDecoder().decode(LLMChatResponse.self, from: data)
    }

    // MARK: - Streaming

    func buildStreamRequest(
        model: String,
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]?,
        maxTokens: Int,
        temperature: Double,
        capabilities: ModelCapabilities,
        thinkingLevel: ThinkingLevel
    ) throws -> URLRequest {
        let modalities: [String]? = capabilities.imageGenerationMode == .chatInline ? ["image", "text"] : nil
        let request = LLMChatRequest(
            model: model,
            messages: messages,
            tools: tools?.isEmpty == true ? nil : tools,
            toolChoice: (tools != nil && tools?.isEmpty == false) ? .auto : nil,
            stream: true,
            streamOptions: LLMStreamOptions(includeUsage: true),
            maxTokens: maxTokens,
            temperature: temperature,
            modalities: modalities,
            reasoningEffort: thinkingLevel.openAIReasoningEffort
        )

        let bodyData = try Self.stableEncoder.encode(request)
        return try APIRequestBuilder.jsonPOST(
            base: context.baseURL,
            path: "/chat/completions",
            apiKey: context.apiKey,
            style: .openAI,
            body: bodyData
        )
    }

    func processStreamEvent(_ event: SSEEvent) -> [StreamChunk] {
        switch event {
        case .message(let data):
            return processOpenAIMessage(data)
        case .done:
            var chunks: [StreamChunk] = []
            for toolCall in toolAccum.flush() {
                chunks.append(.toolCall(toolCall))
            }
            chunks.append(.done)
            return chunks
        }
    }

    private func processOpenAIMessage(_ data: String) -> [StreamChunk] {
        guard let jsonData = data.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(LLMChatResponse.self, from: jsonData)
        else { return [] }

        var chunks: [StreamChunk] = []

        if let delta = chunk.choices.first?.delta {
            if let reasoning = delta.reasoningContent {
                chunks.append(.thinking(reasoning))
            }
            if let content = delta.content {
                chunks.append(.content(content))
            }
            if let deltaToolCalls = delta.toolCalls {
                for dtc in deltaToolCalls {
                    toolAccum.accumulate(
                        index: dtc.index,
                        id: dtc.id,
                        name: dtc.function?.name,
                        arguments: dtc.function?.arguments
                    )
                }
            }
        }

        if let usage = chunk.usage,
           (usage.promptTokens != nil || usage.completionTokens != nil || usage.totalTokens != nil) {
            chunks.append(.usage(usage))
        }

        if let reason = chunk.choices.first?.finishReason,
           isToolCallFinishReason(reason),
           toolAccum.hasPending {
            for toolCall in toolAccum.flush() {
                chunks.append(.toolCall(toolCall))
            }
        }

        return chunks
    }

    private func isToolCallFinishReason(_ reason: String) -> Bool {
        reason == "tool_calls" || reason == "tool_call" || reason == "function_call"
    }

    // MARK: - Models

    func buildModelsRequest() throws -> URLRequest {
        try APIRequestBuilder.jsonGET(
            base: context.baseURL,
            path: "/models",
            apiKey: context.apiKey,
            style: .openAI
        )
    }

    func parseModelsResponse(data: Data) throws -> [String] {
        let response = try JSONDecoder().decode(ModelsListResponse.self, from: data)
        return response.data.map(\.id).sorted()
    }
}
