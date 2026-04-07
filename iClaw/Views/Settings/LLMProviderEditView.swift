import SwiftUI

struct LLMProviderEditView: View {
    let viewModel: SettingsViewModel
    var existingProvider: LLMProvider?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var endpoint: String = "https://api.openai.com/v1"
    @State private var apiKey: String = ""
    @State private var modelName: String = "gpt-5.4"
    @State private var maxTokens: Int = 4096
    @State private var thinkingBudget: Int = 10000
    @State private var temperature: Double = 0.7
    @State private var apiStyle: APIStyle = .openAI

    // Per-model capabilities
    @State private var modelCapabilities: [String: ModelCapabilities] = [:]

    @State private var fetchedModels: [String] = []
    @State private var enabledModels: Set<String> = []
    @State private var isFetchingModels = false
    @State private var fetchError: String?

    @State private var showAddModel = false
    @State private var newModelName: String = ""

    private var isEditing: Bool { existingProvider != nil }

    /// Only show enabled models in pickers.
    private var allKnownModels: [String] {
        Array(enabledModels).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                providerSection
                apiStyleSection
                authSection
                defaultModelSection
                enabledModelsSection
                remoteModelsSection
                parametersSection
                presetsSection
            }
            .navigationTitle(isEditing ? L10n.Provider.editProvider : L10n.Provider.addProvider)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.save) {
                        save()
                        dismiss()
                    }
                    .disabled(name.isEmpty || endpoint.isEmpty || modelName.isEmpty)
                }
            }
            .alert(L10n.Provider.addModel, isPresented: $showAddModel) {
                TextField(L10n.Provider.modelNamePlaceholder, text: $newModelName)
                    .autocapitalization(.none)
                Button(L10n.Common.add) {
                    let trimmed = newModelName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        enableModel(trimmed)
                    }
                    newModelName = ""
                }
                Button(L10n.Common.cancel, role: .cancel) { newModelName = "" }
            }
        }
        .onAppear {
            if let p = existingProvider {
                name = p.name
                endpoint = p.endpoint
                apiKey = p.apiKey
                modelName = p.modelName
                maxTokens = p.maxTokens
                thinkingBudget = p.thinkingBudget
                temperature = p.temperature
                apiStyle = APIStyle(rawValue: p.apiStyleRaw) ?? .openAI
                enabledModels = Set(p.enabledModels)
                fetchedModels = p.cachedModelList

                // Load model capabilities from raw JSON
                if let json = p.modelCapabilitiesJSON,
                   let data = json.data(using: .utf8),
                   let dict = try? JSONDecoder().decode([String: ModelCapabilities].self, from: data) {
                    modelCapabilities = dict
                }

                // Migrate legacy provider-level flags for existing models without capabilities
                for model in p.enabledModels where modelCapabilities[model] == nil {
                    modelCapabilities[model] = ModelCapabilities(
                        supportsVision: p.supportsVision,
                        supportsToolUse: p.supportsToolUse,
                        supportsImageGeneration: p.supportsImageGeneration,
                        supportsReasoning: false
                    )
                }
            } else {
                enableModel(modelName)
            }
        }
    }

    // MARK: - Sections

    private var providerSection: some View {
        Section(L10n.Provider.provider) {
            TextField(L10n.Common.name, text: $name)
            TextField(L10n.Provider.endpoint, text: $endpoint)
                .textContentType(.URL)
                .autocapitalization(.none)
                .keyboardType(.URL)
        }
    }

    private var apiStyleSection: some View {
        Section {
            Picker(L10n.Provider.apiStyle, selection: $apiStyle) {
                ForEach(APIStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
        } header: {
            Text(L10n.Provider.apiStyle)
        } footer: {
            Text(L10n.Provider.apiStyleFooter)
        }
    }

    private var authSection: some View {
        Section(L10n.Provider.authentication) {
            SecureField(L10n.Provider.apiKey, text: $apiKey)
                .autocapitalization(.none)
        }
    }

    private var defaultModelSection: some View {
        Section {
            HStack {
                TextField(L10n.Provider.defaultModel, text: $modelName)
                    .autocapitalization(.none)
                if !allKnownModels.isEmpty {
                    Menu {
                        ForEach(allKnownModels, id: \.self) { model in
                            Button(model) {
                                modelName = model
                                enableModel(model)
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(L10n.Provider.defaultModel)
        } footer: {
            Text(L10n.Provider.defaultModelFooter)
        }
    }

    private var enabledModelsSection: some View {
        Section {
            if enabledModels.isEmpty {
                Text(L10n.Provider.noModelsEnabled)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(Array(enabledModels).sorted(), id: \.self) { model in
                    modelRow(model)
                }
            }

            Button {
                showAddModel = true
            } label: {
                Label(L10n.Provider.manuallyAddModel, systemImage: "plus")
            }
        } header: {
            HStack {
                Text(L10n.Provider.enabledModels)
                Spacer()
                Text("\(enabledModels.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(L10n.Provider.enabledModelsFooter)
        }
    }

    /// Inline model row with expandable capabilities toggles.
    @ViewBuilder
    private func modelRow(_ model: String) -> some View {
        DisclosureGroup {
            let binding = capabilitiesBinding(for: model)
            Toggle(L10n.Provider.supportsVision, isOn: binding.supportsVision)
            Toggle(L10n.Provider.supportsToolUse, isOn: binding.supportsToolUse)
            Picker(L10n.Provider.supportsImageGeneration, selection: binding.imageGenerationMode) {
                ForEach(ImageGenMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            Picker(L10n.Provider.thinkingLevel, selection: thinkingLevelBinding(for: model)) {
                ForEach(ThinkingLevel.allCases, id: \.self) { level in
                    Text(level.displayName).tag(level)
                }
            }
            perModelParametersView(for: model)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model)
                        .font(.subheadline)
                    if model == modelName {
                        Text(L10n.Common.defaultLabel)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    HStack(spacing: 4) {
                        let c = modelCapabilities[model] ?? .default
                        if c.supportsVision { capBadge("eye", color: .green) }
                        if c.supportsToolUse { capBadge("wrench", color: .blue) }
                        if c.thinkingLevel.isEnabled { thinkingLevelBadge(c.thinkingLevel) }
                        if c.imageGenerationMode == .chatInline { capBadge("paintbrush", color: .orange) }
                        if c.imageGenerationMode == .dedicatedAPI { capBadge("photo", color: .orange) }
                    }
                }
                Spacer()
                if model == modelName {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            if model != modelName {
                Button(role: .destructive) {
                    enabledModels.remove(model)
                    modelCapabilities.removeValue(forKey: model)
                } label: {
                    Label(L10n.Common.disable, systemImage: "xmark")
                }
            }
        }
        .swipeActions(edge: .leading) {
            if model != modelName {
                Button(L10n.Provider.setDefault) {
                    modelName = model
                }
                .tint(.blue)
            }
        }
        .contextMenu {
            if model != modelName {
                Button {
                    modelName = model
                } label: {
                    Label(L10n.Provider.setDefault, systemImage: "star")
                }
                Button(role: .destructive) {
                    enabledModels.remove(model)
                    modelCapabilities.removeValue(forKey: model)
                } label: {
                    Label(L10n.Common.disable, systemImage: "xmark")
                }
            }
        }
    }

    /// Create individual Bool bindings for each capability field of a model.
    private func capabilitiesBinding(for model: String) -> CapabilitiesBindings {
        CapabilitiesBindings(
            supportsVision: Binding(
                get: { (modelCapabilities[model] ?? .default).supportsVision },
                set: { newVal in
                    var caps = modelCapabilities[model] ?? .default
                    caps.supportsVision = newVal
                    modelCapabilities[model] = caps
                }
            ),
            supportsToolUse: Binding(
                get: { (modelCapabilities[model] ?? .default).supportsToolUse },
                set: { newVal in
                    var caps = modelCapabilities[model] ?? .default
                    caps.supportsToolUse = newVal
                    modelCapabilities[model] = caps
                }
            ),
            imageGenerationMode: Binding(
                get: { (modelCapabilities[model] ?? .default).imageGenerationMode },
                set: { newVal in
                    var caps = modelCapabilities[model] ?? .default
                    caps.imageGenerationMode = newVal
                    modelCapabilities[model] = caps
                }
            )
        )
    }

    /// ThinkingLevel binding for a specific model.
    private func thinkingLevelBinding(for model: String) -> Binding<ThinkingLevel> {
        Binding(
            get: { (modelCapabilities[model] ?? .default).thinkingLevel },
            set: { newVal in
                var caps = modelCapabilities[model] ?? .default
                caps.thinkingLevel = newVal
                // Keep legacy flag in sync
                caps.supportsReasoning = newVal.isEnabled
                modelCapabilities[model] = caps
            }
        )
    }

    @ViewBuilder
    private func capBadge(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 9))
            .foregroundStyle(color)
            .padding(3)
            .background(color.opacity(0.1), in: Circle())
    }

    @ViewBuilder
    private func thinkingLevelBadge(_ level: ThinkingLevel) -> some View {
        HStack(spacing: 1) {
            Image(systemName: "brain")
                .font(.system(size: 9))
            Text(level.displayName.prefix(1))
                .font(.system(size: 7, weight: .bold))
        }
        .foregroundStyle(.purple)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(.purple.opacity(0.1), in: Capsule())
    }

    /// Per-model maxTokens / temperature overrides (nil = use provider default).
    @ViewBuilder
    private func perModelParametersView(for model: String) -> some View {
        let caps = modelCapabilities[model] ?? .default
        let hasMaxTokensOverride = caps.maxTokens != nil
        let hasTempOverride = caps.temperature != nil

        // Max Tokens override
        HStack {
            Toggle(isOn: Binding(
                get: { hasMaxTokensOverride },
                set: { enabled in
                    var c = modelCapabilities[model] ?? .default
                    c.maxTokens = enabled ? maxTokens : nil
                    modelCapabilities[model] = c
                }
            )) {
                Text(L10n.Provider.perModelMaxTokens)
            }
        }
        if hasMaxTokensOverride {
            Stepper(
                L10n.Provider.maxTokens(caps.maxTokens ?? maxTokens),
                value: Binding(
                    get: { caps.maxTokens ?? maxTokens },
                    set: { newVal in
                        var c = modelCapabilities[model] ?? .default
                        c.maxTokens = newVal
                        modelCapabilities[model] = c
                    }
                ),
                in: 256...128000,
                step: 256
            )
        }

        // Temperature override
        HStack {
            Toggle(isOn: Binding(
                get: { hasTempOverride },
                set: { enabled in
                    var c = modelCapabilities[model] ?? .default
                    c.temperature = enabled ? temperature : nil
                    modelCapabilities[model] = c
                }
            )) {
                Text(L10n.Provider.perModelTemperature)
            }
        }
        if hasTempOverride {
            HStack {
                Text("\(caps.temperature ?? temperature, specifier: "%.2f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
                Slider(
                    value: Binding(
                        get: { caps.temperature ?? temperature },
                        set: { newVal in
                            var c = modelCapabilities[model] ?? .default
                            c.temperature = newVal
                            modelCapabilities[model] = c
                        }
                    ),
                    in: 0...2,
                    step: 0.05
                )
            }
        }
    }

    private var remoteModelsSection: some View {
        Section {
            Button {
                fetchModels()
            } label: {
                HStack {
                    Label(L10n.Provider.fetchFromAPI, systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if isFetchingModels {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(endpoint.isEmpty || isFetchingModels)

            if let error = fetchError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let cachedDate = existingProvider?.cachedModelListDate {
                Text("Last fetched: \(cachedDate, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !fetchedModels.isEmpty {
                let notEnabled = fetchedModels.filter { !enabledModels.contains($0) }
                if !notEnabled.isEmpty {
                    DisclosureGroup(L10n.Provider.availableToEnable(notEnabled.count)) {
                        ForEach(notEnabled, id: \.self) { model in
                            HStack {
                                Text(model)
                                    .font(.subheadline)
                                Spacer()
                                Button {
                                    enableModel(model)
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.green)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    Text(L10n.Provider.allModelsEnabled(fetchedModels.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(L10n.Provider.enableAll) {
                    for m in fetchedModels {
                        enableModel(m)
                    }
                }
                .font(.subheadline)
            }
        } header: {
            Text(L10n.Provider.remoteModels)
        } footer: {
            Text(L10n.Provider.remoteModelsFooter)
        }
    }

    private var anyModelHasThinking: Bool {
        modelCapabilities.values.contains { $0.thinkingLevel.isEnabled }
    }

    private var parametersSection: some View {
        Section {
            Stepper(L10n.Provider.maxTokens(maxTokens), value: $maxTokens, in: 256...128000, step: 256)
            HStack {
                Text(L10n.Provider.temperature(temperature))
                Slider(value: $temperature, in: 0...2, step: 0.05)
            }
        } header: {
            Text(L10n.Provider.parameters)
        } footer: {
            Text(L10n.Provider.parametersFooter)
        }
    }

    private var presetsSection: some View {
        Section(L10n.Provider.presets) {
            Button("OpenAI") {
                endpoint = "https://api.openai.com/v1"
                modelName = "gpt-5.4"
                apiStyle = .openAI
                enableModel("gpt-5.4")
            }
            Button("Anthropic") {
                endpoint = "https://api.anthropic.com/v1"
                modelName = "claude-sonnet-4-6"
                apiStyle = .anthropic
                enableModel("claude-sonnet-4-6")
                modelCapabilities["claude-sonnet-4-6"]?.thinkingLevel = .medium
                modelCapabilities["claude-sonnet-4-6"]?.supportsReasoning = true
            }
            Button("DeepSeek") {
                endpoint = "https://api.deepseek.com/v1"
                modelName = "deepseek-chat"
                apiStyle = .openAI
                enableModel("deepseek-chat")
            }
            Button("OpenRouter") {
                endpoint = "https://openrouter.ai/api/v1"
                modelName = "anthropic/claude-sonnet-4.6"
                apiStyle = .openAI
                enableModel("anthropic/claude-sonnet-4.6")
                enableModel("openai/gpt-5.4")
            }
            Button("Local (Ollama)") {
                endpoint = "http://localhost:11434/v1"
                modelName = "llama3"
                apiKey = "ollama"
                apiStyle = .openAI
                enableModel("llama3")
            }
        }
    }

    // MARK: - Actions

    /// Insert model into enabled set and auto-infer capabilities if not already configured.
    private func enableModel(_ model: String) {
        enabledModels.insert(model)
        if modelCapabilities[model] == nil {
            modelCapabilities[model] = ModelCapabilities.inferred(from: model)
        }
    }

    private func save() {
        enableModel(modelName)

        // Encode capabilities JSON directly to avoid computed property setter issues with SwiftData
        let capsJSON: String? = {
            guard !modelCapabilities.isEmpty,
                  let data = try? JSONEncoder().encode(modelCapabilities),
                  let json = String(data: data, encoding: .utf8)
            else { return nil }
            return json
        }()

        let defaultCaps = modelCapabilities[modelName] ?? .default

        if let p = existingProvider {
            p.name = name
            p.endpoint = endpoint
            p.apiKey = apiKey
            p.modelName = modelName
            p.maxTokens = maxTokens
            p.thinkingBudget = thinkingBudget
            p.temperature = temperature
            // Write raw stored properties directly (not through computed setters)
            p.apiStyleRaw = apiStyle.rawValue
            p.modelCapabilitiesJSON = capsJSON
            p.enabledModels = Array(enabledModels)
            p.cachedModelList = fetchedModels

            // Sync legacy flags from default model for backward compatibility
            p.supportsVision = defaultCaps.supportsVision
            p.supportsToolUse = defaultCaps.supportsToolUse
            p.supportsImageGeneration = defaultCaps.supportsImageGeneration

            viewModel.updateProvider(p)
        } else {
            let provider = LLMProvider(
                name: name,
                endpoint: endpoint,
                apiKey: apiKey,
                modelName: modelName,
                isDefault: viewModel.providers.isEmpty,
                maxTokens: maxTokens,
                temperature: temperature
            )
            // Write raw stored properties directly
            provider.thinkingBudget = thinkingBudget
            provider.apiStyleRaw = apiStyle.rawValue
            provider.modelCapabilitiesJSON = capsJSON

            provider.supportsVision = defaultCaps.supportsVision
            provider.supportsToolUse = defaultCaps.supportsToolUse
            provider.supportsImageGeneration = defaultCaps.supportsImageGeneration

            provider.enabledModels = Array(enabledModels)
            provider.cachedModelList = fetchedModels
            viewModel.addProviderDirectly(provider)
        }
    }

    private func fetchModels() {
        isFetchingModels = true
        fetchError = nil

        Task {
            do {
                let models = try await LLMService.fetchModels(
                    endpoint: endpoint,
                    apiKey: apiKey,
                    apiStyle: apiStyle
                )
                await MainActor.run {
                    fetchedModels = models
                    enableModel(modelName)
                    isFetchingModels = false

                    if let p = existingProvider {
                        p.cachedModelList = models
                        p.cachedModelListDate = Date()
                        try? viewModel.modelContext.save()
                    }
                }
            } catch {
                await MainActor.run {
                    fetchError = error.localizedDescription
                    isFetchingModels = false
                }
            }
        }
    }
}

/// Helper to bundle multiple Bool bindings for model capabilities.
private struct CapabilitiesBindings {
    let supportsVision: Binding<Bool>
    let supportsToolUse: Binding<Bool>
    let imageGenerationMode: Binding<ImageGenMode>
}
