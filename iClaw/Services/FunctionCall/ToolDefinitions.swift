import Foundation

enum ToolDefinitions {
    static var allTools: [LLMToolDefinition] {
        [
            readConfigTool,
            writeConfigTool,
            executeJavaScriptTool,
            saveCodeTool,
            loadCodeTool,
            listCodeTool,
            runSnippetTool,
            deleteCodeTool,
            createSubAgentTool,
            messageSubAgentTool,
            collectSubAgentOutputTool,
            listSubAgentsTool,
            stopSubAgentTool,
            deleteSubAgentTool,
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
            browserNavigateTool,
            browserGetPageInfoTool,
            browserClickTool,
            browserInputTool,
            browserSelectTool,
            browserExtractTool,
            browserExecuteJSTool,
            browserWaitTool,
            browserScrollTool,
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

    static let executeJavaScriptTool = ToolDefinitionBuilder.build(
        name: "execute_javascript",
        description: "Execute JavaScript code in a WKWebView sandbox. In 'repr' mode, evaluates an expression and returns its result. In 'script' mode, runs a script and captures console output. Built-in: JSON, Math, Date, RegExp, Map/Set, Array methods, String methods. Network: synchronous fetch(url, options) returning {ok, status, text, json()}. Console: console.log/warn/error captured. Polyfills: TextEncoder/TextDecoder, atob/btoa, setTimeout (runs immediately). Default timeout 60s (max 300s).",
        properties: [
            "code": ToolDefinitionBuilder.stringParam("The JavaScript code to execute"),
            "mode": ToolDefinitionBuilder.enumParam("Execution mode", values: ["repr", "script"]),
            "timeout": ToolDefinitionBuilder.numberParam("Execution timeout in seconds (1-300, default: 60)")
        ],
        required: ["code"]
    )

    static let saveCodeTool = ToolDefinitionBuilder.build(
        name: "save_code",
        description: "Save a code snippet to the agent's config space for later reuse.",
        properties: [
            "name": ToolDefinitionBuilder.stringParam("A descriptive name for the code snippet"),
            "language": ToolDefinitionBuilder.stringParam("The programming language (e.g. 'javascript')"),
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

    static let runSnippetTool = ToolDefinitionBuilder.build(
        name: "run_snippet",
        description: "Execute a saved code snippet by name. Loads the snippet and runs it directly in the appropriate runtime (currently JavaScript only). Supports optional argument overrides for mode and timeout.",
        properties: [
            "name": ToolDefinitionBuilder.stringParam("The name of the saved code snippet to execute"),
            "mode": ToolDefinitionBuilder.enumParam("Execution mode override", values: ["repr", "script"]),
            "timeout": ToolDefinitionBuilder.numberParam("Execution timeout in seconds (1-300, default: 60)")
        ],
        required: ["name"]
    )

    static let deleteCodeTool = ToolDefinitionBuilder.build(
        name: "delete_code",
        description: "Delete a saved code snippet by name.",
        properties: [
            "name": ToolDefinitionBuilder.stringParam("The name of the code snippet to delete")
        ],
        required: ["name"]
    )

    static let createSubAgentTool = ToolDefinitionBuilder.build(
        name: "create_sub_agent",
        description: "Create a sub-agent that can work on tasks independently. Returns an agent_id (UUID) you must use with message_sub_agent to communicate. Type 'temp' (default) auto-destroys after output collection; 'persistent' lives across sessions.",
        properties: [
            "name": ToolDefinitionBuilder.stringParam("A short descriptive name for the sub-agent"),
            "initial_context": ToolDefinitionBuilder.stringParam("Task description and background context for the sub-agent"),
            "model_id": ToolDefinitionBuilder.stringParam("UUID of an LLM provider (from list_models). Optional."),
            "model_name": ToolDefinitionBuilder.stringParam("Model name on the provider (e.g. 'gpt-4o'). Requires model_id. Optional."),
            "type": ToolDefinitionBuilder.enumParam("Agent lifecycle type", values: ["temp", "persistent"])
        ],
        required: ["name"]
    )

    static let messageSubAgentTool = ToolDefinitionBuilder.build(
        name: "message_sub_agent",
        description: "Send a message to an existing sub-agent and wait for its response. The sub-agent processes the message autonomously (including any tool calls) and returns a text reply. Multiple message_sub_agent calls in the same response execute in PARALLEL — use this for concurrent fan-out tasks. You must first create a sub-agent with create_sub_agent to obtain the agent_id.",
        properties: [
            "agent_id": ToolDefinitionBuilder.stringParam("The sub-agent's UUID string, exactly as returned by create_sub_agent (e.g. \"A1B2C3D4-E5F6-7890-ABCD-EF1234567890\")"),
            "message": ToolDefinitionBuilder.stringParam("The text message or instruction to send to the sub-agent"),
            "forward_images": ToolDefinitionBuilder.enumParam("Attach images from the current conversation. Default: none", values: ["none", "latest", "all"])
        ],
        required: ["agent_id", "message"]
    )

    static let collectSubAgentOutputTool = ToolDefinitionBuilder.build(
        name: "collect_sub_agent_output",
        description: "Retrieve a sub-agent's session output. Use after messaging a sub-agent. Mode 'summary' (default) returns assistant replies only; 'full' returns complete transcript. Temp agents are auto-destroyed after collection by default.",
        properties: [
            "agent_id": ToolDefinitionBuilder.stringParam("The sub-agent's UUID string, exactly as returned by create_sub_agent"),
            "mode": ToolDefinitionBuilder.enumParam("Output detail level", values: ["summary", "full"]),
            "auto_destroy": ToolDefinitionBuilder.boolParam("Auto-destroy temp agent after collecting (default: true)")
        ],
        required: ["agent_id"]
    )

    static let listSubAgentsTool = ToolDefinitionBuilder.build(
        name: "list_sub_agents",
        description: "List all sub-agents of this agent with their type, status (active/idle), and message count.",
        properties: [:],
        required: []
    )

    static let stopSubAgentTool = ToolDefinitionBuilder.build(
        name: "stop_sub_agent",
        description: "Force-stop an in-flight sub-agent session. The sub-agent will stop processing and its session becomes idle.",
        properties: [
            "agent_id": ToolDefinitionBuilder.stringParam("The UUID of the sub-agent to stop")
        ],
        required: ["agent_id"]
    )

    static let deleteSubAgentTool = ToolDefinitionBuilder.build(
        name: "delete_sub_agent",
        description: "Permanently delete a sub-agent and all its sessions/data. Works for both temp and persistent agents.",
        properties: [
            "agent_id": ToolDefinitionBuilder.stringParam("The UUID of the sub-agent to delete")
        ],
        required: ["agent_id"]
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
            "model_name": ToolDefinitionBuilder.stringParam("Optional: specific model name on the provider. If omitted, uses the provider's default model."),
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

    // MARK: - Browser Tools

    static let browserNavigateTool = ToolDefinitionBuilder.build(
        name: "browser_navigate",
        description: "Navigate the in-app browser to a URL, or perform back/forward/reload actions. The browser persists across calls — use it for multi-step web automation.",
        properties: [
            "url": ToolDefinitionBuilder.stringParam("The URL to navigate to (e.g. 'https://example.com')"),
            "action": ToolDefinitionBuilder.enumParam("Navigation action instead of URL", values: ["back", "forward", "reload"])
        ],
        required: []
    )

    static let browserGetPageInfoTool = ToolDefinitionBuilder.build(
        name: "browser_get_page_info",
        description: "Get information about the current browser page: URL, title, and optionally a simplified readable representation of the page content (text, links, forms, buttons).",
        properties: [
            "include_content": ToolDefinitionBuilder.boolParam("Include page content (default: false). Set true to read page text, links, and form elements."),
            "simplified": ToolDefinitionBuilder.boolParam("Use simplified DOM extraction (default: true). If false, returns raw HTML.")
        ],
        required: []
    )

    static let browserClickTool = ToolDefinitionBuilder.build(
        name: "browser_click",
        description: "Click an element on the current page by CSS selector. Triggers the element's click event.",
        properties: [
            "selector": ToolDefinitionBuilder.stringParam("CSS selector of the element to click (e.g. '#submit-btn', '.login-button', 'a[href=\"/login\"]')")
        ],
        required: ["selector"]
    )

    static let browserInputTool = ToolDefinitionBuilder.build(
        name: "browser_input",
        description: "Type text into an input field or textarea on the current page. Dispatches input and change events for React/Vue compatibility.",
        properties: [
            "selector": ToolDefinitionBuilder.stringParam("CSS selector of the input element"),
            "text": ToolDefinitionBuilder.stringParam("The text to type into the field"),
            "clear_first": ToolDefinitionBuilder.boolParam("Clear existing value before typing (default: true)")
        ],
        required: ["selector", "text"]
    )

    static let browserSelectTool = ToolDefinitionBuilder.build(
        name: "browser_select",
        description: "Select an option in a <select> dropdown element.",
        properties: [
            "selector": ToolDefinitionBuilder.stringParam("CSS selector of the <select> element"),
            "value": ToolDefinitionBuilder.stringParam("The option value to select")
        ],
        required: ["selector", "value"]
    )

    static let browserExtractTool = ToolDefinitionBuilder.build(
        name: "browser_extract",
        description: "Extract text content or attribute values from elements matching a CSS selector. Returns up to 50 matches.",
        properties: [
            "selector": ToolDefinitionBuilder.stringParam("CSS selector to match elements (e.g. 'h1', '.price', 'a.nav-link')"),
            "attribute": ToolDefinitionBuilder.stringParam("Optional: extract a specific attribute (e.g. 'href', 'src') instead of text content")
        ],
        required: ["selector"]
    )

    static let browserExecuteJSTool = ToolDefinitionBuilder.build(
        name: "browser_execute_js",
        description: "Execute arbitrary JavaScript code in the browser page context. Use for complex interactions not covered by other browser tools. Has full access to the page DOM and JavaScript APIs.",
        properties: [
            "code": ToolDefinitionBuilder.stringParam("JavaScript code to execute in the page context. Return a value to see the result.")
        ],
        required: ["code"]
    )

    static let browserWaitTool = ToolDefinitionBuilder.build(
        name: "browser_wait",
        description: "Wait for an element matching a CSS selector to appear on the page. Polls every 300ms until the element is found or timeout is reached.",
        properties: [
            "selector": ToolDefinitionBuilder.stringParam("CSS selector to wait for"),
            "timeout": ToolDefinitionBuilder.numberParam("Max wait time in seconds (1-30, default: 10)")
        ],
        required: ["selector"]
    )

    static let browserScrollTool = ToolDefinitionBuilder.build(
        name: "browser_scroll",
        description: "Scroll the current page up or down by a specified number of pixels.",
        properties: [
            "direction": ToolDefinitionBuilder.enumParam("Scroll direction", values: ["down", "up"]),
            "pixels": ToolDefinitionBuilder.intParam("Number of pixels to scroll (default: 500)")
        ],
        required: []
    )
}
