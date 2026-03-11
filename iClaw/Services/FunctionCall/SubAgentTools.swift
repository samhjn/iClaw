import Foundation
import SwiftData

struct SubAgentTools {
    let agent: Agent
    let modelContext: ModelContext
    let subAgentManager: SubAgentManager

    func createSubAgent(arguments: [String: Any]) -> String {
        guard let name = arguments["name"] as? String else {
            return "[Error] Missing required parameter: name"
        }

        let initialContext = arguments["initial_context"] as? String
        var providerIdOverride: UUID?
        if let modelIdStr = arguments["model_id"] as? String {
            providerIdOverride = UUID(uuidString: modelIdStr)
        }

        let typeStr = arguments["type"] as? String ?? "temp"
        let type: SubAgentType = typeStr == "persistent" ? .persistent : .temp

        // Find the current session to link as parent
        let parentSessionId = agent.sessions.last?.id

        let (subAgent, _) = subAgentManager.createSubAgent(
            name: name,
            parentAgent: agent,
            initialContext: initialContext,
            providerIdOverride: providerIdOverride,
            type: type,
            parentSessionId: parentSessionId
        )

        let router = ModelRouter(modelContext: modelContext)
        let modelInfo = router.primaryProvider(for: subAgent)
            .map { "\($0.name) (\($0.modelName))" } ?? "inherited"

        let typeLabel = type == .persistent ? "persistent (long-lived)" : "temp (auto-destroy after task)"

        return """
        Sub-agent created successfully.
        - Name: \(subAgent.name)
        - ID: \(subAgent.id.uuidString)
        - Type: \(typeLabel)
        - Model: \(modelInfo)
        - Inherited SOUL from parent agent
        - Use `message_sub_agent` with agent_id "\(subAgent.id.uuidString)" to communicate
        - Use `collect_sub_agent_output` to retrieve its session content
        \(type == .temp ? "- This agent will be auto-destroyed after you collect its output" : "- This agent persists and can be reused across sessions")
        """
    }

    @MainActor
    func messageSubAgent(arguments: [String: Any]) async -> String {
        guard let agentIdStr = arguments["agent_id"] as? String,
              let agentId = UUID(uuidString: agentIdStr) else {
            return "[Error] Missing or invalid agent_id parameter"
        }
        guard let message = arguments["message"] as? String else {
            return "[Error] Missing required parameter: message"
        }

        do {
            let response = try await subAgentManager.sendMessage(
                to: agentId,
                content: message
            )
            return response
        } catch {
            return "[Error] \(error.localizedDescription)"
        }
    }

    func collectSubAgentOutput(arguments: [String: Any]) -> String {
        guard let agentIdStr = arguments["agent_id"] as? String,
              let agentId = UUID(uuidString: agentIdStr) else {
            return "[Error] Missing or invalid agent_id parameter"
        }

        let mode = arguments["mode"] as? String ?? "summary"
        let autoDestroy = arguments["auto_destroy"] as? Bool ?? true

        let output: String
        if mode == "full" {
            output = subAgentManager.collectFullTranscript(subAgentId: agentId)
        } else {
            output = subAgentManager.collectSessionSummary(subAgentId: agentId)
        }

        // Auto-destroy temp agents after collecting output
        if autoDestroy {
            let agentService = AgentService(modelContext: modelContext)
            if let subAgent = agentService.fetchAgent(id: agentId), subAgent.isTempSubAgent {
                subAgentManager.destroyTempAgent(agentId)
            }
        }

        return output
    }

    func listSubAgents(arguments: [String: Any]) -> String {
        let allSessions = subAgentManager.allSubAgentSessions(for: agent)

        if allSessions.isEmpty && agent.subAgents.isEmpty {
            return "(No sub-agents)"
        }

        var lines: [String] = []
        for sub in agent.subAgents {
            let typeLabel = sub.subAgentType ?? "unknown"
            let sessionInfo = allSessions.first(where: { $0.agent.id == sub.id })
            let statusLabel = sessionInfo?.isActive == true ? "🟢 active" : "⚪ idle"
            let msgCount = sessionInfo?.session.messages.count ?? 0

            lines.append("""
            - **\(sub.name)** [\(typeLabel)] \(statusLabel)
              ID: \(sub.id.uuidString)
              Messages: \(msgCount)
            """)
        }
        return lines.joined(separator: "\n")
    }

    func stopSubAgent(arguments: [String: Any]) -> String {
        guard let agentIdStr = arguments["agent_id"] as? String,
              let agentId = UUID(uuidString: agentIdStr) else {
            return "[Error] Missing or invalid agent_id parameter"
        }

        subAgentManager.forceStop(subAgentId: agentId)
        return "Sub-agent session force-stopped."
    }

    func deleteSubAgent(arguments: [String: Any]) -> String {
        guard let agentIdStr = arguments["agent_id"] as? String,
              let agentId = UUID(uuidString: agentIdStr) else {
            return "[Error] Missing or invalid agent_id parameter"
        }

        subAgentManager.deletePersistentAgent(agentId)
        return "Sub-agent deleted."
    }
}
