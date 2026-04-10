import XCTest
import SwiftData
@testable import iClaw

final class LLMProviderTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    @MainActor
    override func setUp() {
        super.setUp()
        let schema = Schema([Agent.self, LLMProvider.self, Session.self, AgentConfig.self,
                             CodeSnippet.self, CronJob.self, InstalledSkill.self, Skill.self,
                             Message.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Init Defaults

    @MainActor
    func testDefaultInit() {
        let provider = LLMProvider(name: "Test Provider")
        XCTAssertEqual(provider.name, "Test Provider")
        XCTAssertEqual(provider.endpoint, "https://api.openai.com/v1")
        XCTAssertEqual(provider.modelName, "gpt-5.4")
        XCTAssertFalse(provider.isDefault)
        XCTAssertEqual(provider.maxTokens, 4096)
        XCTAssertEqual(provider.thinkingBudget, 10000)
        XCTAssertEqual(provider.temperature, 0.7)
        XCTAssertEqual(provider.apiStyle, .openAI)
        XCTAssertTrue(provider.apiKey.isEmpty)
    }

    @MainActor
    func testCustomInit() {
        let provider = LLMProvider(
            name: "Anthropic",
            endpoint: "https://api.anthropic.com/v1",
            apiKey: "sk-ant-xxx",
            modelName: "claude-3-opus",
            isDefault: true,
            maxTokens: 8192,
            temperature: 0.5
        )
        XCTAssertEqual(provider.name, "Anthropic")
        XCTAssertEqual(provider.endpoint, "https://api.anthropic.com/v1")
        XCTAssertEqual(provider.apiKey, "sk-ant-xxx")
        XCTAssertEqual(provider.modelName, "claude-3-opus")
        XCTAssertTrue(provider.isDefault)
        XCTAssertEqual(provider.maxTokens, 8192)
        XCTAssertEqual(provider.temperature, 0.5)
    }

    // MARK: - API Style

    @MainActor
    func testAPIStyleOpenAI() {
        let provider = LLMProvider(name: "OpenAI")
        XCTAssertEqual(provider.apiStyle, .openAI)
        XCTAssertEqual(provider.apiStyleRaw, "openai")
    }

    @MainActor
    func testAPIStyleAnthropic() {
        let provider = LLMProvider(name: "Anthropic")
        provider.apiStyle = .anthropic
        XCTAssertEqual(provider.apiStyle, .anthropic)
        XCTAssertEqual(provider.apiStyleRaw, "anthropic")
    }

    @MainActor
    func testAPIStyleDisplayNames() {
        XCTAssertEqual(APIStyle.openAI.displayName, "OpenAI")
        XCTAssertEqual(APIStyle.anthropic.displayName, "Anthropic")
    }

    @MainActor
    func testAPIStyleCodable() throws {
        for style in APIStyle.allCases {
            let data = try JSONEncoder().encode(style)
            let decoded = try JSONDecoder().decode(APIStyle.self, from: data)
            XCTAssertEqual(decoded, style)
        }
    }

    // MARK: - Model Capabilities

    @MainActor
    func testDefaultCapabilities() {
        let caps = ModelCapabilities.default
        XCTAssertFalse(caps.supportsVision)
        XCTAssertTrue(caps.supportsToolUse)
        XCTAssertFalse(caps.supportsImageGeneration)
        XCTAssertFalse(caps.supportsReasoning)
    }

    @MainActor
    func testCapabilitiesFallbackToProviderLevel() {
        let provider = LLMProvider(name: "Test")
        provider.supportsVision = true
        provider.supportsToolUse = true

        let caps = provider.capabilities(for: "some-model")
        XCTAssertTrue(caps.supportsVision)
        XCTAssertTrue(caps.supportsToolUse)
        XCTAssertFalse(caps.supportsImageGeneration)
    }

    @MainActor
    func testSetAndGetModelCapabilities() {
        let provider = LLMProvider(name: "Test")
        let caps = ModelCapabilities(
            supportsVision: true,
            supportsToolUse: true,
            supportsImageGeneration: false,
            supportsReasoning: true
        )
        provider.setCapabilities(caps, for: "claude-3-opus")

        let retrieved = provider.capabilities(for: "claude-3-opus")
        XCTAssertEqual(retrieved, caps)
    }

    @MainActor
    func testModelCapabilitiesMultipleModels() {
        let provider = LLMProvider(name: "Multi")
        let caps1 = ModelCapabilities(supportsVision: true, supportsToolUse: true)
        let caps2 = ModelCapabilities(supportsVision: false, supportsToolUse: false)

        provider.setCapabilities(caps1, for: "model-a")
        provider.setCapabilities(caps2, for: "model-b")

        XCTAssertEqual(provider.capabilities(for: "model-a"), caps1)
        XCTAssertEqual(provider.capabilities(for: "model-b"), caps2)
    }

    @MainActor
    func testModelCapabilitiesOverwrite() {
        let provider = LLMProvider(name: "Test")
        let caps1 = ModelCapabilities(supportsVision: false)
        let caps2 = ModelCapabilities(supportsVision: true)

        provider.setCapabilities(caps1, for: "model-x")
        provider.setCapabilities(caps2, for: "model-x")

        XCTAssertEqual(provider.capabilities(for: "model-x").supportsVision, true)
    }

    @MainActor
    func testModelCapabilitiesCodableRoundTrip() throws {
        let caps = ModelCapabilities(
            supportsVision: true,
            supportsToolUse: false,
            supportsImageGeneration: true,
            supportsReasoning: true
        )
        let data = try JSONEncoder().encode(caps)
        let decoded = try JSONDecoder().decode(ModelCapabilities.self, from: data)
        XCTAssertEqual(decoded, caps)
    }

    // MARK: - Thinking Level

    func testThinkingLevelDefaults() {
        let caps = ModelCapabilities.default
        XCTAssertEqual(caps.thinkingLevel, .off)
        XCTAssertFalse(caps.thinkingLevel.isEnabled)
    }

    func testThinkingLevelExplicitValue() {
        let caps = ModelCapabilities(supportsReasoning: true, thinkingLevel: .high)
        XCTAssertEqual(caps.thinkingLevel, .high)
        XCTAssertTrue(caps.thinkingLevel.isEnabled)
    }

    func testThinkingLevelCodableRoundTrip() throws {
        for level in ThinkingLevel.allCases {
            let caps = ModelCapabilities(thinkingLevel: level)
            let data = try JSONEncoder().encode(caps)
            let decoded = try JSONDecoder().decode(ModelCapabilities.self, from: data)
            XCTAssertEqual(decoded.thinkingLevel, level,
                           "ThinkingLevel.\(level.rawValue) should survive encode/decode")
        }
    }

    func testThinkingLevelMigrationFromLegacyData() throws {
        // Simulate old persisted JSON that has supportsReasoning but no thinkingLevel key
        let legacyJSON = """
        {"supportsVision":false,"supportsToolUse":true,"supportsImageGeneration":false,"supportsReasoning":true}
        """
        let data = legacyJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ModelCapabilities.self, from: data)
        XCTAssertEqual(decoded.thinkingLevel, .medium,
                       "Legacy supportsReasoning=true should migrate to .medium")
        XCTAssertTrue(decoded.supportsReasoning)
    }

    func testThinkingLevelMigrationNoReasoning() throws {
        let legacyJSON = """
        {"supportsVision":true,"supportsToolUse":true,"supportsImageGeneration":false,"supportsReasoning":false}
        """
        let data = legacyJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ModelCapabilities.self, from: data)
        XCTAssertEqual(decoded.thinkingLevel, .off,
                       "Legacy supportsReasoning=false should stay .off")
    }

    func testThinkingLevelComparable() {
        XCTAssertTrue(ThinkingLevel.off < ThinkingLevel.low)
        XCTAssertTrue(ThinkingLevel.low < ThinkingLevel.medium)
        XCTAssertTrue(ThinkingLevel.medium < ThinkingLevel.high)
        XCTAssertFalse(ThinkingLevel.high < ThinkingLevel.off)
    }

    func testThinkingLevelAnthropicBudget() {
        XCTAssertEqual(ThinkingLevel.off.anthropicBudgetTokens, 0)
        XCTAssertEqual(ThinkingLevel.low.anthropicBudgetTokens, 2048)
        XCTAssertEqual(ThinkingLevel.medium.anthropicBudgetTokens, 10240)
        XCTAssertEqual(ThinkingLevel.high.anthropicBudgetTokens, 32768)
    }

    func testThinkingLevelOpenAIReasoningEffort() {
        XCTAssertNil(ThinkingLevel.off.openAIReasoningEffort)
        XCTAssertEqual(ThinkingLevel.low.openAIReasoningEffort, "low")
        XCTAssertEqual(ThinkingLevel.medium.openAIReasoningEffort, "medium")
        XCTAssertEqual(ThinkingLevel.high.openAIReasoningEffort, "high")
    }

    @MainActor
    func testThinkingLevelPerModelPersistence() {
        let provider = LLMProvider(name: "Test")
        let caps = ModelCapabilities(
            supportsVision: true,
            supportsReasoning: true,
            thinkingLevel: .high
        )
        provider.setCapabilities(caps, for: "claude-opus-4-6")

        let retrieved = provider.capabilities(for: "claude-opus-4-6")
        XCTAssertEqual(retrieved.thinkingLevel, .high)
        XCTAssertTrue(retrieved.supportsReasoning)
    }

    // MARK: - Inferred Capabilities

    func testInferredCapabilities_GPTFamily() {
        let cases: [(String, Bool)] = [
            ("gpt-5.4", true),
            ("openai/gpt-5.4", true),
            ("openai/gpt-5.4-nano", true),
            ("openai/gpt-5.3-codex", true),
            ("gpt-4o", true),
            ("gpt-4.1-mini", true),
            ("gpt-3.5-turbo", false),
        ]
        for (model, expectedVision) in cases {
            let caps = ModelCapabilities.inferred(from: model)
            XCTAssertEqual(caps.supportsVision, expectedVision,
                           "\(model): expected vision=\(expectedVision)")
            XCTAssertTrue(caps.supportsToolUse,
                          "\(model): GPT models should support tool use")
            XCTAssertFalse(caps.supportsImageGeneration,
                           "\(model): GPT models should not generate images")
        }
    }

    func testInferredCapabilities_ClaudeFamily() {
        let visionModels = [
            "claude-sonnet-4-6",
            "claude-opus-4-6",
            "anthropic/claude-sonnet-4.6",
            "anthropic/claude-opus-4.6",
            "claude-3.5-sonnet",
            "claude-3-5-sonnet-20241022",
        ]
        for model in visionModels {
            let caps = ModelCapabilities.inferred(from: model)
            XCTAssertTrue(caps.supportsVision,
                          "\(model): expected vision=true")
            XCTAssertTrue(caps.supportsToolUse,
                          "\(model): expected toolUse=true")
            XCTAssertFalse(caps.supportsImageGeneration,
                           "\(model): expected imageGen=false")
        }

        let noVisionModels = [
            "claude-3-opus",
            "claude-3-haiku",
        ]
        for model in noVisionModels {
            let caps = ModelCapabilities.inferred(from: model)
            XCTAssertFalse(caps.supportsVision,
                           "\(model): expected vision=false (below 3.5)")
        }
    }

    func testInferredCapabilities_GeminiVision() {
        let visionModels = [
            "gemini-3.1-pro-preview",
            "google/gemini-3.1-flash-lite-preview",
            "gemini-2.0-flash",
            "gemini-2.5-pro",
        ]
        for model in visionModels {
            let caps = ModelCapabilities.inferred(from: model)
            XCTAssertTrue(caps.supportsVision,
                          "\(model): expected vision=true")
            XCTAssertTrue(caps.supportsToolUse,
                          "\(model): expected toolUse=true")
            XCTAssertFalse(caps.supportsImageGeneration,
                           "\(model): expected imageGen=false")
        }

        let noVision = ModelCapabilities.inferred(from: "gemini-1.5-pro")
        XCTAssertFalse(noVision.supportsVision, "gemini-1.5 should not have vision")
    }

    func testInferredCapabilities_GeminiImageModels() {
        let imageModels = [
            "gemini-3.1-flash-image-preview",
            "gemini-3-pro-image-preview",
            "google/gemini-3.1-flash-image-preview",
        ]
        for model in imageModels {
            let caps = ModelCapabilities.inferred(from: model)
            XCTAssertTrue(caps.supportsVision,
                          "\(model): image models should support vision")
            XCTAssertTrue(caps.supportsImageGeneration,
                          "\(model): expected imageGen=true")
            XCTAssertFalse(caps.supportsToolUse,
                           "\(model): image models should NOT support tool use")
        }
    }

    func testInferredCapabilities_QwenFamily() {
        let visionModels = [
            "qwen3.6-plus",
            "qwen/qwen3.6-plus:free",
            "qwen2.5-vl-72b",
            "qwen-vl-max",
            "qwen-omni-turbo",
        ]
        for model in visionModels {
            let caps = ModelCapabilities.inferred(from: model)
            XCTAssertTrue(caps.supportsVision,
                          "\(model): expected vision=true")
            XCTAssertTrue(caps.supportsToolUse,
                          "\(model): expected toolUse=true")
        }

        let noVision = [
            "qwen2.5-72b",
            "qwen3-8b",
        ]
        for model in noVision {
            let caps = ModelCapabilities.inferred(from: model)
            XCTAssertFalse(caps.supportsVision,
                           "\(model): expected vision=false (below 3.5, no vl/omni)")
        }
    }

    func testInferredCapabilities_UnknownModels() {
        let unknowns = ["llama3", "deepseek-chat", "mistral-large"]
        for model in unknowns {
            let caps = ModelCapabilities.inferred(from: model)
            XCTAssertEqual(caps, .default,
                           "\(model): unknown model should return default capabilities")
        }
    }

    func testInferredCapabilities_DoesNotOverrideExisting() {
        let custom = ModelCapabilities(
            supportsVision: false,
            supportsToolUse: false,
            supportsImageGeneration: true,
            supportsReasoning: true
        )
        let inferred = ModelCapabilities.inferred(from: "gpt-5.4")
        XCTAssertNotEqual(inferred, custom,
                          "Inferred and custom should differ — caller decides which to use")
    }

    // MARK: - Enabled Models

    @MainActor
    func testEnabledModelsDefault() {
        let provider = LLMProvider(name: "Test", modelName: "gpt-4o")
        XCTAssertTrue(provider.enabledModels.contains("gpt-4o"))
    }

    @MainActor
    func testEnabledModelsWithAdditional() {
        let provider = LLMProvider(name: "Test", modelName: "gpt-4o")
        provider.enabledModels = ["gpt-4o", "gpt-3.5-turbo"]

        let models = provider.enabledModels
        XCTAssertTrue(models.contains("gpt-4o"))
        XCTAssertTrue(models.contains("gpt-3.5-turbo"))
    }

    @MainActor
    func testEnabledModelsAlwaysIncludesDefault() {
        let provider = LLMProvider(name: "Test", modelName: "gpt-4o")
        provider.enabledModels = ["gpt-3.5-turbo"]

        let models = provider.enabledModels
        XCTAssertTrue(models.contains("gpt-4o"), "Default model should always be included")
    }

    // MARK: - Cached Model List

    @MainActor
    func testCachedModelListEmpty() {
        let provider = LLMProvider(name: "Test")
        XCTAssertTrue(provider.cachedModelList.isEmpty)
    }

    @MainActor
    func testCachedModelListRoundTrip() {
        let provider = LLMProvider(name: "Test")
        provider.cachedModelList = ["model-a", "model-b", "model-c"]
        XCTAssertEqual(provider.cachedModelList, ["model-a", "model-b", "model-c"])
    }

    @MainActor
    func testCachedModelListClear() {
        let provider = LLMProvider(name: "Test")
        provider.cachedModelList = ["model-a"]
        provider.cachedModelList = []
        XCTAssertTrue(provider.cachedModelList.isEmpty)
        XCTAssertNil(provider.cachedModelListRaw)
    }

    // MARK: - Thinking Budget

    @MainActor
    func testThinkingBudgetDefault() {
        let provider = LLMProvider(name: "Test")
        XCTAssertEqual(provider.thinkingBudget, 10000)
    }

    @MainActor
    func testThinkingBudgetCustomValue() {
        let provider = LLMProvider(name: "Test")
        provider.thinkingBudget = 25000
        XCTAssertEqual(provider.thinkingBudget, 25000)
    }

    @MainActor
    func testThinkingBudgetPersistence() throws {
        let provider = LLMProvider(name: "Budget Test")
        provider.thinkingBudget = 50000
        context.insert(provider)
        try context.save()

        let fetchDescriptor = FetchDescriptor<LLMProvider>(
            predicate: #Predicate { $0.name == "Budget Test" }
        )
        let fetched = try context.fetch(fetchDescriptor)
        XCTAssertEqual(fetched.first?.thinkingBudget, 50000)
    }

    // MARK: - SwiftData Persistence

    @MainActor
    func testProviderPersistence() throws {
        let provider = LLMProvider(
            name: "Persistent Provider",
            endpoint: "https://example.com/v1",
            apiKey: "test-key",
            modelName: "test-model"
        )
        provider.apiStyle = .anthropic
        provider.setCapabilities(
            ModelCapabilities(supportsVision: true, supportsReasoning: true),
            for: "test-model"
        )

        context.insert(provider)
        try context.save()

        let fetchDescriptor = FetchDescriptor<LLMProvider>(
            predicate: #Predicate { $0.name == "Persistent Provider" }
        )
        let fetched = try context.fetch(fetchDescriptor)
        XCTAssertEqual(fetched.count, 1)

        let retrieved = fetched.first!
        XCTAssertEqual(retrieved.name, "Persistent Provider")
        XCTAssertEqual(retrieved.endpoint, "https://example.com/v1")
        XCTAssertEqual(retrieved.apiStyle, .anthropic)
        XCTAssertTrue(retrieved.capabilities(for: "test-model").supportsVision)
        XCTAssertTrue(retrieved.capabilities(for: "test-model").supportsReasoning)
    }

    // MARK: - ToolCallResult

    func testToolCallResultInit() {
        let result = ToolCallResult("Success")
        XCTAssertEqual(result.text, "Success")
        XCTAssertNil(result.imageAttachments)
    }

    func testToolCallResultCancelled() {
        let result = ToolCallResult.cancelled
        XCTAssertTrue(result.text.contains("Cancelled"))
    }
}
