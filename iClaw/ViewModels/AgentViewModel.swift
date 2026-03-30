import Foundation
import SwiftData
import Observation

@Observable
final class AgentViewModel {
    var agents: [Agent] = []
    var agentToDelete: Agent?

    private var modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchAgents()
    }

    func fetchAgents() {
        let descriptor = FetchDescriptor<Agent>(
            predicate: #Predicate { $0.parentAgent == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        agents = (try? modelContext.fetch(descriptor)) ?? []
    }

    func createAgent(name: String) -> Agent {
        let soul = DefaultPrompts.defaultSoul
        let memory = DefaultPrompts.defaultMemory
        let user = DefaultPrompts.defaultUser

        let agent = Agent(
            name: name,
            soulMarkdown: soul,
            memoryMarkdown: memory,
            userMarkdown: user
        )
        modelContext.insert(agent)
        try? modelContext.save()
        fetchAgents()
        return agent
    }

    func deleteAgent(_ agent: Agent) {
        let agentId = agent.id
        modelContext.delete(agent)
        try? modelContext.save()
        AgentFileManager.shared.cleanupAgentFiles(agentId: agentId)
        fetchAgents()
    }

    func renameAgent(_ agent: Agent, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        agent.name = trimmed
        updateAgent(agent)
    }

    func updateAgent(_ agent: Agent) {
        agent.updatedAt = Date()
        try? modelContext.save()
        fetchAgents()
    }
}
