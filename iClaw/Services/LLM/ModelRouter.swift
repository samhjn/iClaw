import Foundation
import SwiftData

/// Resolves LLM providers for agents and handles automatic failover.
final class ModelRouter {
    private let modelContext: ModelContext
    private(set) var lastUsedProviderName: String?
    private(set) var failoverOccurred = false

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Provider resolution

    /// Returns the ordered list of providers for an agent: primary first, then fallbacks.
    func resolveProviderChain(for agent: Agent) -> [LLMProvider] {
        var chain: [LLMProvider] = []

        if let primaryId = agent.primaryProviderId, let p = fetchProvider(id: primaryId) {
            chain.append(p)
        }

        for fbId in agent.fallbackProviderIds {
            if let p = fetchProvider(id: fbId), !chain.contains(where: { $0.id == p.id }) {
                chain.append(p)
            }
        }

        if chain.isEmpty {
            if let global = fetchGlobalDefault() {
                chain.append(global)
            }
        }

        return chain
    }

    /// Returns the primary provider for an agent (first in chain).
    func primaryProvider(for agent: Agent) -> LLMProvider? {
        resolveProviderChain(for: agent).first
    }

    /// Resolve the model capabilities for the primary (first) provider+model pair.
    func primaryModelCapabilities(for agent: Agent) -> ModelCapabilities {
        let chain = resolveProviderChainWithModels(for: agent)
        guard let first = chain.first else { return .default }
        let effectiveModel = first.modelName ?? first.provider.modelName
        return first.provider.capabilities(for: effectiveModel)
    }

    /// Returns the provider for sub-agent creation.
    func subAgentProvider(for agent: Agent) -> LLMProvider? {
        if let subId = agent.subAgentProviderId, let p = fetchProvider(id: subId) {
            return p
        }
        return primaryProvider(for: agent)
    }

    /// Returns a provider by specific ID, or nil.
    func providerById(_ id: UUID) -> LLMProvider? {
        fetchProvider(id: id)
    }

    /// Returns the resolved chain with model name overrides,
    /// filtered by the agent's model whitelist if configured.
    /// Same provider can appear multiple times with different models.
    func resolveProviderChainWithModels(for agent: Agent) -> [(provider: LLMProvider, modelName: String?)] {
        var chain: [(provider: LLMProvider, modelName: String?)] = []
        var seen = Set<String>()

        func effectiveModel(provider: LLMProvider, override: String?) -> String {
            override ?? provider.modelName
        }

        func dedupKey(provider: LLMProvider, override: String?) -> String {
            "\(provider.id.uuidString):\(effectiveModel(provider: provider, override: override))"
        }

        if let primaryId = agent.primaryProviderId, let p = fetchProvider(id: primaryId) {
            let key = dedupKey(provider: p, override: agent.primaryModelNameOverride)
            chain.append((p, agent.primaryModelNameOverride))
            seen.insert(key)
        }

        let fbNames = agent.fallbackModelNames
        for (i, fbId) in agent.fallbackProviderIds.enumerated() {
            if let p = fetchProvider(id: fbId) {
                let modelOverride = i < fbNames.count && !fbNames[i].isEmpty ? fbNames[i] : nil
                let key = dedupKey(provider: p, override: modelOverride)
                if !seen.contains(key) {
                    chain.append((p, modelOverride))
                    seen.insert(key)
                }
            }
        }

        if chain.isEmpty {
            if let global = fetchGlobalDefault() {
                chain.append((global, nil))
            }
        }

        return applyModelWhitelist(chain, for: agent)
    }

    /// Filters a resolved provider chain through the agent's model whitelist.
    /// If the whitelist is empty, all models pass through unchanged.
    private func applyModelWhitelist(
        _ chain: [(provider: LLMProvider, modelName: String?)],
        for agent: Agent
    ) -> [(provider: LLMProvider, modelName: String?)] {
        let whitelist = agent.allowedModelIds
        guard !whitelist.isEmpty else { return chain }

        let filtered = chain.filter { entry in
            let effectiveModel = entry.modelName ?? entry.provider.modelName
            return whitelist.contains("\(entry.provider.id.uuidString):\(effectiveModel)")
        }
        return filtered.isEmpty ? chain : filtered
    }

