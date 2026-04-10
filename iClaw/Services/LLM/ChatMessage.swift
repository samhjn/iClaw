import Foundation

// MARK: - Multimodal content parts

enum ContentPart: Codable {
    case text(String)
    case imageURL(url: String, detail: String?)

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageUrl = "image_url"
    }

    struct ImageURLPayload: Codable {
        let url: String
        var detail: String?
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL(let url, let detail):
            try container.encode("image_url", forKey: .type)
            try container.encode(ImageURLPayload(url: url, detail: detail), forKey: .imageUrl)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "image_url":
            let payload = try container.decode(ImageURLPayload.self, forKey: .imageUrl)
            self = .imageURL(url: payload.url, detail: payload.detail)
        default:
            let text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            self = .text(text)
        }
    }
}

// MARK: - OpenAI-compatible request/response types

struct LLMChatMessage: Codable {
    let role: String
    var content: String?
    var contentParts: [ContentPart]?
    var toolCalls: [LLMToolCall]?
    var toolCallId: String?
    var name: String?

    enum CodingKeys: String, CodingKey {
        case role, content, name, images
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)

        if let parts = contentParts, !parts.isEmpty {
            try container.encode(parts, forKey: .content)
        } else if role == "assistant" && toolCalls != nil {
            try container.encode(content, forKey: .content)
        } else if let content = content {
            try container.encode(content, forKey: .content)
        }

        if let toolCalls = toolCalls, !toolCalls.isEmpty {
            try container.encode(toolCalls, forKey: .toolCalls)
        }
        if let toolCallId = toolCallId {
            try container.encode(toolCallId, forKey: .toolCallId)
        }
        if let name = name {
            try container.encode(name, forKey: .name)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        toolCalls = try container.decodeIfPresent([LLMToolCall].self, forKey: .toolCalls)
        toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
        name = try container.decodeIfPresent(String.self, forKey: .name)

        var contentStr: String?
        if let str = try? container.decodeIfPresent(String.self, forKey: .content) {
            contentStr = str
            contentParts = nil
        } else if let parts = try? container.decodeIfPresent([ContentPart].self, forKey: .content) {
            contentParts = parts
            contentStr = parts.map { part in
                switch part {
                case .text(let t): return t
                case .imageURL(let url, _): return "\n![image](\(url))\n"
                }
            }.joined()
        } else {
            contentStr = nil
            contentParts = nil
        }

        // OpenRouter image generation: images in a separate field
        if let images = try? container.decodeIfPresent([ContentPart].self, forKey: .images) {
            let imageMarkdown = images.compactMap { part -> String? in
                if case .imageURL(let url, _) = part { return "\n![image](\(url))\n" }
                return nil
            }.joined()
            if !imageMarkdown.isEmpty {
                contentStr = (contentStr ?? "") + imageMarkdown
            }
        }

        content = contentStr
    }

    init(role: String, content: String? = nil, contentParts: [ContentPart]? = nil,
         toolCalls: [LLMToolCall]? = nil, toolCallId: String? = nil, name: String? = nil) {
        self.role = role
        self.content = content
        self.contentParts = contentParts
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.name = name
    }

    static func system(_ content: String) -> LLMChatMessage {
        LLMChatMessage(role: "system", content: content)
    }

    static func user(_ content: String) -> LLMChatMessage {
        LLMChatMessage(role: "user", content: content)
    }

    static func userWithImages(_ text: String, images: [ImageAttachment]) -> LLMChatMessage {
        var parts: [ContentPart] = [.text(text)]
        for img in images {
            parts.append(.imageURL(url: img.base64DataURI, detail: "auto"))
        }
        return LLMChatMessage(role: "user", content: text, contentParts: parts)
    }

    static func assistant(_ content: String?, toolCalls: [LLMToolCall]? = nil) -> LLMChatMessage {
        LLMChatMessage(role: "assistant", content: content, toolCalls: toolCalls)
    }

    static func tool(content: String, toolCallId: String, name: String? = nil) -> LLMChatMessage {
        LLMChatMessage(role: "tool", content: content, toolCallId: toolCallId, name: name)
    }

}

struct LLMToolCall: Codable, Identifiable {
    let id: String
    var type: String = "function"
    var function: LLMFunctionCall

    struct LLMFunctionCall: Codable {
        var name: String
        var arguments: String
    }

    init(id: String, name: String, arguments: String) {
        self.id = id
        self.type = "function"
        self.function = LLMFunctionCall(name: name, arguments: arguments)
    }
}

struct LLMStreamOptions: Codable {
    var includeUsage: Bool = true

    enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }
}

