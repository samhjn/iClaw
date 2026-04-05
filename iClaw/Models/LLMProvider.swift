import Foundation
import SwiftData

/// API communication style.
enum APIStyle: String, Codable, CaseIterable {
    case openAI = "openai"
    case anthropic = "anthropic"

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        }
    }
}

/// Per-model capability flags.
struct ModelCapabilities: Codable, Equatable {
    var supportsVision: Bool = false
    var supportsToolUse: Bool = true
    var supportsImageGeneration: Bool = false
    var supportsReasoning: Bool = false

    static let `default` = ModelCapabilities()

    /// Infer default capabilities from a model name.
    ///
    /// Vision: GPT-4+, Claude 3.5+, Qwen-VL/Omni/3.5+, Gemini 2+
    /// Image generation (no tool use): gemini-*-image-* models
    static func inferred(from modelName: String) -> ModelCapabilities {
        let base = modelName.split(separator: "/").last.map { String($0).lowercased() }
            ?? modelName.lowercased()

        if base.contains("gemini") && base.contains("image") {
            return ModelCapabilities(
                supportsVision: true,
                supportsToolUse: false,
                supportsImageGeneration: true,
                supportsReasoning: false
            )
        }

        if inferVision(base) {
            return ModelCapabilities(
                supportsVision: true,
                supportsToolUse: true,
                supportsImageGeneration: false,
                supportsReasoning: false
            )
        }

        return .default
    }

    // MARK: - Private inference helpers

    private static func inferVision(_ name: String) -> Bool {
        isGPTVisionCapable(name)
            || isClaudeVisionCapable(name)
            || isQwenVisionCapable(name)
            || isGeminiVisionCapable(name)
    }

    /// GPT-4.x and above
    private static func isGPTVisionCapable(_ name: String) -> Bool {
        guard name.hasPrefix("gpt-") else { return false }
        let rest = name.dropFirst(4)
        guard let digit = rest.first, let num = digit.wholeNumberValue else { return false }
        return num >= 4
    }

    /// Claude 3.5 and above
    private static func isClaudeVisionCapable(_ name: String) -> Bool {
        guard name.hasPrefix("claude") else { return false }

        // New naming: claude-{variant}-{version} (e.g. claude-sonnet-4-6, claude-opus-4)
        for variant in ["sonnet", "opus", "haiku"] {
            let prefix = "claude-\(variant)-"
            if name.hasPrefix(prefix) {
                let rest = name.dropFirst(prefix.count)
                if let digit = rest.first, let num = digit.wholeNumberValue, num >= 4 {
                    return true
                }
            }
        }

        // Old naming: claude-{version}-{variant} (e.g. claude-3.5-sonnet, claude-3-5-sonnet)
        guard name.hasPrefix("claude-") else { return false }
        let rest = name.dropFirst(7) // "claude-"
        guard let digit = rest.first, let num = digit.wholeNumberValue else { return false }
        if num > 3 { return true }
        if num == 3 {
            let afterDigit = rest.dropFirst(1)
            if afterDigit.hasPrefix(".5") || afterDigit.hasPrefix("-5") { return true }
        }
        return false
    }

    /// Qwen-VL, Qwen-Omni, or Qwen 3.5+
    private static func isQwenVisionCapable(_ name: String) -> Bool {
        guard name.contains("qwen") else { return false }
        if name.contains("-vl") || name.contains("-omni") { return true }

        // Version directly after "qwen" (no dash): qwen3.5, qwen4, etc.
        guard let range = name.range(of: "qwen") else { return false }
        let afterQwen = name[range.upperBound...]
        guard let first = afterQwen.first, first.isNumber else { return false }
        if let version = parseLeadingVersion(String(afterQwen)), version >= 3.5 {
            return true
        }
        return false
    }

    /// Gemini 2 and above (non-image variants handled here)
    private static func isGeminiVisionCapable(_ name: String) -> Bool {
        guard name.hasPrefix("gemini-") else { return false }
        let rest = name.dropFirst(7)
        guard let digit = rest.first, let num = digit.wholeNumberValue else { return false }
        return num >= 2
    }

    private static func parseLeadingVersion(_ str: String) -> Double? {
        var numStr = ""
        var hasDot = false
        for ch in str {
            if ch.isNumber {
                numStr.append(ch)
            } else if ch == "." && !hasDot {
                hasDot = true
                numStr.append(ch)
            } else {
                break
            }
        }
        return numStr.isEmpty ? nil : Double(numStr)
    }
}

