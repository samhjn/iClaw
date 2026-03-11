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

    private var isEditing: Bool { existingProvider != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    TextField("Name", text: $name)
                    TextField("Endpoint", text: $endpoint)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                }

                Section("Authentication") {
                    SecureField("API Key", text: $apiKey)
                        .autocapitalization(.none)
                }

                Section("Model") {
                    TextField("Model Name", text: $modelName)
                        .autocapitalization(.none)
                    Stepper("Max Tokens: \(maxTokens)", value: $maxTokens, in: 256...128000, step: 256)
                    HStack {
                        Text("Temperature: \(temperature, specifier: "%.2f")")
                        Slider(value: $temperature, in: 0...2, step: 0.05)
                    }
                }

                Section("Presets") {
                    Button("OpenAI") {
                        endpoint = "https://api.openai.com/v1"
                        modelName = "gpt-4o"
                    }
                    Button("DeepSeek") {
                        endpoint = "https://api.deepseek.com/v1"
                        modelName = "deepseek-chat"
                    }
                    Button("OpenRouter") {
                        endpoint = "https://openrouter.ai/api/v1"
                        modelName = "openai/gpt-4o"
                    }
                    Button("Local (Ollama)") {
                        endpoint = "http://localhost:11434/v1"
                        modelName = "llama3"
                        apiKey = "ollama"
                    }
                }
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
        }
        .onAppear {
            if let p = existingProvider {
                name = p.name
                endpoint = p.endpoint
                apiKey = p.apiKey
                modelName = p.modelName
                maxTokens = p.maxTokens
                temperature = p.temperature
            }
        }
    }

    private func save() {
        if let p = existingProvider {
            p.name = name
            p.endpoint = endpoint
            p.apiKey = apiKey
            p.modelName = modelName
            p.maxTokens = maxTokens
            p.temperature = temperature
            viewModel.updateProvider(p)
        } else {
            viewModel.addProvider(
                name: name,
                endpoint: endpoint,
                apiKey: apiKey,
                modelName: modelName
            )
        }
    }
}