    // MARK: - Streaming with failover

    func chatCompletionStreamWithFailover(
        agent: Agent,
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]?
    ) async throws -> (stream: AsyncStream<StreamChunk>, providerName: String, capabilities: ModelCapabilities) {
        let chain = resolveProviderChainWithModels(for: agent)
        guard !chain.isEmpty else { throw ChatError.noProviderConfigured }

        failoverOccurred = false

        for (index, entry) in chain.enumerated() {
            do {
                let effectiveModel = entry.modelName ?? entry.provider.modelName
                let caps = entry.provider.capabilities(for: effectiveModel)
                let effectiveTools = caps.supportsToolUse ? tools : nil
                let service = LLMService(provider: entry.provider, modelNameOverride: entry.modelName)
                let stream = try await service.chatCompletionStream(messages: messages, tools: effectiveTools)
                lastUsedProviderName = "\(entry.provider.name) (\(effectiveModel))"
                failoverOccurred = index > 0
                return (stream, lastUsedProviderName!, caps)
            } catch {
                let isLast = index == chain.count - 1
                if isLast { throw error }
            }
        }

        throw ChatError.noProviderConfigured
    }

    // MARK: - Non-streaming with failover

    func chatCompletionWithFailover(
        agent: Agent,
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]?
    ) async throws -> (response: LLMChatResponse, providerName: String) {
        let chain = resolveProviderChainWithModels(for: agent)
        guard !chain.isEmpty else { throw ChatError.noProviderConfigured }

        failoverOccurred = false

        for (index, entry) in chain.enumerated() {
            do {
                let effectiveModel = entry.modelName ?? entry.provider.modelName
                let caps = entry.provider.capabilities(for: effectiveModel)
                let effectiveTools = caps.supportsToolUse ? tools : nil
                let service = LLMService(provider: entry.provider, modelNameOverride: entry.modelName)
                let response = try await service.chatCompletion(messages: messages, tools: effectiveTools)
                lastUsedProviderName = "\(entry.provider.name) (\(effectiveModel))"
                failoverOccurred = index > 0
                return (response, lastUsedProviderName!)
            } catch {
                let isLast = index == chain.count - 1
                if isLast { throw error }
            }
        }

        throw ChatError.noProviderConfigured
    }

    // MARK: - Specific provider (no failover)

    func chatCompletionStreamWith(
        provider: LLMProvider,
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]?
    ) async throws -> AsyncStream<StreamChunk> {
        let service = LLMService(provider: provider)
        return try await service.chatCompletionStream(messages: messages, tools: tools)
    }

    func chatCompletionWith(
        provider: LLMProvider,
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]?
    ) async throws -> LLMChatResponse {
        let service = LLMService(provider: provider)
        return try await service.chatCompletion(messages: messages, tools: tools)
    }

    // MARK: - Provider queries

    func fetchAllProviders() -> [LLMProvider] {
        let descriptor = FetchDescriptor<LLMProvider>(sortBy: [SortDescriptor(\.name)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Private

    private func fetchProvider(id: UUID) -> LLMProvider? {
        let descriptor = FetchDescriptor<LLMProvider>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchGlobalDefault() -> LLMProvider? {
        var descriptor = FetchDescriptor<LLMProvider>(
            predicate: #Predicate { $0.isDefault == true }
        )
        descriptor.fetchLimit = 1
        if let p = try? modelContext.fetch(descriptor).first { return p }
        let all = FetchDescriptor<LLMProvider>(sortBy: [SortDescriptor(\.createdAt)])
        return try? modelContext.fetch(all).first
    }
}
