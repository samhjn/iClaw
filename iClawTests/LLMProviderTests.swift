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
        XCTAssertEqual(provider.modelName, "gpt-4o")
        XCTAssertFalse(provider.isDefault)
        XCTAssertEqual(provider.maxTokens, 4096)
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