@Model
final class LLMProvider {
    var id: UUID
    var name: String
    var endpoint: String
    var apiKey: String
    var modelName: String
    var isDefault: Bool
    var maxTokens: Int
    var temperature: Double
    var createdAt: Date

    /// All model names enabled for this provider (in addition to modelName).
    /// Stored as comma-separated string for SwiftData compatibility.
    var enabledModelsRaw: String?

    /// Cached model list fetched from the API.
    /// Stored as comma-separated string.
    var cachedModelListRaw: String?

    /// When the model list was last fetched.
    var cachedModelListDate: Date?

    /// Legacy provider-level flags (kept for backward compatibility with existing data).
    var supportsVision: Bool = false
    var supportsToolUse: Bool = true
    var supportsImageGeneration: Bool = false

    /// API communication style: "openai" or "anthropic".
    var apiStyleRaw: String = "openai"

    /// Per-model capabilities, stored as JSON: {"model-name": {...}}
    var modelCapabilitiesJSON: String?

    // MARK: - Computed

    var apiStyle: APIStyle {
        get { APIStyle(rawValue: apiStyleRaw) ?? .openAI }
        set { apiStyleRaw = newValue.rawValue }
    }

    var enabledModels: [String] {
        get {
            var models = Set<String>()
            models.insert(modelName)
            if let raw = enabledModelsRaw, !raw.isEmpty {
                raw.components(separatedBy: "|||").forEach { models.insert($0) }
            }
            return Array(models).sorted()
        }
        set {
            let filtered = newValue.filter { $0 != modelName }
            enabledModelsRaw = filtered.isEmpty ? nil : filtered.joined(separator: "|||")
        }
    }

    var cachedModelList: [String] {
        get {
            guard let raw = cachedModelListRaw, !raw.isEmpty else { return [] }
            return raw.components(separatedBy: "|||")
        }
        set {
            cachedModelListRaw = newValue.isEmpty ? nil : newValue.joined(separator: "|||")
        }
    }

    /// Per-model capabilities dictionary.
    var allModelCapabilities: [String: ModelCapabilities] {
        get {
            guard let json = modelCapabilitiesJSON,
                  let data = json.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: ModelCapabilities].self, from: data)
            else { return [:] }
            return dict
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8)
            else { modelCapabilitiesJSON = nil; return }
            modelCapabilitiesJSON = json
        }
    }

    /// Get capabilities for a specific model, with provider-level fallback.
    /// Reads directly from the raw JSON to avoid computed property issues with SwiftData.
    func capabilities(for model: String) -> ModelCapabilities {
        if let json = modelCapabilitiesJSON,
           let data = json.data(using: .utf8),
           let dict = try? JSONDecoder().decode([String: ModelCapabilities].self, from: data),
           let caps = dict[model] {
            return caps
        }
        return ModelCapabilities(
            supportsVision: supportsVision,
            supportsToolUse: supportsToolUse,
            supportsImageGeneration: supportsImageGeneration,
            supportsReasoning: false
        )
    }

    /// Set capabilities for a specific model.
    /// Writes directly to the raw JSON property for reliable SwiftData persistence.
    func setCapabilities(_ caps: ModelCapabilities, for model: String) {
        var dict: [String: ModelCapabilities] = [:]
        if let json = modelCapabilitiesJSON,
           let data = json.data(using: .utf8),
           let existing = try? JSONDecoder().decode([String: ModelCapabilities].self, from: data) {
            dict = existing
        }
        dict[model] = caps
        if let data = try? JSONEncoder().encode(dict),
           let json = String(data: data, encoding: .utf8) {
            modelCapabilitiesJSON = json
        }
    }

    init(
        name: String,
        endpoint: String = "https://api.openai.com/v1",
        apiKey: String = "",
        modelName: String = "gpt-5.4",
        isDefault: Bool = false,
        maxTokens: Int = 4096,
        temperature: Double = 0.7
    ) {
        self.id = UUID()
        self.name = name
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.modelName = modelName
        self.isDefault = isDefault
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.createdAt = Date()
        self.enabledModelsRaw = nil
        self.cachedModelListRaw = nil
        self.cachedModelListDate = nil
        self.supportsVision = false
        self.apiStyleRaw = "openai"
        self.modelCapabilitiesJSON = nil
    }
}
