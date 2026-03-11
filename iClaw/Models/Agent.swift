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
    /// Comma-separated UUIDs of fallback providers in priority order
    var fallbackProviderIdsRaw: String?
    /// UUID of the default provider for sub-agents (nil = inherit from self)
    var subAgentProviderIdRaw: String?

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

    var subAgentProviderId: UUID? {
        get { subAgentProviderIdRaw.flatMap { UUID(uuidString: $0) } }
        set { subAgentProviderIdRaw = newValue?.uuidString }
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
        self.fallbackProviderIdsRaw = nil
        self.subAgentProviderIdRaw = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
