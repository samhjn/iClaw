import Foundation

enum ToolDefinitions {

    /// Returns tools filtered by the agent's Apple tool permission settings.
    /// Tools are filtered per category read/write permissions.
    static func tools(for agent: Agent) -> [LLMToolDefinition] {
        allTools.filter { tool in
            agent.isToolAllowed(tool.function.name)
        }
    }

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

            // Session RAG
            searchSessionsTool,
            recallSessionTool,

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

            // File Management
            fileListTool,
            fileReadTool,
            fileWriteTool,
            fileDeleteTool,
            fileInfoTool,
            attachMediaTool,

            // Image Generation
            generateImageTool,

            // Video Generation
            generateVideoTool,

            // Apple Ecosystem — Calendar
            calendarListCalendarsTool,
            calendarCreateEventTool,
            calendarSearchEventsTool,
            calendarUpdateEventTool,
            calendarDeleteEventTool,

            // Apple Ecosystem — Reminders
            reminderListTool,
            reminderListsTool,
            reminderCreateTool,
            reminderCompleteTool,
            reminderDeleteTool,

            // Apple Ecosystem — Contacts
            contactsSearchTool,
            contactsGetDetailTool,

            // Apple Ecosystem — Clipboard
            clipboardReadTool,
            clipboardWriteTool,

            // Apple Ecosystem — Notifications
            notificationScheduleTool,
            notificationCancelTool,
            notificationListTool,

            // Apple Ecosystem — Location
            locationGetCurrentTool,
            locationGeocodeTool,
            locationReverseGeocodeTool,

            // Apple Ecosystem — Map
            mapSearchPlacesTool,
            mapGetDirectionsTool,

