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
            .navigationTitle(isEditing ? "Edit Provider" : "Add Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(name.isEmpty || endpoint.isEmpty || modelName.isEmpty)
                }
            }
            .alert("Add Model", isPresented: $showAddModel) {
                TextField("Model name (e.g. gpt-4o-mini)", text: $newModelName)
                    .autocapitalization(.none)
                Button("Add") {
                    let trimmed = newModelName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        enabledModels.insert(trimmed)
                    }
                    newModelName = ""
                }
                Button("Cancel", role: .cancel) { newModelName = "" }
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
                enabledModels = Set(p.enabledModels)
                fetchedModels = p.cachedModelList
            } else {
                enabledModels = [modelName]
            }
        }
    }

    // MARK: - Sections

    private var providerSection: some View {
        Section("Provider") {
            TextField("Name", text: $name)
            TextField("Endpoint", text: $endpoint)
                .textContentType(.URL)
                .autocapitalization(.none)
                .keyboardType(.URL)
        }
    }

    private var authSection: some View {
        Section("Authentication") {
            SecureField("API Key", text: $apiKey)
                .autocapitalization(.none)
        }
    }

    private var defaultModelSection: some View {
        Section {
            HStack {
                TextField("Default Model", text: $modelName)
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
            Text("Default Model")
        } footer: {
            Text("The default model used when no specific model is selected.")
        }
    }

    private var enabledModelsSection: some View {
        Section {
            if enabledModels.isEmpty {
                Text("No models enabled")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(Array(enabledModels).sorted(), id: \.self) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model)
                                .font(.subheadline)
                            if model == modelName {
                                Text("Default")
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
                                Label("Disable", systemImage: "xmark")
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if model != modelName {
                            Button("Set Default") {
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
                Label("Manually Add Model", systemImage: "plus")
            }
        } header: {
            HStack {
                Text("Enabled Models")
                Spacer()
                Text("\(enabledModels.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Swipe left to disable, swipe right to set as default. Only enabled models appear in agent model selection.")
        }
    }

    private var remoteModelsSection: some View {
        Section {
            Button {
                fetchModels()
            } label: {
                HStack {
                    Label("Fetch from API", systemImage: "arrow.triangle.2.circlepath")
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
                    DisclosureGroup("Available to Enable (\(notEnabled.count))") {
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
                    Text("All \(fetchedModels.count) fetched models are enabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Enable All") {
                    for m in fetchedModels {
                        enabledModels.insert(m)
                    }
                }
                .font(.subheadline)
            }
        } header: {
            Text("Remote Models")
        } footer: {
            Text("Fetch models from the API endpoint, then enable the ones you need.")
        }
    }

    private var parametersSection: some View {
        Section {
            Stepper("Max Tokens: \(maxTokens)", value: $maxTokens, in: 256...128000, step: 256)
            HStack {
                Text("Temperature: \(temperature, specifier: "%.2f")")
                Slider(value: $temperature, in: 0...2, step: 0.05)
            }
        } header: {
            Text("Parameters")
        }
    }

    private var presetsSection: some View {
        Section("Presets") {
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
