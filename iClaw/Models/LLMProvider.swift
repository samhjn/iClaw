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

/// Thinking / reasoning intensity level.
///
/// Maps to provider-specific parameters:
/// - Anthropic: `thinking.budget_tokens`
/// - OpenAI: `reasoning_effort`
enum ThinkingLevel: String, Codable, CaseIterable, Comparable {
    case off = "off"
    case low = "low"
    case medium = "medium"
    case high = "high"

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// Anthropic `budget_tokens` for this level.
    var anthropicBudgetTokens: Int {
        switch self {
        case .off: return 0
        case .low: return 2048
        case .medium: return 10240
        case .high: return 32768
        }
    }

    /// OpenAI `reasoning_effort` value, or nil when thinking is off.
    var openAIReasoningEffort: String? {
        switch self {
        case .off: return nil
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        }
    }

    var isEnabled: Bool { self != .off }

    // MARK: Comparable

    private var sortOrder: Int {
        switch self {
        case .off: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }

    static func < (lhs: ThinkingLevel, rhs: ThinkingLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// Image generation mode for a model.
enum ImageGenMode: String, Codable, CaseIterable {
    /// Model does not support image generation.
    case none
    /// Generates images inline via chat completions with `modalities: ["image","text"]` (e.g. Gemini Image).
    case chatInline
    /// Generates images via dedicated `/images/generations` endpoint (e.g. DALL-E, FLUX, SD3).
    case dedicatedAPI

    var displayName: String {
        switch self {
        case .none: return L10n.Provider.imageGenModeNone
        case .chatInline: return L10n.Provider.imageGenModeChatInline
        case .dedicatedAPI: return L10n.Provider.imageGenModeDedicatedAPI
        }
    }
}

/// Video generation API adaptation mode for a model.
///
/// All video generation APIs are asynchronous (submit → poll → download).
/// This enum specifies which API protocol/format to use, allowing users to
/// manually override auto-detection when using proxies or relay services.
enum VideoGenMode: String, Codable, CaseIterable {
    /// Model does not support video generation.
    case none
    /// Auto-detect from endpoint hostname and model name.
    case auto
    /// OpenAI-compatible REST pattern (Sora, Runway, Luma AI, etc.).
    case openAI
    /// Google Gemini API `predictLongRunning` pattern (Veo 2/3/3.1).
    case googleVeo
    /// Alibaba Cloud DashScope pattern (Tongyi Wan series).
    case dashScope
    /// Kuaishou Kling API pattern.
    case kling

    var displayName: String {
        switch self {
        case .none: return L10n.Provider.videoGenModeNone
        case .auto: return L10n.Provider.videoGenModeAuto
        case .openAI: return L10n.Provider.videoGenModeOpenAI
        case .googleVeo: return L10n.Provider.videoGenModeGoogleVeo
        case .dashScope: return L10n.Provider.videoGenModeDashScope
        case .kling: return L10n.Provider.videoGenModeKling
        }
    }
}

/// Per-model capability flags and parameter overrides.
struct ModelCapabilities: Codable, Equatable {
    var supportsVision: Bool = false
    var supportsToolUse: Bool = true
    var imageGenerationMode: ImageGenMode = .none
    /// Whether this model supports video input (e.g. Gemini 2+, Qwen-VL).
    var supportsVideoInput: Bool = false
    /// Video generation API mode. `.none` = not supported, `.auto` = detect from endpoint/model.
    var videoGenerationMode: VideoGenMode = .none
    /// Legacy flag kept for backward compatibility with existing persisted data.
    /// New code should use `thinkingLevel` instead.
    var supportsReasoning: Bool = false
    /// The default thinking level for this model. `.off` means no thinking support.
    var thinkingLevel: ThinkingLevel = .off
    /// Per-model max output tokens override. `nil` = use provider default.
    var maxTokens: Int? = nil
    /// Per-model temperature override. `nil` = use provider default.
    var temperature: Double? = nil

    /// Backward-compatible computed property.
    var supportsImageGeneration: Bool {
        get { imageGenerationMode != .none }
        set { imageGenerationMode = newValue ? .chatInline : .none }
    }

    /// Whether this model supports video generation.
    var supportsVideoGeneration: Bool { videoGenerationMode != .none }

    static let `default` = ModelCapabilities()

    enum CodingKeys: String, CodingKey {
        case supportsVision, supportsToolUse, imageGenerationMode, supportsVideoInput
        case videoGenerationMode
        case supportsReasoning, thinkingLevel
        case maxTokens, temperature
        case _legacyImageGen = "supportsImageGeneration"
    }

    init(supportsVision: Bool = false, supportsToolUse: Bool = true,
         imageGenerationMode: ImageGenMode = .none, supportsVideoInput: Bool = false,
         videoGenerationMode: VideoGenMode = .none,
         supportsReasoning: Bool = false, thinkingLevel: ThinkingLevel = .off,
         maxTokens: Int? = nil, temperature: Double? = nil) {
        self.supportsVision = supportsVision
        self.supportsToolUse = supportsToolUse
        self.imageGenerationMode = imageGenerationMode
        self.supportsVideoInput = supportsVideoInput
        self.videoGenerationMode = videoGenerationMode
        self.supportsReasoning = supportsReasoning
        self.thinkingLevel = thinkingLevel
        self.maxTokens = maxTokens
        self.temperature = temperature
    }

    /// Legacy init for backward compatibility with callers using the old Bool parameter.
    init(supportsVision: Bool, supportsToolUse: Bool,
         supportsImageGeneration: Bool, supportsReasoning: Bool) {
        self.supportsVision = supportsVision
        self.supportsToolUse = supportsToolUse
        self.imageGenerationMode = supportsImageGeneration ? .chatInline : .none
        self.supportsReasoning = supportsReasoning
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        supportsVision = try c.decodeIfPresent(Bool.self, forKey: .supportsVision) ?? false
        supportsToolUse = try c.decodeIfPresent(Bool.self, forKey: .supportsToolUse) ?? true
        supportsVideoInput = try c.decodeIfPresent(Bool.self, forKey: .supportsVideoInput) ?? false
        videoGenerationMode = try c.decodeIfPresent(VideoGenMode.self, forKey: .videoGenerationMode) ?? .none
        supportsReasoning = try c.decodeIfPresent(Bool.self, forKey: .supportsReasoning) ?? false
        // ImageGenMode: try new enum first, fall back to legacy bool
        if let mode = try? c.decodeIfPresent(ImageGenMode.self, forKey: .imageGenerationMode) {
            imageGenerationMode = mode
        } else if let legacy = try? c.decodeIfPresent(Bool.self, forKey: ._legacyImageGen), legacy {
            imageGenerationMode = .chatInline
        } else {
            imageGenerationMode = .none
        }
        // ThinkingLevel: migration from supportsReasoning bool
        if let level = try c.decodeIfPresent(ThinkingLevel.self, forKey: .thinkingLevel) {
            thinkingLevel = level
        } else {
            thinkingLevel = supportsReasoning ? .medium : .off
        }
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens)
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(supportsVision, forKey: .supportsVision)
        try container.encode(supportsToolUse, forKey: .supportsToolUse)
        try container.encode(imageGenerationMode, forKey: .imageGenerationMode)
        try container.encode(supportsVideoInput, forKey: .supportsVideoInput)
        try container.encode(videoGenerationMode, forKey: .videoGenerationMode)
        try container.encode(supportsReasoning, forKey: .supportsReasoning)
        try container.encode(thinkingLevel, forKey: .thinkingLevel)
        try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
        try container.encodeIfPresent(temperature, forKey: .temperature)
    }

    /// Infer default capabilities from a model name.
    ///
    /// Vision: GPT-4+, Claude 3.5+, Qwen-VL/Omni/3.5+, Gemini 1.5+
    /// Video: Gemini 1.5+, Qwen-VL/Omni, InternVL, Pixtral, LLaVA-Video
    /// Image generation (chatInline): gemini-*-image-* models
    /// Image generation (dedicatedAPI): dall-e-*, gpt-image-*, flux-*, sd3-*, sdxl-*
    static func inferred(from modelName: String) -> ModelCapabilities {
        let base = modelName.split(separator: "/").last.map { String($0).lowercased() }
            ?? modelName.lowercased()

        // Gemini image models: chatInline mode (no tool use)
        if base.contains("gemini") && base.contains("image") {
            return ModelCapabilities(
                supportsVision: true,
                supportsToolUse: false,
                imageGenerationMode: .chatInline,
                supportsVideoInput: true,
                supportsReasoning: false
            )
        }

        // Dedicated image generation models
        if inferDedicatedImageGen(base) {
            return ModelCapabilities(
                supportsVision: false,
                supportsToolUse: false,
                imageGenerationMode: .dedicatedAPI,
                supportsReasoning: false
            )
        }

        // Dedicated video generation models
        if inferVideoGeneration(base) {
            return ModelCapabilities(
                supportsVision: false,
                supportsToolUse: false,
                videoGenerationMode: .auto,
                supportsReasoning: false
            )
        }

        let videoCapable = inferVideoInput(base)

        // Video capability implies vision capability
        if videoCapable {
            return ModelCapabilities(
                supportsVision: true,
                supportsToolUse: true,
                imageGenerationMode: .none,
                supportsVideoInput: true,
                supportsReasoning: false
            )
        }

        if inferVision(base) {
            return ModelCapabilities(
                supportsVision: true,
                supportsToolUse: true,
                imageGenerationMode: .none,
                supportsVideoInput: false,
                supportsReasoning: false
            )
        }

        return .default
    }

    /// Detect dedicated video generation models.
    ///
    /// Sora: sora-*
    /// Veo: veo-*
    /// Wan (Tongyi): wan*-t2v*, wan*-i2v*, wan*-r2v*, wan*-kf2v*, wan*-s2v*, wan*-vace*
    /// Runway: runway-*, gen-3*, gen-4*
    /// Luma: luma-*, dream-machine*
    /// Kling: kling-*
    /// MiniMax/Hailuo: minimax-video*, hailuo*
    private static func inferVideoGeneration(_ name: String) -> Bool {
        // OpenAI Sora
        if name.hasPrefix("sora") { return true }
        // Google Veo
        if name.hasPrefix("veo-") || name.hasPrefix("veo_") { return true }
        // Alibaba Wan series (wan2.6-t2v, wan2.7-t2v-turbo, wan2.6-i2v-flash, etc.)
        if name.hasPrefix("wan") && (name.contains("-t2v") || name.contains("-i2v")
            || name.contains("-r2v") || name.contains("-kf2v")
            || name.contains("-s2v") || name.contains("-vace")) { return true }
        // Runway
        if name.hasPrefix("runway-") || name.hasPrefix("gen-3") || name.hasPrefix("gen-4") { return true }
        // Luma AI
        if name.hasPrefix("luma-") || name.hasPrefix("dream-machine") || name.hasPrefix("ray-") { return true }
        // Kling
        if name.hasPrefix("kling") { return true }
        // MiniMax / Hailuo
        if (name.hasPrefix("minimax") && name.contains("video")) || name.hasPrefix("hailuo") { return true }
        return false
    }

    /// Detect models that use the dedicated /images/generations API.
    private static func inferDedicatedImageGen(_ name: String) -> Bool {
        name.hasPrefix("dall-e")
            || name.hasPrefix("gpt-image")
            || name.hasPrefix("flux")
            || name.hasPrefix("stable-diffusion")
            || name.hasPrefix("sd3")
            || name.hasPrefix("sdxl")
            || name.contains("imagen")
    }

    /// Detect models that support video input.
    /// Gemini 1.5+, Qwen-VL/Omni, InternVL, Pixtral, LLaVA-Video support video natively.
    private static func inferVideoInput(_ name: String) -> Bool {
        // Gemini 1.5+ supports video input
        if name.hasPrefix("gemini-") {
            let rest = name.dropFirst(7)
            if let version = parseLeadingVersion(String(rest)), version >= 1.5 {
                return true
            }
        }
        // Qwen-VL and Qwen-Omni support video
        if name.contains("qwen") && (name.contains("-vl") || name.contains("-omni")) {
            return true
        }
        // InternVL supports video
        if name.contains("internvl") {
            return true
        }
        // Pixtral (Mistral) supports video
        if name.contains("pixtral") {
            return true
        }
        // LLaVA-Video / LLaVA-Next-Video
        if name.contains("llava") && name.contains("video") {
            return true
        }
        return false
    }

    // MARK: - Private inference helpers

    /// Detect vision-only models (no video). Video models are handled separately by `inferVideoInput`.
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

    /// Gemini 1.5 and above
    private static func isGeminiVisionCapable(_ name: String) -> Bool {
        guard name.hasPrefix("gemini-") else { return false }
        let rest = name.dropFirst(7)
        if let version = parseLeadingVersion(String(rest)), version >= 1.5 {
            return true
        }
        return false
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
    var thinkingBudget: Int = 10000
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
            imageGenerationMode: supportsImageGeneration ? .chatInline : .none,
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
        self.thinkingBudget = 10000
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
