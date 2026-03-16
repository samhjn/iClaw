import Foundation
import SwiftData

final class FunctionCallRouter {
    let agent: Agent
    let modelContext: ModelContext
    let sessionId: UUID?
    private let agentService: AgentService
    private let subAgentManager: SubAgentManager

    init(agent: Agent, modelContext: ModelContext, sessionId: UUID? = nil) {
        self.agent = agent
        self.modelContext = modelContext
        self.sessionId = sessionId
        self.agentService = AgentService(modelContext: modelContext)
        self.subAgentManager = SubAgentManager(modelContext: modelContext)
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

        case "execute_javascript":
            let tools = CodeExecutionTools(agent: agent, modelContext: modelContext)
            return await tools.executeJavaScript(arguments: arguments)

        case "save_code":
            return CodeExecutionTools(agent: agent, modelContext: modelContext)
                .saveCode(arguments: arguments)

        case "load_code":
            return CodeExecutionTools(agent: agent, modelContext: modelContext)
                .loadCode(arguments: arguments)

        case "list_code":
            return CodeExecutionTools(agent: agent, modelContext: modelContext)
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

        case "browser_navigate":
            return await browserTools.navigate(arguments: arguments)

        case "browser_get_page_info":
            return await browserTools.getPageInfo(arguments: arguments)

        case "browser_click":
            return await browserTools.click(arguments: arguments)

        case "browser_input":
            return await browserTools.input(arguments: arguments)

        case "browser_select":
            return await browserTools.select(arguments: arguments)

        case "browser_extract":
            return await browserTools.extract(arguments: arguments)

        case "browser_execute_js":
            return await browserTools.executeJS(arguments: arguments)

        case "browser_wait":
            return await browserTools.waitForElement(arguments: arguments)

        case "browser_scroll":
            return await browserTools.scroll(arguments: arguments)

        default:
            return "[Error] Unknown tool: \(name)"
        }
    }

    private var browserTools: BrowserTools {
        BrowserTools(sessionId: sessionId ?? agent.id, agentName: agent.name)
    }

    private func parseArguments(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }
}
