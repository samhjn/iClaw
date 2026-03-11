import Foundation
import SwiftData

@Model
final class LLMProvider {
    var id: UUID
    var name: String
    var endpoint: String
    var apiKey: String
    var modelName: String
    var isDefault: Bool
    var maxTokens: Int
    var temperature: Double
    var createdAt: Date

    /// All model names enabled for this provider (in addition to modelName).
    /// Stored as comma-separated string for SwiftData compatibility.
    var enabledModelsRaw: String?

    /// Cached model list fetched from the API.
    /// Stored as comma-separated string.
    var cachedModelListRaw: String?

    /// When the model list was last fetched.
    var cachedModelListDate: Date?

    // MARK: - Computed

    var enabledModels: [String] {
        get {
            var models = Set<String>()
            models.insert(modelName)
            if let raw = enabledModelsRaw, !raw.isEmpty {
                raw.components(separatedBy: "|||").forEach { models.insert($0) }
            }
            return Array(models).sorted()
        }
        set {
            let filtered = newValue.filter { $0 != modelName }
            enabledModelsRaw = filtered.isEmpty ? nil : filtered.joined(separator: "|||")
        }
    }

    var cachedModelList: [String] {
        get {
            guard let raw = cachedModelListRaw, !raw.isEmpty else { return [] }
            return raw.components(separatedBy: "|||")
        }
        set {
            cachedModelListRaw = newValue.isEmpty ? nil : newValue.joined(separator: "|||")
        }
    }

    init(
        name: String,
        endpoint: String = "https://api.openai.com/v1",
        apiKey: String = "",
        modelName: String = "gpt-4o",
        isDefault: Bool = false,
        maxTokens: Int = 4096,
        temperature: Double = 0.7
    ) {
        self.id = UUID()
        self.name = name
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.modelName = modelName
        self.isDefault = isDefault
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.createdAt = Date()
        self.enabledModelsRaw = nil
        self.cachedModelListRaw = nil
        self.cachedModelListDate = nil
    }
}
