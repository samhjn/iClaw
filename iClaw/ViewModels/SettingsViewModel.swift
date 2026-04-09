import Foundation
import SwiftData
import Observation

@Observable
final class SettingsViewModel {
    var providers: [LLMProvider] = []

    /// UUID of the current default provider.  The View reads this instead of
    /// `provider.isDefault` so that `@Model` property mutations during
    /// deletion don't trigger premature SwiftUI row invalidation.
    var defaultProviderId: UUID?

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
        defaultProviderId = providers.first(where: \.isDefault)?.id
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
        let successor: LLMProvider? = wasDefault
            ? providers.first { $0.id != provider.id }
            : nil

        // ── 1. Update the view state FIRST ──────────────────────────
        // Remove the provider from the ForEach array and update the
        // default badge before any @Model mutation or save().  This
        // lets SwiftUI apply a single, clean batch update (row removal)
        // before SwiftData fires observation notifications that could
        // trigger conflicting batch updates → crash.
        //
        // NOTE: AgentModelConfigView previously used @Query for
        // allProviders, which auto-fired on save() and caused a
        // complex multi-section batch update that conflicted with this
        // List's update.  That @Query has been replaced with @State +
        // onAppear to break the cross-view observation chain.
        providers = providers.filter { $0.id != provider.id }
        if wasDefault {
            defaultProviderId = successor?.id
        }

        // ── 2. Persist ──────────────────────────────────────────────
        // The ForEach no longer contains the deleted row, so @Model
        // observation from these mutations won't re-enter the list.
        // The View reads vm.defaultProviderId (not provider.isDefault),
        // so the successor mutation doesn't trigger a conflicting row
        // re-render through SwiftData per-property observation.
        successor?.isDefault = true
        modelContext.delete(provider)
        try? modelContext.save()

        // ── 3. Re-sync ─────────────────────────────────────────────
        // fetchProviders() returns the same list we already set in
        // step 1, so the ForEach sees no identity change.
        fetchProviders()

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