struct LLMChatRequest: Codable {
    let model: String
    let messages: [LLMChatMessage]
    var tools: [LLMToolDefinition]?
    var toolChoice: LLMToolChoice?
    var stream: Bool?
    var streamOptions: LLMStreamOptions?
    var maxTokens: Int?
    var temperature: Double?
    var modalities: [String]?
    /// OpenAI reasoning_effort parameter for o-series / reasoning models.
    var reasoningEffort: String?

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, stream, temperature, modalities
        case toolChoice = "tool_choice"
        case streamOptions = "stream_options"
        case maxTokens = "max_tokens"
        case reasoningEffort = "reasoning_effort"
    }
}

enum LLMToolChoice: Codable {
    case auto
    case none
    case required
    case function(name: String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto: try container.encode("auto")
        case .none: try container.encode("none")
        case .required: try container.encode("required")
        case .function(let name):
            let value = ToolChoiceFunction(type: "function", function: ToolChoiceFunctionName(name: name))
            try container.encode(value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            switch str {
            case "auto": self = .auto
            case "none": self = .none
            case "required": self = .required
            default: self = .auto
            }
        } else {
            self = .auto
        }
    }
}

private struct ToolChoiceFunction: Codable {
    let type: String
    let function: ToolChoiceFunctionName
}

private struct ToolChoiceFunctionName: Codable {
    let name: String
}

struct LLMToolDefinition: Codable {
    let type: String
    let function: LLMFunctionDefinition

    init(function: LLMFunctionDefinition) {
        self.type = "function"
        self.function = function
    }
}

struct LLMFunctionDefinition: Codable {
    let name: String
    let description: String
    let parameters: JSONSchema

    init(name: String, description: String, parameters: JSONSchema) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

struct JSONSchema: Codable {
    let type: String
    var properties: [String: JSONSchemaProperty]?
    var required: [String]?
    var additionalProperties: Bool?

    enum CodingKeys: String, CodingKey {
        case type, properties, required
        case additionalProperties = "additionalProperties"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        // Always encode properties (as empty {} if nil) for maximum API compatibility
        try container.encode(properties ?? [:], forKey: .properties)
        if let required = required, !required.isEmpty {
            try container.encode(required, forKey: .required)
        }
        if let ap = additionalProperties {
            try container.encode(ap, forKey: .additionalProperties)
        }
    }

    init(
        type: String = "object",
        properties: [String: JSONSchemaProperty]? = nil,
        required: [String]? = nil
    ) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

final class JSONSchemaProperty: Codable {
    let type: String
    var description: String?
    var enumValues: [String]?
    var items: JSONSchemaProperty?

    enum CodingKeys: String, CodingKey {
        case type, description, items
        case enumValues = "enum"
    }

    init(type: String, description: String? = nil, enumValues: [String]? = nil, items: JSONSchemaProperty? = nil) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
        self.items = items
    }
}

// MARK: - Response types

struct LLMChatResponse: Codable {
    let id: String?
    let choices: [LLMChoice]
    let usage: LLMUsage?
}

struct LLMChoice: Codable {
    let index: Int
    let message: LLMChatMessage?
    let delta: LLMDelta?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, message, delta
        case finishReason = "finish_reason"
    }
}

struct LLMDelta: Codable {
    var role: String?
    var content: String?
    var reasoningContent: String?
    var toolCalls: [LLMDeltaToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content, images, reasoning
        case reasoningContent = "reasoning_content"
        case toolCalls = "tool_calls"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(reasoningContent, forKey: .reasoningContent)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        toolCalls = try container.decodeIfPresent([LLMDeltaToolCall].self, forKey: .toolCalls)

        // Parse reasoning from multiple possible fields
        reasoningContent = try container.decodeIfPresent(String.self, forKey: .reasoningContent)
            ?? container.decodeIfPresent(String.self, forKey: .reasoning)

        var contentStr: String?
        if let str = try? container.decodeIfPresent(String.self, forKey: .content) {
            contentStr = str
        } else if let parts = try? container.decodeIfPresent([ContentPart].self, forKey: .content) {
            contentStr = parts.map { part in
                switch part {
                case .text(let t): return t
                case .imageURL(let url, _): return "\n![image](\(url))\n"
                }
            }.joined()
        }

        if let images = try? container.decodeIfPresent([ContentPart].self, forKey: .images) {
            let imageMarkdown = images.compactMap { part -> String? in
                if case .imageURL(let url, _) = part { return "\n![image](\(url))\n" }
                return nil
            }.joined()
            if !imageMarkdown.isEmpty {
                contentStr = (contentStr ?? "") + imageMarkdown
            }
        }

        content = contentStr
    }
}

struct LLMDeltaToolCall: Codable {
    let index: Int
    var id: String?
    var type: String?
    var function: LLMDeltaFunction?
}

struct LLMDeltaFunction: Codable {
    var name: String?
    var arguments: String?
}

struct LLMUsage: Codable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Anthropic API types

struct AnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    var system: [AnthropicSystemBlock]?
    let messages: [AnthropicMessage]
    var tools: [AnthropicTool]?
    var stream: Bool?
    var temperature: Double?
    var thinking: AnthropicThinking?

    enum CodingKeys: String, CodingKey {
        case model, system, messages, tools, stream, temperature, thinking
        case maxTokens = "max_tokens"
    }
}

