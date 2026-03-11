import Foundation

// MARK: - OpenAI-compatible request/response types

struct LLMChatMessage: Codable {
    let role: String
    var content: String?
    var toolCalls: [LLMToolCall]?
    var toolCallId: String?
    var name: String?

    enum CodingKeys: String, CodingKey {
        case role, content, name
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)

        // For assistant messages with tool_calls, always encode content (even if null).
        // Many APIs require "content": null explicitly.
        if role == "assistant" && toolCalls != nil {
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

    static func system(_ content: String) -> LLMChatMessage {
        LLMChatMessage(role: "system", content: content)
    }

    static func user(_ content: String) -> LLMChatMessage {
        LLMChatMessage(role: "user", content: content)
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

struct LLMChatRequest: Codable {
    let model: String
    let messages: [LLMChatMessage]
    var tools: [LLMToolDefinition]?
    var toolChoice: LLMToolChoice?
    var stream: Bool?
    var maxTokens: Int?
    var temperature: Double?

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, stream, temperature
        case toolChoice = "tool_choice"
        case maxTokens = "max_tokens"
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
    var toolCalls: [LLMDeltaToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
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