            // Apple Ecosystem — Health (Read)
            healthReadStepsTool,
            healthReadHeartRateTool,
            healthReadSleepTool,
            healthReadBodyMassTool,
            healthReadBloodPressureTool,
            healthReadBloodGlucoseTool,
            healthReadBloodOxygenTool,
            healthReadBodyTemperatureTool,
            // Apple Ecosystem — Health (Write)
            healthWriteDietaryEnergyTool,
            healthWriteBodyMassTool,
            healthWriteDietaryWaterTool,
            healthWriteDietaryCarbohydratesTool,
            healthWriteDietaryProteinTool,
            healthWriteDietaryFatTool,
            healthWriteBloodPressureTool,
            healthWriteBodyFatTool,
            healthWriteHeightTool,
            healthWriteBloodGlucoseTool,
            healthWriteBloodOxygenTool,
            healthWriteBodyTemperatureTool,
            healthWriteHeartRateTool,
            healthWriteWorkoutTool,
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
        description: "Execute JavaScript code in a WKWebView sandbox. In 'repr' mode, evaluates an expression and returns its result. In 'script' mode, runs a script and captures console output. Built-in: JSON, Math, Date, RegExp, Map/Set, Array methods, String methods. Network: synchronous fetch(url, options) returning {ok, status, text, json()}. Console: console.log/warn/error captured. Polyfills: TextEncoder/TextDecoder, atob/btoa, setTimeout (runs immediately). File system: `fs.list()`, `fs.read(name)`, `fs.write(name, content)`, `fs.delete(name)`, `fs.info(name)` — persistent agent file storage. Apple ecosystem: `apple.calendar.*`, `apple.reminders.*`, `apple.contacts.*`, `apple.clipboard.*`, `apple.notifications.*`, `apple.location.*`, `apple.maps.*`, `apple.health.*` — all return Promises, use `await` in script mode (e.g. `let events = await apple.calendar.searchEvents({})`). Parameter passing: use 'args' to inject a key-value object accessible as `args` in JS (e.g. `args.name`, `args.items`). Default timeout 60s (max 300s).",
        properties: [
            "code": ToolDefinitionBuilder.stringParam("The JavaScript code to execute"),
            "mode": ToolDefinitionBuilder.enumParam("Execution mode", values: ["repr", "script"]),
            "timeout": ToolDefinitionBuilder.numberParam("Execution timeout in seconds (1-300, default: 60)"),
            "args": ToolDefinitionBuilder.objectParam("Key-value arguments injected as the `args` object in JavaScript scope (e.g. {\"name\": \"Alice\", \"count\": 3} → accessible as args.name, args.count)")
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
        description: "Execute a saved code snippet by name. Loads the snippet and runs it directly in the appropriate runtime (currently JavaScript only). Supports optional argument overrides for mode and timeout. Use 'args' to pass parameters — they become the `args` object in JavaScript (e.g. a snippet using `args.url` can be called with {\"args\": {\"url\": \"https://example.com\"}}).",
        properties: [
            "name": ToolDefinitionBuilder.stringParam("The name of the saved code snippet to execute"),
            "mode": ToolDefinitionBuilder.enumParam("Execution mode override", values: ["repr", "script"]),
            "timeout": ToolDefinitionBuilder.numberParam("Execution timeout in seconds (1-300, default: 60)"),
            "args": ToolDefinitionBuilder.objectParam("Key-value arguments passed to the snippet as the `args` object in JavaScript scope")
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

    // MARK: - Session RAG Tools

    static let searchSessionsTool = ToolDefinitionBuilder.build(
        name: "search_sessions",
        description: "Search past conversation sessions by keyword. Returns matching session IDs, titles, and metadata. Use this to discover relevant prior conversations when the Related Sessions list is insufficient or empty, then use `recall_session` to retrieve their context.",
        properties: [
            "query": ToolDefinitionBuilder.stringParam("Search query — keywords to match against session titles and message content"),
            "limit": ToolDefinitionBuilder.intParam("Maximum number of results (1-20, default: 10)")
        ],
        required: ["query"]
    )

    static let recallSessionTool = ToolDefinitionBuilder.build(
        name: "recall_session",
        description: "Retrieve context from a past session by its UUID. Returns the session title, compressed history summary, and the 3 most recent messages by default. Supports paging: use `offset` to load earlier messages. The response tells you if there are more messages available.",
        properties: [
            "session_id": ToolDefinitionBuilder.stringParam("The UUID of the session to recall (from search_sessions results or the Related Sessions section)"),
            "max_messages": ToolDefinitionBuilder.intParam("Page size — number of messages to retrieve (default: 3, max: 50)"),
            "offset": ToolDefinitionBuilder.intParam("Skip this many messages from the end. 0 = most recent (default). Use the offset value suggested in the previous response to page backwards through history.")
        ],
        required: ["session_id"]
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

    // MARK: - File Management Tools

    static let fileListTool = ToolDefinitionBuilder.build(
        name: "file_list",
        description: "List all files in the agent's file folder with name, size, and modification date.",
        properties: [:],
        required: []
    )

    static let fileReadTool = ToolDefinitionBuilder.build(
        name: "file_read",
        description: "Read a file from the agent's file folder. Text files are returned as UTF-8 text; use mode='base64' for binary files.",
        properties: [
            "name": ToolDefinitionBuilder.stringParam("The filename to read"),
            "mode": ToolDefinitionBuilder.enumParam("Read mode", values: ["text", "base64"])
        ],
        required: ["name"]
    )

    static let fileWriteTool = ToolDefinitionBuilder.build(
        name: "file_write",
        description: "Write or create a file in the agent's file folder. Text content by default; use encoding='base64' to write binary data.",
        properties: [
            "name": ToolDefinitionBuilder.stringParam("The filename to write (e.g. 'notes.txt', 'data.json')"),
            "content": ToolDefinitionBuilder.stringParam("The content to write (text or base64-encoded)"),
            "encoding": ToolDefinitionBuilder.enumParam("Content encoding", values: ["text", "base64"])
        ],
        required: ["name", "content"]
    )

    static let fileDeleteTool = ToolDefinitionBuilder.build(
        name: "file_delete",
        description: "Delete a file from the agent's file folder.",
        properties: [
            "name": ToolDefinitionBuilder.stringParam("The filename to delete")
        ],
        required: ["name"]
    )

    static let fileInfoTool = ToolDefinitionBuilder.build(
        name: "file_info",
        description: "Get metadata about a file: size, creation date, modification date, and whether it's an image.",
        properties: [
            "name": ToolDefinitionBuilder.stringParam("The filename to get info for")
        ],
        required: ["name"]
    )

    static let attachMediaTool = ToolDefinitionBuilder.build(
        name: "attach_media",
        description: "Attach a media file from the agent's folder as multimodal content in the conversation. The attached file becomes visible to the LLM for analysis. Supports images (jpg, png, gif, webp, heic, bmp, tiff) and videos (mp4, mov, m4v, webm). Audio support planned.",
        properties: [
            "name": ToolDefinitionBuilder.stringParam("The filename to attach (e.g. 'photo.jpg', 'chart.png')"),
            "modality": ToolDefinitionBuilder.enumParam("Media type (auto-detected from extension if omitted)", values: ["image", "audio", "video"])
        ],
        required: ["name"]
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
            "selector": ToolDefinitionBuilder.stringParam("CSS selector (e.g. '#submit-btn', '.login-button'). Use :contains(\"text\") to match elements by text content (e.g. 'button:contains(\"Submit\")').")
        ],
        required: ["selector"]
    )

    static let browserInputTool = ToolDefinitionBuilder.build(
        name: "browser_input",
        description: "Type text into an input field or textarea on the current page. Dispatches input and change events for React/Vue compatibility.",
        properties: [
            "selector": ToolDefinitionBuilder.stringParam("CSS selector of the input element. Use :contains(\"text\") to match by text content."),
            "text": ToolDefinitionBuilder.stringParam("The text to type into the field"),
            "clear_first": ToolDefinitionBuilder.boolParam("Clear existing value before typing (default: true)")
        ],
        required: ["selector", "text"]
    )

    static let browserSelectTool = ToolDefinitionBuilder.build(
        name: "browser_select",
        description: "Select an option in a <select> dropdown element.",
        properties: [
            "selector": ToolDefinitionBuilder.stringParam("CSS selector of the <select> element. Use :contains(\"text\") to match by text content."),
            "value": ToolDefinitionBuilder.stringParam("The option value to select")
        ],
        required: ["selector", "value"]
    )

    static let browserExtractTool = ToolDefinitionBuilder.build(
        name: "browser_extract",
        description: "Extract text content or attribute values from elements matching a CSS selector. Returns up to 50 matches.",
        properties: [
            "selector": ToolDefinitionBuilder.stringParam("CSS selector to match elements (e.g. 'h1', '.price', 'a.nav-link'). Use :contains(\"text\") to match by text content."),
            "attribute": ToolDefinitionBuilder.stringParam("Optional: extract a specific attribute (e.g. 'href', 'src') instead of text content")
        ],
        required: ["selector"]
    )

    static let browserExecuteJSTool = ToolDefinitionBuilder.build(
        name: "browser_execute_js",
        description: "Execute arbitrary JavaScript code in the browser page context. Use for complex interactions not covered by other browser tools. Has full access to the page DOM and JavaScript APIs.",
        properties: [
            "code": ToolDefinitionBuilder.stringParam("JavaScript code to execute in the page context. Use `return value` to return a result. Supports `await` for async operations.")
        ],
        required: ["code"]
    )

    static let browserWaitTool = ToolDefinitionBuilder.build(
        name: "browser_wait",
        description: "Wait for an element matching a CSS selector to appear on the page. Polls every 300ms until the element is found or timeout is reached.",
        properties: [
            "selector": ToolDefinitionBuilder.stringParam("CSS selector to wait for. Use :contains(\"text\") to match by text content."),
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

    // MARK: - Apple Calendar Tools

    static let calendarListCalendarsTool = ToolDefinitionBuilder.build(
        name: "calendar_list_calendars",
        description: "List all available calendars on the device (iCloud, Google, Exchange, etc.).",
        properties: [:],
        required: []
    )

    static let calendarCreateEventTool = ToolDefinitionBuilder.build(
        name: "calendar_create_event",
        description: "Create a new calendar event. Requires title and start_date. Dates use ISO 8601 format (e.g. '2025-03-24T14:00:00') or 'yyyy-MM-dd HH:mm'.",
        properties: [
            "title": ToolDefinitionBuilder.stringParam("Event title"),
            "start_date": ToolDefinitionBuilder.stringParam("Start date/time (ISO 8601 or 'yyyy-MM-dd HH:mm')"),
            "end_date": ToolDefinitionBuilder.stringParam("End date/time (defaults to 1 hour after start)"),
            "all_day": ToolDefinitionBuilder.boolParam("Whether this is an all-day event"),
            "location": ToolDefinitionBuilder.stringParam("Event location"),
            "notes": ToolDefinitionBuilder.stringParam("Event notes/description"),
            "url": ToolDefinitionBuilder.stringParam("URL associated with the event"),
            "calendar_id": ToolDefinitionBuilder.stringParam("Calendar identifier (from calendar_list_calendars). Uses default calendar if omitted."),
            "alert_minutes": ToolDefinitionBuilder.numberParam("Minutes before event to trigger an alert (e.g. 15 for 15-minute reminder)")
        ],
        required: ["title", "start_date"]
    )

    static let calendarSearchEventsTool = ToolDefinitionBuilder.build(
        name: "calendar_search_events",
        description: "Search calendar events within a date range. Defaults to the next 7 days from today.",
        properties: [
            "start_date": ToolDefinitionBuilder.stringParam("Start of search range (defaults to today)"),
            "end_date": ToolDefinitionBuilder.stringParam("End of search range (defaults to 7 days from start)"),
            "keyword": ToolDefinitionBuilder.stringParam("Filter events by keyword in title or location"),
            "calendar_id": ToolDefinitionBuilder.stringParam("Only search in this calendar")
        ],
        required: []
    )

    static let calendarUpdateEventTool = ToolDefinitionBuilder.build(
        name: "calendar_update_event",
        description: "Update an existing calendar event. Only provided fields will be changed.",
        properties: [
            "event_id": ToolDefinitionBuilder.stringParam("The event identifier (from calendar_search_events)"),
            "title": ToolDefinitionBuilder.stringParam("New title"),
            "start_date": ToolDefinitionBuilder.stringParam("New start date/time"),
            "end_date": ToolDefinitionBuilder.stringParam("New end date/time"),
            "location": ToolDefinitionBuilder.stringParam("New location"),
            "notes": ToolDefinitionBuilder.stringParam("New notes")
        ],
        required: ["event_id"]
    )

    static let calendarDeleteEventTool = ToolDefinitionBuilder.build(
        name: "calendar_delete_event",
        description: "Delete a calendar event by its identifier.",
        properties: [
            "event_id": ToolDefinitionBuilder.stringParam("The event identifier to delete")
        ],
        required: ["event_id"]
    )

    // MARK: - Apple Reminder Tools

    static let reminderListTool = ToolDefinitionBuilder.build(
        name: "reminder_list",
        description: "List reminders. By default shows incomplete reminders only. Optionally filter by list name.",
        properties: [
            "list_name": ToolDefinitionBuilder.stringParam("Only show reminders from this list"),
            "include_completed": ToolDefinitionBuilder.boolParam("Include completed reminders (default: false)")
        ],
        required: []
    )

    static let reminderListsTool = ToolDefinitionBuilder.build(
        name: "reminder_lists",
        description: "List all reminder lists (e.g. 'Personal', 'Work', 'Shopping').",
        properties: [:],
        required: []
    )

    static let reminderCreateTool = ToolDefinitionBuilder.build(
        name: "reminder_create",
        description: "Create a new reminder with optional due date, priority, and list assignment.",
        properties: [
            "title": ToolDefinitionBuilder.stringParam("Reminder title"),
            "notes": ToolDefinitionBuilder.stringParam("Additional notes"),
            "due_date": ToolDefinitionBuilder.stringParam("Due date (ISO 8601 or 'yyyy-MM-dd HH:mm' or 'yyyy-MM-dd')"),
            "priority": ToolDefinitionBuilder.enumParam("Priority level", values: ["high", "medium", "low"]),
            "list_name": ToolDefinitionBuilder.stringParam("Reminder list to add to (uses default if omitted)"),
            "alert_minutes": ToolDefinitionBuilder.numberParam("Minutes before due date to trigger alert")
        ],
        required: ["title"]
    )

    static let reminderCompleteTool = ToolDefinitionBuilder.build(
        name: "reminder_complete",
        description: "Mark a reminder as completed or incomplete.",
        properties: [
            "reminder_id": ToolDefinitionBuilder.stringParam("The reminder identifier (from reminder_list)"),
            "completed": ToolDefinitionBuilder.boolParam("Set to true to complete, false to uncomplete (default: true)")
        ],
        required: ["reminder_id"]
    )

    static let reminderDeleteTool = ToolDefinitionBuilder.build(
        name: "reminder_delete",
        description: "Delete a reminder by its identifier.",
        properties: [
            "reminder_id": ToolDefinitionBuilder.stringParam("The reminder identifier to delete")
        ],
        required: ["reminder_id"]
    )

    // MARK: - Apple Contacts Tools

    static let contactsSearchTool = ToolDefinitionBuilder.build(
        name: "contacts_search",
        description: "Search contacts by name or phone number. Returns matching contacts with basic info (name, phone, email). Read-only.",
        properties: [
            "query": ToolDefinitionBuilder.stringParam("Name or phone number to search for")
        ],
        required: ["query"]
    )

    static let contactsGetDetailTool = ToolDefinitionBuilder.build(
        name: "contacts_get_detail",
        description: "Get detailed information about a specific contact by ID (phones, emails, addresses, birthday, job, etc.). Read-only.",
        properties: [
            "contact_id": ToolDefinitionBuilder.stringParam("Contact identifier (from contacts_search)")
        ],
        required: ["contact_id"]
    )

    // MARK: - Apple Clipboard Tools

    static let clipboardReadTool = ToolDefinitionBuilder.build(
        name: "clipboard_read",
        description: "Read the current content of the system clipboard (text, URL, or image indicator).",
        properties: [:],
        required: []
    )

    static let clipboardWriteTool = ToolDefinitionBuilder.build(
        name: "clipboard_write",
        description: "Write text to the system clipboard.",
        properties: [
            "text": ToolDefinitionBuilder.stringParam("The text to copy to clipboard")
        ],
        required: ["text"]
    )

    // MARK: - Apple Notification Tools

    static let notificationScheduleTool = ToolDefinitionBuilder.build(
        name: "notification_schedule",
        description: "Schedule a local notification. Can fire at a specific date/time or after a delay in seconds.",
        properties: [
            "title": ToolDefinitionBuilder.stringParam("Notification title"),
            "body": ToolDefinitionBuilder.stringParam("Notification body text"),
            "subtitle": ToolDefinitionBuilder.stringParam("Optional subtitle"),
            "id": ToolDefinitionBuilder.stringParam("Custom notification identifier (auto-generated if omitted)"),
            "date": ToolDefinitionBuilder.stringParam("Fire at this date/time (ISO 8601 or 'yyyy-MM-dd HH:mm')"),
            "delay_seconds": ToolDefinitionBuilder.numberParam("Fire after this many seconds (used if date is not set)")
        ],
        required: ["title"]
    )

    static let notificationCancelTool = ToolDefinitionBuilder.build(
        name: "notification_cancel",
        description: "Cancel a pending notification by its identifier, or cancel all pending notifications.",
        properties: [
            "id": ToolDefinitionBuilder.stringParam("Notification identifier to cancel"),
            "cancel_all": ToolDefinitionBuilder.boolParam("Cancel all pending notifications (default: false)")
        ],
        required: []
    )

    static let notificationListTool = ToolDefinitionBuilder.build(
        name: "notification_list",
        description: "List all pending (scheduled but not yet delivered) notifications.",
        properties: [:],
        required: []
    )

    // MARK: - Apple Location Tools

    static let locationGetCurrentTool = ToolDefinitionBuilder.build(
        name: "location_get_current",
        description: "Get the device's current GPS location (latitude, longitude, altitude, accuracy) with optional reverse-geocoded address.",
        properties: [
            "include_address": ToolDefinitionBuilder.boolParam("Include reverse-geocoded address (default: true)")
        ],
        required: []
    )

    static let locationGeocodeTool = ToolDefinitionBuilder.build(
        name: "location_geocode",
        description: "Convert an address string to geographic coordinates (latitude/longitude).",
        properties: [
            "address": ToolDefinitionBuilder.stringParam("The address to geocode (e.g. '1 Apple Park Way, Cupertino')")
        ],
        required: ["address"]
    )

    static let locationReverseGeocodeTool = ToolDefinitionBuilder.build(
        name: "location_reverse_geocode",
        description: "Convert geographic coordinates to a human-readable address.",
        properties: [
            "latitude": ToolDefinitionBuilder.numberParam("Latitude"),
            "longitude": ToolDefinitionBuilder.numberParam("Longitude")
        ],
        required: ["latitude", "longitude"]
    )

    // MARK: - Apple Map Tools

    static let mapSearchPlacesTool = ToolDefinitionBuilder.build(
        name: "map_search_places",
        description: "Search for places, businesses, and points of interest using Apple Maps. Optionally search near specific coordinates or the user's current location.",
        properties: [
            "query": ToolDefinitionBuilder.stringParam("Search query (e.g. 'coffee shop', 'gas station', 'Apple Store')"),
            "latitude": ToolDefinitionBuilder.numberParam("Center latitude for nearby search"),
            "longitude": ToolDefinitionBuilder.numberParam("Center longitude for nearby search"),
            "near_me": ToolDefinitionBuilder.boolParam("Search near the user's current location (default: false)"),
            "radius": ToolDefinitionBuilder.numberParam("Search radius in meters (default: 5000)")
        ],
        required: ["query"]
    )

    static let mapGetDirectionsTool = ToolDefinitionBuilder.build(
        name: "map_get_directions",
        description: "Get directions between two locations. Supports driving, walking, and transit. Returns distance, estimated time, and step-by-step directions.",
        properties: [
            "from_address": ToolDefinitionBuilder.stringParam("Starting address (uses current location if omitted)"),
            "from_latitude": ToolDefinitionBuilder.numberParam("Starting latitude (alternative to from_address)"),
            "from_longitude": ToolDefinitionBuilder.numberParam("Starting longitude"),
            "to_address": ToolDefinitionBuilder.stringParam("Destination address"),
            "to_latitude": ToolDefinitionBuilder.numberParam("Destination latitude (alternative to to_address)"),
            "to_longitude": ToolDefinitionBuilder.numberParam("Destination longitude"),
            "transport": ToolDefinitionBuilder.enumParam("Transport type", values: ["driving", "walking", "transit"])
        ],
        required: []
    )

    // MARK: - Apple Health Tools

    static let healthReadStepsTool = ToolDefinitionBuilder.build(
        name: "health_read_steps",
        description: "Read step count from Apple Health in a date range (defaults to last 7 days).",
        properties: [
            "start_date": ToolDefinitionBuilder.stringParam("Start date (ISO 8601 or yyyy-MM-dd HH:mm)"),
            "end_date": ToolDefinitionBuilder.stringParam("End date (ISO 8601 or yyyy-MM-dd HH:mm)")
        ],
        required: []
    )

    static let healthReadHeartRateTool = ToolDefinitionBuilder.build(
        name: "health_read_heart_rate",
        description: "Read heart-rate summary (avg/min/max bpm) from Apple Health in a date range (defaults to last 24h).",
        properties: [
            "start_date": ToolDefinitionBuilder.stringParam("Start date (ISO 8601 or yyyy-MM-dd HH:mm)"),
            "end_date": ToolDefinitionBuilder.stringParam("End date (ISO 8601 or yyyy-MM-dd HH:mm)")
        ],
        required: []
    )

    static let healthReadSleepTool = ToolDefinitionBuilder.build(
        name: "health_read_sleep",
        description: "Read sleep summary from Apple Health (asleep and in-bed durations) in a date range (defaults to last 7 days).",
        properties: [
            "start_date": ToolDefinitionBuilder.stringParam("Start date (ISO 8601 or yyyy-MM-dd HH:mm)"),
            "end_date": ToolDefinitionBuilder.stringParam("End date (ISO 8601 or yyyy-MM-dd HH:mm)")
        ],
        required: []
    )

    static let healthReadBodyMassTool = ToolDefinitionBuilder.build(
        name: "health_read_body_mass",
        description: "Read body-mass samples from Apple Health in a date range (defaults to last 30 days).",
        properties: [
            "start_date": ToolDefinitionBuilder.stringParam("Start date (ISO 8601 or yyyy-MM-dd HH:mm)"),
            "end_date": ToolDefinitionBuilder.stringParam("End date (ISO 8601 or yyyy-MM-dd HH:mm)"),
            "unit": ToolDefinitionBuilder.enumParam("Display unit", values: ["kg", "lb"])
        ],
        required: []
    )

    static let healthWriteDietaryEnergyTool = ToolDefinitionBuilder.build(
        name: "health_write_dietary_energy",
        description: "Write dietary energy consumed (kcal) to Apple Health. Useful for calorie logging (e.g. photo-based calorie estimation).",
        properties: [
            "kcal": ToolDefinitionBuilder.numberParam("Calories in kilocalories"),
            "date": ToolDefinitionBuilder.stringParam("Entry time (ISO 8601 or yyyy-MM-dd HH:mm). Defaults to now."),
            "meal": ToolDefinitionBuilder.stringParam("Optional meal description/category"),
            "note": ToolDefinitionBuilder.stringParam("Optional note")
        ],
        required: ["kcal"]
    )

    static let healthWriteBodyMassTool = ToolDefinitionBuilder.build(
        name: "health_write_body_mass",
        description: "Write body mass to Apple Health.",
        properties: [
            "value": ToolDefinitionBuilder.numberParam("Body mass value"),
            "unit": ToolDefinitionBuilder.enumParam("Unit for value", values: ["kg", "lb"]),
            "date": ToolDefinitionBuilder.stringParam("Entry time (ISO 8601 or yyyy-MM-dd HH:mm). Defaults to now.")
        ],
        required: ["value"]
    )

    static let healthWriteDietaryWaterTool = ToolDefinitionBuilder.build(
        name: "health_write_dietary_water",
        description: "Write dietary water intake to Apple Health.",
        properties: [
            "ml": ToolDefinitionBuilder.numberParam("Water amount in milliliters"),
            "date": ToolDefinitionBuilder.stringParam("Entry time (ISO 8601 or yyyy-MM-dd HH:mm). Defaults to now.")
        ],
        required: ["ml"]
    )

    static let healthWriteDietaryCarbohydratesTool = ToolDefinitionBuilder.build(
        name: "health_write_dietary_carbohydrates",
        description: "Write dietary carbohydrates (grams) to Apple Health.",
        properties: [
            "grams": ToolDefinitionBuilder.numberParam("Carbohydrates in grams"),
            "date": ToolDefinitionBuilder.stringParam("Entry time (ISO 8601 or yyyy-MM-dd HH:mm). Defaults to now.")
        ],
        required: ["grams"]
    )

    static let healthWriteDietaryProteinTool = ToolDefinitionBuilder.build(
        name: "health_write_dietary_protein",
        description: "Write dietary protein (grams) to Apple Health.",
        properties: [
            "grams": ToolDefinitionBuilder.numberParam("Protein in grams"),
            "date": ToolDefinitionBuilder.stringParam("Entry time (ISO 8601 or yyyy-MM-dd HH:mm). Defaults to now.")
        ],
        required: ["grams"]
    )

    static let healthWriteDietaryFatTool = ToolDefinitionBuilder.build(
        name: "health_write_dietary_fat",
        description: "Write dietary fat (grams) to Apple Health.",
        properties: [
            "grams": ToolDefinitionBuilder.numberParam("Fat in grams"),
            "date": ToolDefinitionBuilder.stringParam("Entry time (ISO 8601 or yyyy-MM-dd HH:mm). Defaults to now.")
        ],
        required: ["grams"]
    )

    static let healthWriteWorkoutTool = ToolDefinitionBuilder.build(
        name: "health_write_workout",
        description: "Write a workout session to Apple Health with activity type, start/end time, and optional energy/distance.",
        properties: [
            "activity_type": ToolDefinitionBuilder.stringParam("Workout activity type, e.g. running, walking, cycling, swimming, yoga, strength"),
            "start_date": ToolDefinitionBuilder.stringParam("Workout start time (ISO 8601 or yyyy-MM-dd HH:mm)"),
            "end_date": ToolDefinitionBuilder.stringParam("Workout end time (ISO 8601 or yyyy-MM-dd HH:mm)"),
            "energy_kcal": ToolDefinitionBuilder.numberParam("Optional active energy burned in kcal"),
            "distance_km": ToolDefinitionBuilder.numberParam("Optional distance in kilometers")
        ],
        required: ["start_date", "end_date"]
    )

    // MARK: - Apple Health Tools (New)

    static let healthReadBloodPressureTool = ToolDefinitionBuilder.build(
        name: "health_read_blood_pressure",
        description: "Read blood pressure (systolic/diastolic) samples from Apple Health in a date range (defaults to last 30 days).",
        properties: [
            "start_date": ToolDefinitionBuilder.stringParam("Start date (ISO 8601 or yyyy-MM-dd HH:mm)"),
            "end_date": ToolDefinitionBuilder.stringParam("End date (ISO 8601 or yyyy-MM-dd HH:mm)")
        ],
        required: []
    )

    static let healthReadBloodGlucoseTool = ToolDefinitionBuilder.build(
        name: "health_read_blood_glucose",
        description: "Read blood glucose samples from Apple Health in a date range (defaults to last 30 days).",
        properties: [
            "start_date": ToolDefinitionBuilder.stringParam("Start date (ISO 8601 or yyyy-MM-dd HH:mm)"),
            "end_date": ToolDefinitionBuilder.stringParam("End date (ISO 8601 or yyyy-MM-dd HH:mm)")
        ],
        required: []
    )

    static let healthReadBloodOxygenTool = ToolDefinitionBuilder.build(
        name: "health_read_blood_oxygen",
        description: "Read blood oxygen saturation (SpO₂) samples from Apple Health in a date range (defaults to last 7 days).",
        properties: [
            "start_date": ToolDefinitionBuilder.stringParam("Start date (ISO 8601 or yyyy-MM-dd HH:mm)"),
            "end_date": ToolDefinitionBuilder.stringParam("End date (ISO 8601 or yyyy-MM-dd HH:mm)")
        ],
        required: []
    )

    static let healthReadBodyTemperatureTool = ToolDefinitionBuilder.build(
        name: "health_read_body_temperature",
        description: "Read body temperature samples from Apple Health in a date range (defaults to last 30 days).",
        properties: [
            "start_date": ToolDefinitionBuilder.stringParam("Start date (ISO 8601 or yyyy-MM-dd HH:mm)"),
            "end_date": ToolDefinitionBuilder.stringParam("End date (ISO 8601 or yyyy-MM-dd HH:mm)"),
            "unit": ToolDefinitionBuilder.enumParam("Temperature unit", values: ["c", "f"])
        ],
        required: []
    )

    static let healthWriteBloodPressureTool = ToolDefinitionBuilder.build(
        name: "health_write_blood_pressure",
        description: "Write blood pressure reading (systolic/diastolic mmHg) to Apple Health. Useful for recording blood pressure monitor readings.",
        properties: [
            "systolic": ToolDefinitionBuilder.numberParam("Systolic pressure in mmHg (e.g. 120)"),
            "diastolic": ToolDefinitionBuilder.numberParam("Diastolic pressure in mmHg (e.g. 80)"),
            "date": ToolDefinitionBuilder.stringParam("Entry time (ISO 8601 or yyyy-MM-dd HH:mm). Defaults to now.")
        ],
        required: ["systolic", "diastolic"]
    )

    static let healthWriteBodyFatTool = ToolDefinitionBuilder.build(
        name: "health_write_body_fat",
        description: "Write body fat percentage to Apple Health. Useful for recording smart scale readings.",
        properties: [
            "percentage": ToolDefinitionBuilder.numberParam("Body fat percentage (e.g. 22.5)"),
            "date": ToolDefinitionBuilder.stringParam("Entry time (ISO 8601 or yyyy-MM-dd HH:mm). Defaults to now.")
        ],
        required: ["percentage"]
    )

    static let healthWriteHeightTool = ToolDefinitionBuilder.build(
        name: "health_write_height",
        description: "Write height to Apple Health.",
        properties: [
            "value": ToolDefinitionBuilder.numberParam("Height value"),
            "unit": ToolDefinitionBuilder.enumParam("Unit for value", values: ["cm", "m", "in", "ft"]),
            "date": ToolDefinitionBuilder.stringParam("Entry time (ISO 8601 or yyyy-MM-dd HH:mm). Defaults to now.")
        ],
        required: ["value"]
    )

    static let healthWriteBloodGlucoseTool = ToolDefinitionBuilder.build(
        name: "health_write_blood_glucose",
        description: "Write blood glucose reading to Apple Health. Useful for recording glucose meter readings.",
        properties: [
            "value": ToolDefinitionBuilder.numberParam("Blood glucose value"),
            "unit": ToolDefinitionBuilder.enumParam("Unit for value", values: ["mmol/l", "mg/dl"]),
            "date": ToolDefinitionBuilder.stringParam("Entry time (ISO 8601 or yyyy-MM-dd HH:mm). Defaults to now.")
        ],
        required: ["value"]
    )

    static let healthWriteBloodOxygenTool = ToolDefinitionBuilder.build(
        name: "health_write_blood_oxygen",
        description: "Write blood oxygen saturation (SpO₂ %) to Apple Health. Useful for recording pulse oximeter readings.",
        properties: [
            "percentage": ToolDefinitionBuilder.numberParam("SpO₂ percentage (e.g. 98)"),
            "date": ToolDefinitionBuilder.stringParam("Entry time (ISO 8601 or yyyy-MM-dd HH:mm). Defaults to now.")
        ],
        required: ["percentage"]
    )

    static let healthWriteBodyTemperatureTool = ToolDefinitionBuilder.build(
        name: "health_write_body_temperature",
        description: "Write body temperature to Apple Health. Useful for recording thermometer readings.",
        properties: [
            "value": ToolDefinitionBuilder.numberParam("Temperature value"),
            "unit": ToolDefinitionBuilder.enumParam("Temperature unit", values: ["c", "f"]),
            "date": ToolDefinitionBuilder.stringParam("Entry time (ISO 8601 or yyyy-MM-dd HH:mm). Defaults to now.")
        ],
        required: ["value"]
    )

    static let healthWriteHeartRateTool = ToolDefinitionBuilder.build(
        name: "health_write_heart_rate",
        description: "Write heart rate (bpm) to Apple Health. Useful for recording manual pulse readings.",
        properties: [
            "bpm": ToolDefinitionBuilder.numberParam("Heart rate in beats per minute"),
            "date": ToolDefinitionBuilder.stringParam("Entry time (ISO 8601 or yyyy-MM-dd HH:mm). Defaults to now.")
        ],
        required: ["bpm"]
    )

    // MARK: - Image Generation

    static let generateImageTool = ToolDefinitionBuilder.build(
        name: "generate_image",
        description: "Generate images using AI image generation models. Use this when the user asks you to create, draw, or generate images. Returns the generated image(s) as attachments in the conversation.",
        properties: [
            "prompt": ToolDefinitionBuilder.stringParam("Detailed description of the image to generate. Be specific about style, composition, colors, and subject matter."),
            "size": ToolDefinitionBuilder.stringParam("Image size. Common values: 1024x1024, 1792x1024, 1024x1792. Optional, defaults to model default."),
            "quality": ToolDefinitionBuilder.enumParam("Image quality level. Optional.", values: ["standard", "hd"]),
            "n": ToolDefinitionBuilder.intParam("Number of images to generate (1-4). Default: 1.")
        ],
        required: ["prompt"]
    )

    // MARK: - Video Generation

    static let generateVideoTool = ToolDefinitionBuilder.build(
        name: "generate_video",
        description: "Generate a video using AI video generation models. Use this when the user asks you to create or generate a video. Video generation typically takes 1-5 minutes. Returns the generated video as an attachment in the conversation.",
        properties: [
            "prompt": ToolDefinitionBuilder.stringParam("Detailed description of the video to generate. Be specific about the scene, action, camera movement, style, and mood."),
            "duration": ToolDefinitionBuilder.stringParam("Desired video duration. Common values: '5s', '10s'. Optional, defaults to model default."),
            "aspect_ratio": ToolDefinitionBuilder.stringParam("Aspect ratio. Common values: '16:9', '9:16', '1:1'. Optional, defaults to model default."),
            "image_url": ToolDefinitionBuilder.stringParam("Optional URL or agentfile:// reference of an image to use as the first frame (image-to-video). Only supported by some models.")
        ],
        required: ["prompt"]
    )
}
