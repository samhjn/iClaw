import Foundation
import SwiftData

@Model
final class Agent {
    var id: UUID
    var name: String
    var parentAgent: Agent?
    @Relationship(deleteRule: .cascade, inverse: \Agent.parentAgent)
    var subAgents: [Agent]
    var soulMarkdown: String
    var memoryMarkdown: String
    var userMarkdown: String
    @Relationship(deleteRule: .cascade, inverse: \AgentConfig.agent)
    var customConfigs: [AgentConfig]
    @Relationship(deleteRule: .cascade, inverse: \Session.agent)
    var sessions: [Session]
    @Relationship(deleteRule: .cascade, inverse: \CodeSnippet.agent)
    var codeSnippets: [CodeSnippet]
    @Relationship(deleteRule: .cascade, inverse: \CronJob.agent)
    var cronJobs: [CronJob]
    @Relationship(deleteRule: .cascade, inverse: \InstalledSkill.agent)
    var installedSkills: [InstalledSkill]

    // MARK: - Model configuration

    /// UUID of the primary LLM provider for this agent (nil = use global default)
    var primaryProviderIdRaw: String?
    /// Specific model name override for the primary provider (nil = use provider default)
    var primaryModelNameOverride: String?
    /// Comma-separated UUIDs of fallback providers in priority order
    var fallbackProviderIdsRaw: String?
    /// Comma-separated model name overrides for fallbacks (matching fallbackProviderIds order, empty = use provider default)
    var fallbackModelNamesRaw: String?
    /// UUID of the default provider for sub-agents (nil = inherit from self)
    var subAgentProviderIdRaw: String?
    /// Model name override for sub-agent provider
    var subAgentModelNameOverride: String?

    /// SubAgent lifecycle: "temp" = auto-destroy after task, "persistent" = long-lived, nil = main agent
    var subAgentType: String? = nil

    /// Context compression threshold in tokens (0 = use system default 24000)
    var compressionThreshold: Int = 0

    /// Model whitelist: `|||`-separated `providerId:modelName` pairs.
    /// When non-empty, subagent and agent model selections are restricted to this list.
    var allowedModelIdsRaw: String?

    var createdAt: Date
    var updatedAt: Date

    // MARK: - Computed

    var activeSkills: [InstalledSkill] {
        installedSkills.filter { $0.isEnabled && $0.skill != nil }
    }

    var primaryProviderId: UUID? {
        get { primaryProviderIdRaw.flatMap { UUID(uuidString: $0) } }
        set { primaryProviderIdRaw = newValue?.uuidString }
    }

    var fallbackProviderIds: [UUID] {
        get {
            guard let raw = fallbackProviderIdsRaw, !raw.isEmpty else { return [] }
            return raw.components(separatedBy: ",").compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) }
        }
        set {
            fallbackProviderIdsRaw = newValue.isEmpty ? nil : newValue.map(\.uuidString).joined(separator: ",")
        }
    }

    var fallbackModelNames: [String] {
        get {
            guard let raw = fallbackModelNamesRaw, !raw.isEmpty else { return [] }
            return raw.components(separatedBy: "|||")
        }
        set {
            fallbackModelNamesRaw = newValue.isEmpty ? nil : newValue.joined(separator: "|||")
        }
    }

    var subAgentProviderId: UUID? {
        get { subAgentProviderIdRaw.flatMap { UUID(uuidString: $0) } }
        set { subAgentProviderIdRaw = newValue?.uuidString }
    }

    /// Parsed model whitelist as `["providerId:modelName", ...]`. Empty = allow all.
    var allowedModelIds: [String] {
        get {
            guard let raw = allowedModelIdsRaw, !raw.isEmpty else { return [] }
            return raw.components(separatedBy: "|||").filter { !$0.isEmpty }
        }
        set {
            allowedModelIdsRaw = newValue.isEmpty ? nil : newValue.joined(separator: "|||")
        }
    }

    /// Check whether a specific `providerId:modelName` pair is allowed.
    /// Returns true if the whitelist is empty (allow-all) or the pair is in the list.
    func isModelAllowed(providerId: UUID, modelName: String) -> Bool {
        let list = allowedModelIds
        guard !list.isEmpty else { return true }
        return list.contains("\(providerId.uuidString):\(modelName)")
    }

    init(
        name: String,
        soulMarkdown: String = "",
        memoryMarkdown: String = "",
        userMarkdown: String = "",
        parentAgent: Agent? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.parentAgent = parentAgent
        self.subAgents = []
        self.soulMarkdown = soulMarkdown
        self.memoryMarkdown = memoryMarkdown
        self.userMarkdown = userMarkdown
        self.customConfigs = []
        self.sessions = []
        self.codeSnippets = []
        self.cronJobs = []
        self.installedSkills = []
        self.primaryProviderIdRaw = nil
        self.primaryModelNameOverride = nil
        self.fallbackProviderIdsRaw = nil
        self.fallbackModelNamesRaw = nil
        self.subAgentProviderIdRaw = nil
        self.subAgentModelNameOverride = nil
        self.subAgentType = nil
        self.allowedModelIdsRaw = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var effectiveCompressionThreshold: Int {
        compressionThreshold > 0 ? compressionThreshold : ContextManager.compressionThreshold
    }

    var isTempSubAgent: Bool { subAgentType == "temp" }
    var isPersistentSubAgent: Bool { subAgentType == "persistent" }
    var isSubAgent: Bool { parentAgent != nil }
    var isMainAgent: Bool { parentAgent == nil }
}
