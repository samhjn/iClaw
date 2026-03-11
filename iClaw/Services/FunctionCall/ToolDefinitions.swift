import Foundation

enum ToolDefinitions {
    static var allTools: [LLMToolDefinition] {
        [
            readConfigTool,
            writeConfigTool,
            executePythonTool,
            saveCodeTool,
            loadCodeTool,
            listCodeTool,
            createSubAgentTool,
            messageSubAgentTool,
            scheduleCronTool,
            unscheduleCronTool,
            listCronTool,
            createSkillTool,
            deleteSkillTool,
            installSkillTool,
            uninstallSkillTool,
            listSkillsTool,
            readSkillTool,
            setModelTool,
            getModelTool,
            listModelsTool,
        ]
    }

    static let readConfigTool = ToolDefinitionBuilder.build(
        name: "read_config",
        description: "Read a configuration file from the agent's config space. Available keys: SOUL.md, MEMORY.md, USER.md, or any custom config key.",
        properties: [
            "key": ToolDefinitionBuilder.stringParam("The config key to read (e.g. 'SOUL.md', 'MEMORY.md', 'USER.md', or a custom key)")
        ],
        required: ["key"]
    )

    static let writeConfigTool = ToolDefinitionBuilder.build(
        name: "write_config",
        description: "Write or update a configuration file in the agent's config space. Use this to persist knowledge, update memory, or modify personality.",
        properties: [
            "key": ToolDefinitionBuilder.stringParam("The config key to write (e.g. 'SOUL.md', 'MEMORY.md', 'USER.md', or a custom key)"),
            "content": ToolDefinitionBuilder.stringParam("The full markdown content to write")
        ],
        required: ["key", "content"]
    )

    static let executePythonTool = ToolDefinitionBuilder.build(
        name: "execute_python",
        description: "Execute Python code. In 'repr' mode, evaluates an expression and returns its repr(). In 'script' mode, runs a script and captures stdout/stderr.",
        properties: [
            "code": ToolDefinitionBuilder.stringParam("The Python code to execute"),
            "mode": ToolDefinitionBuilder.enumParam("Execution mode", values: ["repr", "script"])
        ],
        required: ["code"]
    )

    static let saveCodeTool = ToolDefinitionBuilder.build(
        name: "save_code",
        description: "Save a code snippet to the agent's config space for later reuse.",
        properties: [
            "name": ToolDefinitionBuilder.stringParam("A descriptive name for the code snippet"),
            "language": ToolDefinitionBuilder.stringParam("The programming language (e.g. 'python', 'javascript')"),
            "code": ToolDefinitionBuilder.stringParam("The code content to save")
        ],
        required: ["name", "code"]
    )

    static let loadCodeTool = ToolDefinitionBuilder.build(
        name: "load_code",
        description: "Load a previously saved code snippet by name.",
        properties: [
            "name": ToolDefinitionBuilder.stringParam("The name of the code snippet to load")
        ],
        required: ["name"]
    )

    static let listCodeTool = ToolDefinitionBuilder.build(
        name: "list_code",
        description: "List all saved code snippets with their names and languages.",
        properties: [:],
        required: []
    )

    static let createSubAgentTool = ToolDefinitionBuilder.build(
        name: "create_sub_agent",
        description: "Create a new sub-agent that inherits your configuration space. The sub-agent will have your SOUL but starts with empty MEMORY. Optionally specify a model_id to use a different LLM model for the sub-agent.",
        properties: [
            "name": ToolDefinitionBuilder.stringParam("A descriptive name for the sub-agent"),
            "initial_context": ToolDefinitionBuilder.stringParam("Context and instructions for the sub-agent's task"),
            "model_id": ToolDefinitionBuilder.stringParam("Optional: UUID of the LLM provider to use for this sub-agent. Use list_models to see available providers.")
        ],
        required: ["name"]
    )

    static let messageSubAgentTool = ToolDefinitionBuilder.build(
        name: "message_sub_agent",
        description: "Send a message to an active sub-agent and receive its response.",
        properties: [
            "agent_id": ToolDefinitionBuilder.stringParam("The UUID of the sub-agent to message"),
            "message": ToolDefinitionBuilder.stringParam("The message to send to the sub-agent")
        ],
        required: ["agent_id", "message"]
    )

    // MARK: - Cron Job Tools

    static let scheduleCronTool = ToolDefinitionBuilder.build(
        name: "schedule_cron",
        description: "Schedule a recurring cron job. At each trigger time, a new session is automatically created and the job hint is sent to the LLM. Uses standard 5-field cron syntax (minute hour day-of-month month day-of-week). Also accepts presets: @hourly, @daily, @weekly, @monthly, @yearly.",
        properties: [
            "name": ToolDefinitionBuilder.stringParam("A descriptive name for the cron job"),
            "cron_expression": ToolDefinitionBuilder.stringParam("Cron schedule expression, e.g. '0 9 * * 1-5' for weekdays at 9am, or '@daily'"),
            "job_hint": ToolDefinitionBuilder.stringParam("The prompt/instruction that will be sent to the LLM when the job triggers"),
            "enabled": ToolDefinitionBuilder.boolParam("Whether the job starts enabled (default: true)")
        ],
        required: ["name", "cron_expression", "job_hint"]
    )

