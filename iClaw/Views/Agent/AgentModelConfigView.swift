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
            compressionSection
            resolutionPreviewSection
        }
        .navigationTitle(L10n.ModelConfig.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Primary model

    @ViewBuilder
    private var primarySection: some View {
        Section {
            Picker(L10n.ModelConfig.primaryModel, selection: primaryBinding) {
                Text(L10n.ModelConfig.globalDefault).tag("" as String)
                ForEach(allProviderModels) { pm in
                    Text(pm.displayName).tag(pm.id)
                }
            }
        } header: {
            Text(L10n.ModelConfig.primaryModel)
        } footer: {
            Text(L10n.ModelConfig.primaryModelFooter)
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
                Text(L10n.ModelConfig.noFallback)
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
                Label(L10n.ModelConfig.addFallback, systemImage: "plus.circle")
            }
            .disabled(availableFallbackModels.isEmpty)
        } header: {
            Text(L10n.ModelConfig.fallbackChain)
        } footer: {
            Text(L10n.ModelConfig.fallbackFooter)
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
            Picker(L10n.ModelConfig.subAgentModel, selection: subAgentBinding) {
                Text(L10n.ModelConfig.inheritFromPrimary).tag("" as String)
                ForEach(allProviderModels) { pm in
                    Text(pm.displayName).tag(pm.id)
                }
            }
        } header: {
            Text(L10n.ModelConfig.subAgentDefault)
        } footer: {
            Text(L10n.ModelConfig.subAgentFooter)
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

    // MARK: - Compression

    @ViewBuilder
    private var compressionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.ModelConfig.compressionThreshold)
                    Spacer()
                    Text(agent.compressionThreshold > 0
                         ? "\(agent.compressionThreshold)"
                         : L10n.ModelConfig.defaultThreshold(ContextManager.compressionThreshold))
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: compressionThresholdBinding,
                    in: 0...20000,
                    step: 500
                )

                HStack {
                    Text(L10n.ModelConfig.systemDefault)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if agent.compressionThreshold > 0 {
                        Button(L10n.ModelConfig.resetDefault) {
                            agent.compressionThreshold = 0
                            agent.updatedAt = Date()
                            try? modelContext.save()
                        }
                        .font(.caption)
                    }
                }
            }
        } header: {
            Text(L10n.ModelConfig.contextCompression)
        } footer: {
            Text(L10n.ModelConfig.compressionFooter)
        }
    }

    private var compressionThresholdBinding: Binding<Double> {
        Binding(
            get: { Double(agent.compressionThreshold) },
            set: { newValue in
                agent.compressionThreshold = Int(newValue)
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
                Text(L10n.ModelConfig.noModels)
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
                                    Text(L10n.ModelConfig.override)
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }

                        Spacer()

                        if index == 0 {
                            Text(L10n.ModelConfig.primary)
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.blue))
                        } else {
                            Text(L10n.ModelConfig.fallback)
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

            // Sub-agent preview: resolve what a sub-agent would actually use
            let subRouter = ModelRouter(modelContext: modelContext)
            let subProviderInfo: (provider: LLMProvider, modelName: String)? = {
                if let subId = agent.subAgentProviderId,
                   let p = subRouter.providerById(subId) {
                    return (p, agent.subAgentModelNameOverride ?? p.modelName)
                }
                // "Inherit from primary" — use the parent's resolved primary
                let resolved = subRouter.resolveProviderChainWithModels(for: agent)
                if let primary = resolved.first {
                    return (primary.provider, primary.modelName ?? primary.provider.modelName)
                }
                return nil
            }()
            if let info = subProviderInfo {
                let isInherited = agent.subAgentProviderId == nil
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
                        Text(info.modelName)
                            .font(.subheadline.bold())
                        HStack(spacing: 4) {
                            Text("\(info.provider.name) · Sub-Agent")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if isInherited {
                                Text("= Primary")
                                    .font(.caption2)
                                    .foregroundStyle(.blue.opacity(0.7))
                            }
                        }
                    }
                    Spacer()
                    Text(L10n.ModelConfig.subAgent)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().stroke(.orange.opacity(0.4)))
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text(L10n.ModelConfig.resolutionOrder)
        } footer: {
            Text(L10n.ModelConfig.resolutionFooter)
        }
    }
}
