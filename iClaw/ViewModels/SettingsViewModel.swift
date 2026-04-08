import Foundation
import SwiftData
import Observation

@Observable
final class SettingsViewModel {
    var providers: [LLMProvider] = []

    /// Set by the View to trigger a deletion confirmation alert.
    var providerToDelete: LLMProvider?

    /// Names of agents that reference the provider pending deletion (for the alert message).
    var affectedAgentNames: [String] = []

    private(set) var modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchProviders()
    }

    func fetchProviders() {
        let descriptor = FetchDescriptor<LLMProvider>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        providers = (try? modelContext.fetch(descriptor)) ?? []
    }

    func addProvider(
        name: String,
        endpoint: String,
        apiKey: String,
        modelName: String
    ) {
        let isFirst = providers.isEmpty
        let provider = LLMProvider(
            name: name,
            endpoint: endpoint,
            apiKey: apiKey,
            modelName: modelName,
            isDefault: isFirst
        )
        modelContext.insert(provider)
        try? modelContext.save()
        fetchProviders()
    }

    func setDefault(_ provider: LLMProvider) {
        for p in providers {
            p.isDefault = (p.id == provider.id)
        }
        try? modelContext.save()
        fetchProviders()
    }

    /// Returns the names of agents that reference this provider (as primary, fallback, or sub-agent default).
    func agentNamesUsing(provider: LLMProvider) -> [String] {
        let providerId = provider.id.uuidString
        let agents = (try? modelContext.fetch(FetchDescriptor<Agent>())) ?? []
        return agents.compactMap { agent in
            let usesPrimary = agent.primaryProviderIdRaw == providerId
            let usesFallback = agent.fallbackProviderIdsRaw?.contains(providerId) == true
            let usesSubAgent = agent.subAgentProviderIdRaw == providerId
            guard usesPrimary || usesFallback || usesSubAgent else { return nil }
            return agent.name
        }
    }

    /// Prepare for provider deletion: populate affectedAgentNames and set providerToDelete.
    func confirmDeleteProvider(_ provider: LLMProvider) {
        affectedAgentNames = agentNamesUsing(provider: provider)
        providerToDelete = provider
    }

    func deleteProvider(_ provider: LLMProvider) {
        let wasDefault = provider.isDefault
        modelContext.delete(provider)
        try? modelContext.save()
        fetchProviders()
        if wasDefault, let first = providers.first {
            first.isDefault = true
            try? modelContext.save()
            fetchProviders()
        }
        providerToDelete = nil
        affectedAgentNames = []
    }

    func updateProvider(_ provider: LLMProvider) {
        try? modelContext.save()
        fetchProviders()
    }

    func addProviderDirectly(_ provider: LLMProvider) {
        modelContext.insert(provider)
        try? modelContext.save()
        fetchProviders()
    }

    // MARK: - Remote Model Fetching

    @MainActor
    func fetchRemoteModels(for provider: LLMProvider) async throws -> [String] {
        let models = try await LLMService.fetchModels(
            endpoint: provider.endpoint,
            apiKey: provider.apiKey,
            apiStyle: provider.apiStyle
        )
        provider.cachedModelList = models
        provider.cachedModelListDate = Date()
        try? modelContext.save()
        return models
    }

    func toggleModel(_ modelName: String, enabled: Bool, for provider: LLMProvider) {
        var current = provider.enabledModels
        if enabled {
            if !current.contains(modelName) {
                current.append(modelName)
            }
        } else {
            if modelName != provider.modelName {
                current.removeAll { $0 == modelName }
            }
        }
        provider.enabledModels = current
        try? modelContext.save()
        fetchProviders()
    }

    func setDefaultModel(_ modelName: String, for provider: LLMProvider) {
        let oldDefault = provider.modelName
        provider.modelName = modelName
        var enabled = provider.enabledModels
        if !enabled.contains(oldDefault) {
            enabled.append(oldDefault)
        }
        provider.enabledModels = enabled
        try? modelContext.save()
        fetchProviders()
    }
}