    static let unscheduleCronTool = ToolDefinitionBuilder.build(
        name: "unschedule_cron",
        description: "Disable or delete an existing cron job.",
        properties: [
            "job_id": ToolDefinitionBuilder.stringParam("The UUID of the cron job to disable/delete"),
            "delete": ToolDefinitionBuilder.boolParam("If true, permanently delete the job. If false (default), just disable it.")
        ],
        required: ["job_id"]
    )

    static let listCronTool = ToolDefinitionBuilder.build(
        name: "list_cron",
        description: "List all cron jobs configured for this agent, including their schedules, status, and run history.",
        properties: [:],
        required: []
    )

    // MARK: - Skill Tools

    static let createSkillTool = ToolDefinitionBuilder.build(
        name: "create_skill",
        description: "Create a new reusable skill in the skill library. A skill is a markdown document that provides specialized instructions, knowledge, or methodology. Once created, it can be installed on any agent.",
        properties: [
            "name": ToolDefinitionBuilder.stringParam("A unique name for the skill"),
            "summary": ToolDefinitionBuilder.stringParam("A brief one-line description of what the skill does"),
            "content": ToolDefinitionBuilder.stringParam("The full markdown content with instructions, methodology, or knowledge"),
            "tags": ToolDefinitionBuilder.stringParam("Comma-separated tags for categorization (e.g. 'coding,review,quality')")
        ],
        required: ["name", "content"]
    )

    static let deleteSkillTool = ToolDefinitionBuilder.build(
        name: "delete_skill",
        description: "Permanently delete a skill from the library. Built-in skills cannot be deleted. Identify the skill by name or ID.",
        properties: [
            "name": ToolDefinitionBuilder.stringParam("The name of the skill to delete"),
            "skill_id": ToolDefinitionBuilder.stringParam("The UUID of the skill to delete (alternative to name)")
        ],
        required: []
    )

    static let installSkillTool = ToolDefinitionBuilder.build(
        name: "install_skill",
        description: "Install a skill from the library onto the current agent. Once installed, the skill's content is included in the agent's system prompt.",
        properties: [
            "name": ToolDefinitionBuilder.stringParam("The name of the skill to install"),
            "skill_id": ToolDefinitionBuilder.stringParam("The UUID of the skill to install (alternative to name)")
        ],
        required: []
    )

    static let uninstallSkillTool = ToolDefinitionBuilder.build(
        name: "uninstall_skill",
        description: "Uninstall a skill from the current agent. The skill remains in the library for future use.",
        properties: [
            "name": ToolDefinitionBuilder.stringParam("The name of the skill to uninstall"),
            "skill_id": ToolDefinitionBuilder.stringParam("The UUID of the skill to uninstall (alternative to name)")
        ],
        required: []
    )

    static let listSkillsTool = ToolDefinitionBuilder.build(
        name: "list_skills",
        description: "List skills. Use scope='installed' to see only skills installed on this agent, or scope='library' to browse all available skills. Optionally filter by query.",
        properties: [
            "scope": ToolDefinitionBuilder.enumParam("Which skills to list", values: ["installed", "library", "all"]),
            "query": ToolDefinitionBuilder.stringParam("Optional search query to filter skills by name, summary, or tags")
        ],
        required: []
    )

    static let readSkillTool = ToolDefinitionBuilder.build(
        name: "read_skill",
        description: "Read the full content of a skill, including its instructions and metadata.",
        properties: [
            "name": ToolDefinitionBuilder.stringParam("The name of the skill to read"),
            "skill_id": ToolDefinitionBuilder.stringParam("The UUID of the skill to read (alternative to name)")
        ],
        required: []
    )

    // MARK: - Model Tools

    static let setModelTool = ToolDefinitionBuilder.build(
        name: "set_model",
        description: "Configure model settings for this agent. Roles: 'primary' sets the main model, 'fallback' replaces the entire fallback chain, 'add_fallback' appends one model to the chain, 'sub_agent' sets the default model for sub-agents.",
        properties: [
            "role": ToolDefinitionBuilder.enumParam("Which model slot to configure", values: ["primary", "fallback", "add_fallback", "sub_agent"]),
            "model_id": ToolDefinitionBuilder.stringParam("UUID of the LLM provider to set. Use list_models to see available providers."),
            "model_ids": .init(type: "array", description: "Array of provider UUIDs (for 'fallback' role to set the entire chain)", items: .init(type: "string", description: nil))
        ],
        required: ["role"]
    )

    static let getModelTool = ToolDefinitionBuilder.build(
        name: "get_model",
        description: "Get the current model configuration for this agent, including primary model, fallback chain, and sub-agent default.",
        properties: [:],
        required: []
    )

    static let listModelsTool = ToolDefinitionBuilder.build(
        name: "list_models",
        description: "List all available LLM providers/models that can be assigned to agents.",
        properties: [:],
        required: []
    )
}
