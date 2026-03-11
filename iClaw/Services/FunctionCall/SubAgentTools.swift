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

        let (subAgent, _) = subAgentManager.createSubAgent(
            name: name,
            parentAgent: agent,
            initialContext: initialContext,
            providerIdOverride: providerIdOverride
        )

        let router = ModelRouter(modelContext: modelContext)
        let modelInfo = router.primaryProvider(for: subAgent)
            .map { "\($0.name) (\($0.modelName))" } ?? "inherited"

        return """
        Sub-agent created successfully.
        - Name: \(subAgent.name)
        - ID: \(subAgent.id.uuidString)
        - Model: \(modelInfo)
        - Inherited SOUL from parent agent
        - Use `message_sub_agent` with agent_id "\(subAgent.id.uuidString)" to communicate
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
}
