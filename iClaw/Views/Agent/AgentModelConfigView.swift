import SwiftUI
import SwiftData

/// Represents a provider + specific model combination for selection.
struct ProviderModel: Identifiable, Hashable {
    let provider: LLMProvider
    let modelName: String

    var id: String { "\(provider.id.uuidString):\(modelName)" }
    var displayName: String { "\(provider.name) — \(modelName)" }
    var isDefault: Bool { modelName == provider.modelName }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ProviderModel, rhs: ProviderModel) -> Bool {
        lhs.id == rhs.id
    }
}

struct AgentModelConfigView: View {
    @Bindable var agent: Agent
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LLMProvider.name) private var allProviders: [LLMProvider]

    private var allProviderModels: [ProviderModel] {
        allProviders.flatMap { provider in
            provider.enabledModels.map { modelName in
                ProviderModel(provider: provider, modelName: modelName)
            }
        }
    }

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
                Text("Global Default").tag("" as String)
                ForEach(allProviderModels) { pm in
                    Text(pm.displayName).tag(pm.id)
                }
            }
        } header: {
            Text("Primary Model")
        } footer: {
            Text("The main model used for conversations with this agent.")
        }
    }

    private var primaryBinding: Binding<String> {
        Binding(
            get: {
                guard let pid = agent.primaryProviderId else { return "" }
                let modelOverride = agent.primaryModelNameOverride
                if let modelOverride {
                    return "\(pid.uuidString):\(modelOverride)"
                }
                if let provider = allProviders.first(where: { $0.id == pid }) {
                    return "\(pid.uuidString):\(provider.modelName)"
                }
                return ""
            },
            set: { newValue in
                if newValue.isEmpty {
                    agent.primaryProviderId = nil
                    agent.primaryModelNameOverride = nil
                } else {
                    let parts = newValue.split(separator: ":", maxSplits: 1)
                    if parts.count == 2, let uid = UUID(uuidString: String(parts[0])) {
                        let modelName = String(parts[1])
                        agent.primaryProviderId = uid
                        if let provider = allProviders.first(where: { $0.id == uid }),
                           modelName == provider.modelName {
                            agent.primaryModelNameOverride = nil
                        } else {
                            agent.primaryModelNameOverride = modelName
                        }
                    }
                }
                agent.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    // MARK: - Fallback chain

    @ViewBuilder
    private var fallbackSection: some View {
        Section {
            let chain = buildFallbackChain()
            if chain.isEmpty {
                Text("No fallback models configured")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(chain.enumerated()), id: \.offset) { index, pm in
                    HStack {
                        Text("\(index + 1).")
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)
                        VStack(alignment: .leading) {
                            Text(pm.provider.name).font(.body)
                            Text(pm.modelName).font(.caption).foregroundStyle(.secondary)
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
                .onMove { source, destination in
                    var ids = agent.fallbackProviderIds
                    var names = agent.fallbackModelNames
                    ids.move(fromOffsets: source, toOffset: destination)
                    while names.count < ids.count { names.append("") }
                    names.move(fromOffsets: source, toOffset: destination)
                    agent.fallbackProviderIds = ids
                    agent.fallbackModelNames = names
                    agent.updatedAt = Date()
                    try? modelContext.save()
                }
            }

            Menu {
                ForEach(availableFallbackModels) { pm in
                    Button(pm.displayName) {
                        addFallback(pm)
                    }
                }
            } label: {
                Label("Add Fallback", systemImage: "plus.circle")
            }
            .disabled(availableFallbackModels.isEmpty)
        } header: {
            Text("Fallback Chain")
        } footer: {
            Text("When the primary model fails, these are tried in order. Drag to reorder.")
        }
    }

    private func buildFallbackChain() -> [ProviderModel] {
        let ids = agent.fallbackProviderIds
        let names = agent.fallbackModelNames
        return ids.enumerated().compactMap { (i, uid) -> ProviderModel? in
            guard let p = allProviders.first(where: { $0.id == uid }) else { return nil }
            let modelName = i < names.count && !names[i].isEmpty ? names[i] : p.modelName
            return ProviderModel(provider: p, modelName: modelName)
        }
    }

    private var availableFallbackModels: [ProviderModel] {
        let existingIds = Set(buildFallbackChain().map(\.id))
        let primaryId = primaryBinding.wrappedValue
        return allProviderModels.filter { pm in
            pm.id != primaryId && !existingIds.contains(pm.id)
        }
    }

    private func addFallback(_ pm: ProviderModel) {
        var ids = agent.fallbackProviderIds
        var names = agent.fallbackModelNames
        ids.append(pm.provider.id)
        while names.count < ids.count - 1 { names.append("") }
        names.append(pm.modelName == pm.provider.modelName ? "" : pm.modelName)
        agent.fallbackProviderIds = ids
        agent.fallbackModelNames = names
        agent.updatedAt = Date()
        try? modelContext.save()
    }

    private func removeFallback(at index: Int) {
        var ids = agent.fallbackProviderIds
        var names = agent.fallbackModelNames
        ids.remove(at: index)
        if index < names.count { names.remove(at: index) }
        agent.fallbackProviderIds = ids
        agent.fallbackModelNames = names
        agent.updatedAt = Date()
        try? modelContext.save()
    }

    // MARK: - Sub-agent model

    @ViewBuilder
    private var subAgentSection: some View {
        Section {
            Picker("Sub-Agent Model", selection: subAgentBinding) {
                Text("Inherit from Primary").tag("" as String)
                ForEach(allProviderModels) { pm in
                    Text(pm.displayName).tag(pm.id)
                }
            }
        } header: {
            Text("Sub-Agent Default")
        } footer: {
            Text("The default model for sub-agents created by this agent.")
        }
    }

    private var subAgentBinding: Binding<String> {
        Binding(
            get: {
                guard let sid = agent.subAgentProviderId else { return "" }
                let override = agent.subAgentModelNameOverride
                if let override {
                    return "\(sid.uuidString):\(override)"
                }
                if let provider = allProviders.first(where: { $0.id == sid }) {
                    return "\(sid.uuidString):\(provider.modelName)"
                }
                return ""
            },
            set: { newValue in
                if newValue.isEmpty {
                    agent.subAgentProviderId = nil
                    agent.subAgentModelNameOverride = nil
                } else {
                    let parts = newValue.split(separator: ":", maxSplits: 1)
                    if parts.count == 2, let uid = UUID(uuidString: String(parts[0])) {
                        let modelName = String(parts[1])
                        agent.subAgentProviderId = uid
                        if let provider = allProviders.first(where: { $0.id == uid }),
                           modelName == provider.modelName {
                            agent.subAgentModelNameOverride = nil
                        } else {
                            agent.subAgentModelNameOverride = modelName
                        }
                    }
                }
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
            let chain = router.resolveProviderChainWithModels(for: agent)

            if chain.isEmpty {
                Text("No models available — configure a provider in Settings")
                    .foregroundStyle(.red)
            } else {
                ForEach(Array(chain.enumerated()), id: \.offset) { index, entry in
                    let effectiveModel = entry.modelName ?? entry.provider.modelName
                    let isOverride = entry.modelName != nil && entry.modelName != entry.provider.modelName

                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(index == 0 ? Color.yellow.opacity(0.2) : Color.secondary.opacity(0.1))
                                .frame(width: 28, height: 28)
                            if index == 0 {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.system(size: 12))
                            } else {
                                Text("\(index + 1)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(effectiveModel)
                                .font(.subheadline.bold())
                            HStack(spacing: 4) {
                                Text(entry.provider.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if isOverride {
                                    Text("(override)")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }

                        Spacer()

                        if index == 0 {
                            Text("Primary")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.blue))
                        } else {
                            Text("Fallback")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().stroke(.secondary.opacity(0.3)))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // Sub-agent preview
            let subRouter = ModelRouter(modelContext: modelContext)
            if let subProvider = subRouter.subAgentProvider(for: agent) {
                let subModel = agent.subAgentModelNameOverride ?? subProvider.modelName
                Divider()
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(systemName: "person.2")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(subModel)
                            .font(.subheadline.bold())
                        Text("\(subProvider.name) · Sub-Agent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Sub-Agent")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().stroke(.orange.opacity(0.4)))
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Resolution Order")
        } footer: {
            Text("Models are tried in this order. Same provider can appear with different models.")
        }
    }
}