struct AnthropicSystemBlock: Encodable {
    let type: String
    let text: String
}

struct AnthropicThinking: Encodable {
    let type: String
    let budgetTokens: Int

    enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens = "budget_tokens"
    }

    static func enabled(budget: Int) -> AnthropicThinking {
        AnthropicThinking(type: "enabled", budgetTokens: budget)
    }
}

struct AnthropicMessage: Encodable {
    let role: String
    let content: [AnthropicContentBlock]
}

enum AnthropicContentBlock: Encodable {
    case text(String)
    case image(mediaType: String, data: String)
    case toolUse(id: String, name: String, input: String)
    case toolResult(toolUseId: String, content: String)
    case toolResultRich(toolUseId: String, blocks: [AnthropicToolResultBlock])

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let mediaType, let data):
            try container.encode("image", forKey: .type)
            try container.encode(
                ImageSource(type: "base64", mediaType: mediaType, data: data),
                forKey: .source
            )
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            if let data = input.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) {
                try container.encode(AnyCodable(obj), forKey: .input)
            } else {
                try container.encode([String: String](), forKey: .input)
            }
        case .toolResult(let toolUseId, let content):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseId, forKey: .toolUseId)
            try container.encode(content, forKey: .content)
        case .toolResultRich(let toolUseId, let blocks):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseId, forKey: .toolUseId)
            try container.encode(blocks, forKey: .content)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, text, source, id, name, input, content
        case toolUseId = "tool_use_id"
    }

    struct ImageSource: Encodable {
        let type: String
        let mediaType: String
        let data: String

        enum CodingKeys: String, CodingKey {
            case type, data
            case mediaType = "media_type"
        }
    }
}

/// Content blocks inside an Anthropic `tool_result` (text or image).
enum AnthropicToolResultBlock: Encodable {
    case text(String)
    case image(mediaType: String, data: String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let mediaType, let data):
            try container.encode("image", forKey: .type)
            try container.encode(
                AnthropicContentBlock.ImageSource(type: "base64", mediaType: mediaType, data: data),
                forKey: .source
            )
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, text, source
    }
}

struct AnthropicTool: Encodable {
    let name: String
    let description: String
    let inputSchema: JSONSchema

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

/// Type-erased Codable wrapper for arbitrary JSON values.
struct AnyCodable: Encodable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { AnyCodable($0) })
        } else if let array = value as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let str = value as? String {
            try container.encode(str)
        } else if let num = value as? Double {
            try container.encode(num)
        } else if let num = value as? Int {
            try container.encode(num)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if value is NSNull {
            try container.encodeNil()
        } else {
            try container.encodeNil()
        }
    }
}

// MARK: - Anthropic stream response types

struct AnthropicStreamEvent: Decodable {
    let type: String
    var message: AnthropicStreamMessage?
    var index: Int?
    var contentBlock: AnthropicStreamContentBlock?
    var delta: AnthropicStreamDelta?
    var usage: AnthropicUsage?

    enum CodingKeys: String, CodingKey {
        case type, message, index, delta, usage
        case contentBlock = "content_block"
    }
}

struct AnthropicStreamMessage: Decodable {
    let id: String?
    let role: String?
    let model: String?
    let usage: AnthropicUsage?
}

struct AnthropicStreamContentBlock: Decodable {
    let type: String
    var text: String?
    var thinking: String?
    var id: String?
    var name: String?
}

struct AnthropicStreamDelta: Decodable {
    let type: String
    var text: String?
    var thinking: String?
    var partialJson: String?
    var stopReason: String?

    enum CodingKeys: String, CodingKey {
        case type, text, thinking
        case partialJson = "partial_json"
        case stopReason = "stop_reason"
    }
}

struct AnthropicUsage: Decodable {
    var inputTokens: Int?
    var outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

/// Non-streaming Anthropic response.
struct AnthropicResponse: Decodable {
    let id: String?
    let type: String?
    let role: String?
    let content: [AnthropicResponseBlock]
    let model: String?
    let stopReason: String?
    let usage: AnthropicUsage?

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, model, usage
        case stopReason = "stop_reason"
    }
}

struct AnthropicResponseBlock: Decodable {
    let type: String
    var text: String?
    var thinking: String?
    var id: String?
    var name: String?
    var input: AnyCodableDecoder?
}

/// Type-erased Decodable wrapper.
struct AnyCodableDecoder: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodableDecoder].self) {
            value = dict.mapValues(\.value)
        } else if let array = try? container.decode([AnyCodableDecoder].self) {
            value = array.map(\.value)
        } else if let str = try? container.decode(String.self) {
            value = str
        } else if let num = try? container.decode(Double.self) {
            value = num
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }

    var jsonString: String {
        if let data = try? JSONSerialization.data(withJSONObject: value),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}
