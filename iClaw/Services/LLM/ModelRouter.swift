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

    // MARK: - Streaming with failover

    func chatCompletionStreamWithFailover(
        agent: Agent,
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]?
    ) async throws -> (stream: AsyncStream<StreamChunk>, providerName: String) {
        let chain = resolveProviderChain(for: agent)
        guard !chain.isEmpty else { throw ChatError.noProviderConfigured }

        failoverOccurred = false

        for (index, provider) in chain.enumerated() {
            do {
                let service = LLMService(provider: provider)
                let stream = try await service.chatCompletionStream(messages: messages, tools: tools)
                lastUsedProviderName = "\(provider.name) (\(provider.modelName))"
                failoverOccurred = index > 0
                return (stream, lastUsedProviderName!)
            } catch {
                let isLast = index == chain.count - 1
                if isLast { throw error }
                // Otherwise continue to next provider
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
        let chain = resolveProviderChain(for: agent)
        guard !chain.isEmpty else { throw ChatError.noProviderConfigured }

        failoverOccurred = false

        for (index, provider) in chain.enumerated() {
            do {
                let service = LLMService(provider: provider)
                let response = try await service.chatCompletion(messages: messages, tools: tools)
                lastUsedProviderName = "\(provider.name) (\(provider.modelName))"
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
