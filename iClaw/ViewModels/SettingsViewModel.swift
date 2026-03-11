import Foundation
import SwiftData
import Observation

@Observable
final class SettingsViewModel {
    var providers: [LLMProvider] = []

    private var modelContext: ModelContext

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
    }

    func updateProvider(_ provider: LLMProvider) {
        try? modelContext.save()
        fetchProviders()
    }
}
