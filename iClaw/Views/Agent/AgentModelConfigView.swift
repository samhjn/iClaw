import SwiftUI
import SwiftData

struct AgentModelConfigView: View {
    @Bindable var agent: Agent
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LLMProvider.name) private var allProviders: [LLMProvider]

    var body: some View {
        List {
            primarySection
            fallbackSection
            subAgentSection
            resolutionPreviewSection
        }
        .navigationTitle("Model Config")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Primary model

    @ViewBuilder
    private var primarySection: some View {
        Section {
            Picker("Primary Model", selection: primaryBinding) {
                Text("Global Default").tag(nil as UUID?)
                ForEach(allProviders, id: \.id) { p in
                    Text("\(p.name) — \(p.modelName)").tag(Optional(p.id))
                }
            }
        } header: {
            Text("Primary Model")
        } footer: {
            Text("The main model used for conversations with this agent.")
        }
    }

    private var primaryBinding: Binding<UUID?> {
        Binding(
            get: { agent.primaryProviderId },
            set: {
                agent.primaryProviderId = $0
                agent.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    // MARK: - Fallback chain

    @ViewBuilder
    private var fallbackSection: some View {
        Section {
            let chain = agent.fallbackProviderIds
            if chain.isEmpty {
                Text("No fallback models configured")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(chain.enumerated()), id: \.offset) { index, uid in
                    if let p = allProviders.first(where: { $0.id == uid }) {
                        HStack {
                            Text("\(index + 1).")
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .leading)
                            VStack(alignment: .leading) {
                                Text(p.name).font(.body)
                                Text(p.modelName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                removeFallback(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .onMove { source, destination in
                    var ids = agent.fallbackProviderIds
                    ids.move(fromOffsets: source, toOffset: destination)
                    agent.fallbackProviderIds = ids
                    agent.updatedAt = Date()
                    try? modelContext.save()
                }
            }

            Menu {
                ForEach(availableFallbackProviders, id: \.id) { p in
                    Button("\(p.name) — \(p.modelName)") {
                        addFallback(p.id)
                    }
                }
            } label: {
                Label("Add Fallback", systemImage: "plus.circle")
            }
            .disabled(availableFallbackProviders.isEmpty)
        } header: {
            Text("Fallback Chain")
        } footer: {
            Text("When the primary model fails, these are tried in order. Drag to reorder.")
        }
    }

    private var availableFallbackProviders: [LLMProvider] {
        let existing = Set(agent.fallbackProviderIds)
        let primaryId = agent.primaryProviderId
        return allProviders.filter { p in
            p.id != primaryId && !existing.contains(p.id)
        }
    }

    private func addFallback(_ id: UUID) {
        var chain = agent.fallbackProviderIds
        chain.append(id)
        agent.fallbackProviderIds = chain
        agent.updatedAt = Date()
        try? modelContext.save()
    }

    private func removeFallback(at index: Int) {
        var chain = agent.fallbackProviderIds
        chain.remove(at: index)
        agent.fallbackProviderIds = chain
        agent.updatedAt = Date()
        try? modelContext.save()
    }

    // MARK: - Sub-agent model

    @ViewBuilder
    private var subAgentSection: some View {
        Section {
            Picker("Sub-Agent Model", selection: subAgentBinding) {
                Text("Inherit from Primary").tag(nil as UUID?)
                ForEach(allProviders, id: \.id) { p in
                    Text("\(p.name) — \(p.modelName)").tag(Optional(p.id))
                }
            }
        } header: {
            Text("Sub-Agent Default")
        } footer: {
            Text("The default model for sub-agents created by this agent. Individual sub-agents can be overridden at creation time.")
        }
    }

    private var subAgentBinding: Binding<UUID?> {
        Binding(
            get: { agent.subAgentProviderId },
            set: {
                agent.subAgentProviderId = $0
                agent.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    // MARK: - Preview

    @ViewBuilder
    private var resolutionPreviewSection: some View {
        Section {
            let router = ModelRouter(modelContext: modelContext)
            let chain = router.resolveProviderChain(for: agent)

            if chain.isEmpty {
                Text("No models available — configure a provider in Settings")
                    .foregroundStyle(.red)
            } else {
                ForEach(Array(chain.enumerated()), id: \.offset) { index, p in
                    HStack {
                        if index == 0 {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption)
                        } else {
                            Image(systemName: "arrow.turn.down.right")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        VStack(alignment: .leading) {
                            Text(p.name).font(.body)
                            Text(p.modelName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Resolution Order")
        } footer: {
            Text("This is the effective order in which models will be tried for this agent.")
        }
    }
}
