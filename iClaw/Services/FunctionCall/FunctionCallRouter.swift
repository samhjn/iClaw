import Foundation
import SwiftData

final class FunctionCallRouter {
    let agent: Agent
    let modelContext: ModelContext
    private let agentService: AgentService
    private let subAgentManager: SubAgentManager
    private let executor: CodeExecutor

    init(agent: Agent, modelContext: ModelContext, executor: CodeExecutor? = nil) {
        self.agent = agent
        self.modelContext = modelContext
        self.agentService = AgentService(modelContext: modelContext)
        self.subAgentManager = SubAgentManager(modelContext: modelContext)
        self.executor = executor ?? CodeExecutorRegistry.shared.defaultExecutor()
    }

    func execute(toolCall: LLMToolCall) async -> String {
        let name = toolCall.function.name
        let arguments = parseArguments(toolCall.function.arguments)

        switch name {
        case "read_config":
            return ConfigTools(agentService: agentService, agent: agent)
                .readConfig(arguments: arguments)

        case "write_config":
            return ConfigTools(agentService: agentService, agent: agent)
                .writeConfig(arguments: arguments)

        case "execute_python":
            let tools = CodeExecutionTools(agent: agent, modelContext: modelContext, executor: executor)
            return await tools.executePython(arguments: arguments)

        case "execute_javascript":
            let tools = CodeExecutionTools(agent: agent, modelContext: modelContext, executor: executor)
            return await tools.executeJavaScript(arguments: arguments)

        case "save_code":
            return CodeExecutionTools(agent: agent, modelContext: modelContext, executor: executor)
                .saveCode(arguments: arguments)

        case "load_code":
            return CodeExecutionTools(agent: agent, modelContext: modelContext, executor: executor)
                .loadCode(arguments: arguments)

        case "list_code":
            return CodeExecutionTools(agent: agent, modelContext: modelContext, executor: executor)
                .listCode()

        case "create_sub_agent":
            return SubAgentTools(agent: agent, modelContext: modelContext, subAgentManager: subAgentManager)
                .createSubAgent(arguments: arguments)

        case "message_sub_agent":
            return await SubAgentTools(agent: agent, modelContext: modelContext, subAgentManager: subAgentManager)
                .messageSubAgent(arguments: arguments)

        case "collect_sub_agent_output":
            return SubAgentTools(agent: agent, modelContext: modelContext, subAgentManager: subAgentManager)
                .collectSubAgentOutput(arguments: arguments)

        case "list_sub_agents":
            return SubAgentTools(agent: agent, modelContext: modelContext, subAgentManager: subAgentManager)
                .listSubAgents(arguments: arguments)

        case "stop_sub_agent":
            return SubAgentTools(agent: agent, modelContext: modelContext, subAgentManager: subAgentManager)
                .stopSubAgent(arguments: arguments)

        case "delete_sub_agent":
            return SubAgentTools(agent: agent, modelContext: modelContext, subAgentManager: subAgentManager)
                .deleteSubAgent(arguments: arguments)

        case "schedule_cron":
            return CronTools(agent: agent, modelContext: modelContext)
                .scheduleCron(arguments: arguments)

        case "unschedule_cron":
            return CronTools(agent: agent, modelContext: modelContext)
                .unscheduleCron(arguments: arguments)

        case "list_cron":
            return CronTools(agent: agent, modelContext: modelContext)
                .listCron()

        case "create_skill":
            return SkillTools(agent: agent, modelContext: modelContext)
                .createSkill(arguments: arguments)

        case "delete_skill":
            return SkillTools(agent: agent, modelContext: modelContext)
                .deleteSkill(arguments: arguments)

        case "install_skill":
            return SkillTools(agent: agent, modelContext: modelContext)
                .installSkill(arguments: arguments)

        case "uninstall_skill":
            return SkillTools(agent: agent, modelContext: modelContext)
                .uninstallSkill(arguments: arguments)

        case "list_skills":
            return SkillTools(agent: agent, modelContext: modelContext)
                .listSkills(arguments: arguments)

        case "read_skill":
            return SkillTools(agent: agent, modelContext: modelContext)
                .readSkill(arguments: arguments)

        case "set_model":
            return ModelTools(agent: agent, modelContext: modelContext)
                .setModel(arguments: arguments)

        case "get_model":
            return ModelTools(agent: agent, modelContext: modelContext)
                .getModel(arguments: arguments)

        case "list_models":
            return ModelTools(agent: agent, modelContext: modelContext)
                .listModels(arguments: arguments)

        default:
            return "[Error] Unknown tool: \(name)"
        }
    }

    private func parseArguments(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }
}
