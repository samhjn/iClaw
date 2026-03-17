import SwiftUI

struct LLMProviderEditView: View {
    let viewModel: SettingsViewModel
    var existingProvider: LLMProvider?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var endpoint: String = "https://api.openai.com/v1"
    @State private var apiKey: String = ""
    @State private var modelName: String = "gpt-4o"
    @State private var maxTokens: Int = 4096
    @State private var temperature: Double = 0.7
    @State private var supportsVision: Bool = false
    @State private var supportsToolUse: Bool = true
    @State private var supportsImageGeneration: Bool = false

    @State private var fetchedModels: [String] = []
    @State private var enabledModels: Set<String> = []
    @State private var isFetchingModels = false
    @State private var fetchError: String?

    @State private var showAddModel = false
    @State private var newModelName: String = ""

    private var isEditing: Bool { existingProvider != nil }

    /// All models to display: enabled + fetched, deduplicated, sorted.
    private var allKnownModels: [String] {
        var all = enabledModels
        all.formUnion(fetchedModels)
        return Array(all).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                providerSection
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
                        enabledModels.insert(trimmed)
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
                temperature = p.temperature
                supportsVision = p.supportsVision
                supportsToolUse = p.supportsToolUse
                supportsImageGeneration = p.supportsImageGeneration
                enabledModels = Set(p.enabledModels)
                fetchedModels = p.cachedModelList
            } else {
                enabledModels = [modelName]
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
                                enabledModels.insert(model)
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
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model)
                                .font(.subheadline)
                            if model == modelName {
                                Text(L10n.Common.defaultLabel)
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                        }
                        Spacer()
                        if model == modelName {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if model != modelName {
                            Button(role: .destructive) {
                                enabledModels.remove(model)
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
                                    enabledModels.insert(model)
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
                        enabledModels.insert(m)
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

    private var parametersSection: some View {
        Section {
            Stepper(L10n.Provider.maxTokens(maxTokens), value: $maxTokens, in: 256...128000, step: 256)
            HStack {
                Text("Temperature: \(temperature, specifier: "%.2f")")
                Slider(value: $temperature, in: 0...2, step: 0.05)
            }
            Toggle(L10n.Provider.supportsVision, isOn: $supportsVision)
            Toggle(L10n.Provider.supportsToolUse, isOn: $supportsToolUse)
            Toggle(L10n.Provider.supportsImageGeneration, isOn: $supportsImageGeneration)
        } header: {
            Text(L10n.Provider.parameters)
        } footer: {
            if supportsVision {
                Text(L10n.Provider.supportsVisionFooter)
            }
            if !supportsToolUse {
                Text(L10n.Provider.supportsToolUseFooter)
            }
            if supportsImageGeneration {
                Text(L10n.Provider.supportsImageGenerationFooter)
            }
        }
    }

    private var presetsSection: some View {
        Section(L10n.Provider.presets) {
            Button("OpenAI") {
                endpoint = "https://api.openai.com/v1"
                modelName = "gpt-4o"
                enabledModels.insert("gpt-4o")
            }
            Button("DeepSeek") {
                endpoint = "https://api.deepseek.com/v1"
                modelName = "deepseek-chat"
                enabledModels.insert("deepseek-chat")
            }
            Button("OpenRouter") {
                endpoint = "https://openrouter.ai/api/v1"
                modelName = "openai/gpt-4o"
                enabledModels.insert("openai/gpt-4o")
            }
            Button("Local (Ollama)") {
                endpoint = "http://localhost:11434/v1"
                modelName = "llama3"
                apiKey = "ollama"
                enabledModels.insert("llama3")
            }
        }
    }

    // MARK: - Actions

    private func save() {
        enabledModels.insert(modelName)

        if let p = existingProvider {
            p.name = name
            p.endpoint = endpoint
            p.apiKey = apiKey
            p.modelName = modelName
            p.maxTokens = maxTokens
            p.temperature = temperature
            p.supportsVision = supportsVision
            p.supportsToolUse = supportsToolUse
            p.supportsImageGeneration = supportsImageGeneration
            p.enabledModels = Array(enabledModels)
            p.cachedModelList = fetchedModels
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
            provider.supportsVision = supportsVision
            provider.supportsToolUse = supportsToolUse
            provider.supportsImageGeneration = supportsImageGeneration
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
                    apiKey: apiKey
                )
                await MainActor.run {
                    fetchedModels = models
                    enabledModels.insert(modelName)
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
