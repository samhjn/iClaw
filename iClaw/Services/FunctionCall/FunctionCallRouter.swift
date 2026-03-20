import Foundation
import SwiftData

/// Rich result from a tool call, carrying text and optional multimodal attachments.
struct ToolCallResult {
    let text: String
    let imageAttachments: [ImageAttachment]?

    init(_ text: String, imageAttachments: [ImageAttachment]? = nil) {
        self.text = text
        self.imageAttachments = imageAttachments
    }

    static let cancelled = ToolCallResult("[Cancelled] Operation was cancelled.")
}

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

    // MARK: - Public API

    /// Execute a tool call with automatic cancellation support.
    ///
    /// Cancellation is checked before and after tool execution. Tool implementations
    /// that are cancellation-aware (browser, code execution, sub-agents) will also
    /// respond to cancellation mid-flight. Returns `.cancelled` if interrupted.
    func execute(toolCall: LLMToolCall) async -> ToolCallResult {
        do {
            try Task.checkCancellation()
            let result = try await dispatchTool(toolCall: toolCall)
            try Task.checkCancellation()
            return result
        } catch is CancellationError {
            return .cancelled
        } catch {
            return ToolCallResult("[Error] \(error.localizedDescription)")
        }
    }

    // MARK: - Tool Dispatch

    // ┌──────────────────────────────────────────────────────────────────────┐
    // │  HOW TO ADD A NEW TOOL                                              │
    // │                                                                     │
    // │  1. Synchronous → return ToolCallResult(...) directly.              │
    // │  2. Async, non-throwing → wrap with `runAsync { ... }`.             │
    // │  3. Async, throwing → wrap with `runAsyncThrowing { ... }`          │
    // │     or call directly with `try await` (CancellationError will       │
    // │     propagate automatically).                                       │
    // │  4. Long-running async tools MUST check Task.isCancelled or use     │
    // │     cancellation-aware APIs (withTaskCancellationHandler) internally.│
    // │                                                                     │
    // │  `execute()` guarantees cancellation checks before & after dispatch,│
    // │  `runAsync` / `runAsyncThrowing` add a post-completion check, and   │
    // │  CancellationError from any layer is caught and mapped to           │
    // │  `.cancelled`.                                                      │
    // └──────────────────────────────────────────────────────────────────────┘

    private func dispatchTool(toolCall: LLMToolCall) async throws -> ToolCallResult {
        let name = toolCall.function.name
        let arguments = parseArguments(toolCall.function.arguments)

        switch name {

        // --- Sub-Agent ---
        case "message_sub_agent":
            return try await subAgentTools.messageSubAgent(arguments: arguments)
        case "collect_sub_agent_output":
            return subAgentTools.collectSubAgentOutput(arguments: arguments)
        case "create_sub_agent":
            return ToolCallResult(subAgentTools.createSubAgent(arguments: arguments))
        case "list_sub_agents":
            return ToolCallResult(subAgentTools.listSubAgents(arguments: arguments))
        case "stop_sub_agent":
            return ToolCallResult(subAgentTools.stopSubAgent(arguments: arguments))
        case "delete_sub_agent":
            return ToolCallResult(subAgentTools.deleteSubAgent(arguments: arguments))

        // --- Config ---
        case "read_config":
            return ToolCallResult(
                ConfigTools(agentService: agentService, agent: agent)
                    .readConfig(arguments: arguments))
        case "write_config":
            return ToolCallResult(
                ConfigTools(agentService: agentService, agent: agent)
                    .writeConfig(arguments: arguments))

        // --- Code Execution ---
        case "execute_javascript":
            return try await runAsyncThrowing {
                try await CodeExecutionTools(agent: self.agent, modelContext: self.modelContext)
                    .executeJavaScript(arguments: arguments)
            }
        case "save_code":
            return ToolCallResult(
                CodeExecutionTools(agent: agent, modelContext: modelContext)
                    .saveCode(arguments: arguments))
        case "load_code":
            return ToolCallResult(
                CodeExecutionTools(agent: agent, modelContext: modelContext)
                    .loadCode(arguments: arguments))
        case "list_code":
            return ToolCallResult(
                CodeExecutionTools(agent: agent, modelContext: modelContext)
                    .listCode())

        // --- Cron ---
        case "schedule_cron":
            return ToolCallResult(
                CronTools(agent: agent, modelContext: modelContext)
                    .scheduleCron(arguments: arguments))
        case "unschedule_cron":
            return ToolCallResult(
                CronTools(agent: agent, modelContext: modelContext)
                    .unscheduleCron(arguments: arguments))
        case "list_cron":
            return ToolCallResult(
                CronTools(agent: agent, modelContext: modelContext)
                    .listCron())

        // --- Skills ---
        case "create_skill":
            return ToolCallResult(
                SkillTools(agent: agent, modelContext: modelContext)
                    .createSkill(arguments: arguments))
        case "delete_skill":
            return ToolCallResult(
                SkillTools(agent: agent, modelContext: modelContext)
                    .deleteSkill(arguments: arguments))
        case "install_skill":
            return ToolCallResult(
                SkillTools(agent: agent, modelContext: modelContext)
                    .installSkill(arguments: arguments))
        case "uninstall_skill":
            return ToolCallResult(
                SkillTools(agent: agent, modelContext: modelContext)
                    .uninstallSkill(arguments: arguments))
        case "list_skills":
            return ToolCallResult(
                SkillTools(agent: agent, modelContext: modelContext)
                    .listSkills(arguments: arguments))
        case "read_skill":
            return ToolCallResult(
                SkillTools(agent: agent, modelContext: modelContext)
                    .readSkill(arguments: arguments))

        // --- Model ---
        case "set_model":
            return ToolCallResult(
                ModelTools(agent: agent, modelContext: modelContext)
                    .setModel(arguments: arguments))
        case "get_model":
            return ToolCallResult(
                ModelTools(agent: agent, modelContext: modelContext)
                    .getModel(arguments: arguments))
        case "list_models":
            return ToolCallResult(
                ModelTools(agent: agent, modelContext: modelContext)
                    .listModels(arguments: arguments))

        // --- Browser ---
        case "browser_navigate":
            return try await runAsync { await self.browserTools.navigate(arguments: arguments) }
        case "browser_get_page_info":
            return try await runAsync { await self.browserTools.getPageInfo(arguments: arguments) }
        case "browser_click":
            return try await runAsync { await self.browserTools.click(arguments: arguments) }
        case "browser_input":
            return try await runAsync { await self.browserTools.input(arguments: arguments) }
        case "browser_select":
            return try await runAsync { await self.browserTools.select(arguments: arguments) }
        case "browser_extract":
            return try await runAsync { await self.browserTools.extract(arguments: arguments) }
        case "browser_execute_js":
            return try await runAsync { await self.browserTools.executeJS(arguments: arguments) }
        case "browser_wait":
            return try await runAsync { await self.browserTools.waitForElement(arguments: arguments) }
        case "browser_scroll":
            return try await runAsync { await self.browserTools.scroll(arguments: arguments) }

        default:
            return ToolCallResult("[Error] Unknown tool: \(name)")
        }
    }

    // MARK: - Cancellation Helpers

    /// Wraps a non-throwing async tool. Checks cancellation after the operation completes.
    private func runAsync(_ work: () async -> String) async throws -> ToolCallResult {
        let text = await work()
        try Task.checkCancellation()
        return ToolCallResult(text)
    }

    /// Wraps a throwing async tool. CancellationError propagates naturally from the
    /// underlying operation; also re-checks cancellation after successful completion.
    private func runAsyncThrowing(_ work: () async throws -> String) async throws -> ToolCallResult {
        let text = try await work()
        try Task.checkCancellation()
        return ToolCallResult(text)
    }

    // MARK: - Private

    private var subAgentTools: SubAgentTools {
        SubAgentTools(agent: agent, modelContext: modelContext, subAgentManager: subAgentManager, parentSessionId: sessionId)
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
