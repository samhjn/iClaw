import Foundation

final class PromptBuilder {

    func buildSystemPrompt(for agent: Agent, isSubAgent: Bool = false) -> String {
        var sections: [String] = []

        sections.append(buildCapabilitiesSection(for: agent))

        sections.append(buildSoulSection(agent.soulMarkdown))

        if isSubAgent {
            sections.append(buildSubAgentHints())
        } else {
            sections.append(buildMemorySection(agent.memoryMarkdown))
            sections.append(buildUserSection(agent.userMarkdown))
        }

        let activeSkills = agent.activeSkills
        if !activeSkills.isEmpty {
            sections.append(buildInstalledSkillsSection(activeSkills))
        }

        if !agent.customConfigs.isEmpty {
            sections.append(buildCustomConfigsIndex(agent))
        }

        return sections.joined(separator: "\n\n---\n\n")
    }

    func buildSystemPromptWithCompressedContext(
        for agent: Agent,
        compressedContext: String?,
        isSubAgent: Bool = false
    ) -> String {
        var prompt = buildSystemPrompt(for: agent, isSubAgent: isSubAgent)

        if let compressed = compressedContext, !compressed.isEmpty {
            prompt += "\n\n---\n\n"
            prompt += "## Conversation History Summary\n\n"
            prompt += "The following is a compressed summary of earlier messages in this conversation:\n\n"
            prompt += compressed
        }

        return prompt
    }

    func buildSubAgentInitPrompt(
        parentAgent: Agent,
        subAgentName: String,
        initialContext: String?
    ) -> String {
        var prompt = buildSystemPrompt(for: parentAgent, isSubAgent: true)

        if let context = initialContext, !context.isEmpty {
            prompt += "\n\n---\n\n"
            prompt += "## Context from Parent Agent\n\n"
            prompt += context
        }

        return prompt
    }

    // MARK: - Private sections

    private func isEnabled(_ category: ToolCategory, for agent: Agent) -> Bool {
        agent.permissionLevel(for: category) != .disabled
    }

    private func buildCapabilitiesSection(for agent: Agent) -> String {
        var parts: [String] = [
            "## Your Capabilities\n\nYou are an AI agent with the following tools available:"
        ]

        // Config is always available
        parts.append("""
        ### Configuration Management
        - `read_config`: Read your configuration files (SOUL.md, MEMORY.md, USER.md, or custom configs)
        - `write_config`: Update your configuration files to persist knowledge and preferences
        """)

        if isEnabled(.codeExecution, for: agent) {
            parts.append(codeExecutionSection(for: agent))
        }

        if isEnabled(.subAgents, for: agent) {
            parts.append("""
            ### Sub-Agent Management
            Sub-agents are independent AI workers you create and communicate with via messages.

            **Standard workflow:**
            1. `create_sub_agent` → returns an `agent_id` (UUID string)
            2. `message_sub_agent` with that `agent_id` + your `message` → returns the sub-agent's response
            3. `collect_sub_agent_output` with the same `agent_id` → retrieves session content and cleans up

            **Parallel execution:** When you issue multiple `message_sub_agent` tool calls in the same response, they execute **concurrently**. This is the recommended pattern for fan-out tasks — create several sub-agents, then send messages to all of them in a single turn. Their LLM calls and tool loops run in parallel, significantly reducing total wait time.

            **Tools:**
            - `create_sub_agent`: Create a sub-agent. Returns its `agent_id`. Types: `temp` (default, auto-destroyed after collection) or `persistent` (long-lived).
            - `message_sub_agent`: Send a message to a sub-agent by `agent_id`. It runs autonomously (including tool calls) and returns a text response. Multiple calls in the same turn run in parallel.
            - `collect_sub_agent_output`: Retrieve session output. Mode `summary` (default) or `full`.
            - `list_sub_agents`: List all sub-agents with status and message counts.
            - `stop_sub_agent`: Force-stop a running sub-agent.
            - `delete_sub_agent`: Permanently delete a sub-agent.
            """)
        }

        if isEnabled(.cron, for: agent) {
            parts.append("""
            ### Cron Job Scheduling
            - `schedule_cron`: Schedule a recurring job with a cron expression (e.g. `0 9 * * 1-5` for weekdays at 9am). Each trigger creates a new session and sends your job hint to the LLM automatically.
            - `unschedule_cron`: Disable or delete an existing cron job
            - `list_cron`: List all scheduled cron jobs with their status and run history
            - Supported presets: `@hourly`, `@daily`, `@weekly`, `@monthly`, `@yearly`
            """)
        }

        if isEnabled(.skills, for: agent) {
            parts.append("""
            ### Skills Management
            - `create_skill`: Create a reusable skill (methodology, instructions, or knowledge) in the skill library
            - `delete_skill`: Remove a skill from the library (cannot delete built-in skills)
            - `install_skill`: Install a library skill onto the current agent (adds to system prompt)
            - `uninstall_skill`: Remove a skill from the current agent
            - `list_skills`: Browse the skill library or view installed skills
            - `read_skill`: Read the full content of a skill
            """)
        }

        if isEnabled(.files, for: agent) {
            parts.append("""
            ### File Management
            - `file_list`: List all files in your file folder with names, sizes, and dates
            - `file_read`: Read a file (text by default; use `mode: "base64"` for binary)
            - `file_write`: Create or overwrite a file (`encoding: "base64"` for binary data)
            - `file_delete`: Delete a file from the folder
            - `file_info`: Get file metadata (size, dates, image detection)
            - `attach_media`: Attach an image file from your folder into the conversation so you can see and analyze it
            - Files persist across sessions. Sub-agents share the parent agent's file folder.
            - Generated images are automatically saved here. Users can also upload files via the UI.
            """)
        }

        if isEnabled(.browser, for: agent) {
            parts.append("""
            ### Browser
            - `browser_navigate`: Navigate to a URL or search query
            - `browser_get_page_info`: Get current page title, URL, and interactive elements
            - `browser_click`: Click an element by selector or index
            - `browser_input`: Type text into an input field
            - `browser_select`: Select an option from a dropdown
            - `browser_extract`: Extract text content from the page
            - `browser_execute_js`: Execute JavaScript in the browser page context
            - `browser_wait`: Wait for an element to appear
            - `browser_scroll`: Scroll the page
            """)
        }

        if isEnabled(.model, for: agent) {
            parts.append("""
            ### Model Management
            - `set_model`: Configure your LLM model. Roles:
              - `primary`: Set the main model for this agent
              - `fallback`: Replace the entire fallback chain (array of model IDs)
              - `add_fallback`: Append a model to the fallback chain
              - `sub_agent`: Set the default model for sub-agents you create
            - `get_model`: View current model configuration (primary, fallbacks, sub-agent default)
            - `list_models`: List all available LLM providers and their model IDs
            - When creating sub-agents, you can specify `model_id` to override the default
            """)
        }

        // Apple ecosystem categories
        let appleCategories: [(ToolCategory, String)] = [
            (.calendar, "Calendar: `calendar_list_calendars`, `calendar_create_event`, `calendar_search_events`, `calendar_update_event`, `calendar_delete_event`"),
            (.reminders, "Reminders: `reminder_list`, `reminder_lists`, `reminder_create`, `reminder_complete`, `reminder_delete`"),
            (.contacts, "Contacts: `contacts_search`, `contacts_get_detail`"),
            (.clipboard, "Clipboard: `clipboard_read`, `clipboard_write`"),
            (.notifications, "Notifications: `notification_schedule`, `notification_cancel`, `notification_list`"),
            (.location, "Location: `location_get_current`, `location_geocode`, `location_reverse_geocode`"),
            (.map, "Maps: `map_search_places`, `map_get_directions`"),
            (.health, "Health: read steps/heart rate/sleep/body mass/blood pressure/glucose/oxygen/temperature; write dietary/body/health metrics and workouts"),
        ]
        let enabledApple = appleCategories.filter { isEnabled($0.0, for: agent) }
        if !enabledApple.isEmpty {
            var section = "### Apple Ecosystem\n"
            for (_, desc) in enabledApple {
                section += "- \(desc)\n"
            }
            parts.append(section)
        }

        // Guidelines
        var guidelines: [String] = [
            "Update MEMORY.md with important facts and decisions you want to remember across sessions.",
            "If a model call fails, the system will automatically try fallback models in order.",
            "Always explain your reasoning before using tools.",
        ]
        if isEnabled(.codeExecution, for: agent) {
            guidelines.append("Use JavaScript execution when working with JSON-heavy data, web APIs, or when JS-specific features are needed.")
        }
        if isEnabled(.subAgents, for: agent) {
            guidelines.append("For sub-agents: always use the exact `agent_id` UUID string returned by `create_sub_agent`. When parallelizing work, batch multiple `message_sub_agent` calls in a single response for concurrent execution.")
        }
        if isEnabled(.cron, for: agent) {
            guidelines.append("Use cron jobs for recurring automated tasks like daily summaries, periodic checks, or scheduled reminders.")
        }
        if isEnabled(.skills, for: agent) {
            guidelines.append("Create and install skills to give yourself or other agents specialized capabilities.")
        }
        parts.append("### Important Guidelines\n" + guidelines.map { "- \($0)" }.joined(separator: "\n"))

        return parts.joined(separator: "\n\n")
    }

    private func codeExecutionSection(for agent: Agent) -> String {
        var section = """
        ### Code Execution
        - `execute_javascript`: Execute JavaScript in a sandboxed WKWebView runtime with two modes:
          - `repr` mode: Evaluate an expression and return its JSON-serialized result
          - `script` mode: Run a script and capture console output
          - Full ES6+ syntax: arrow functions, destructuring, template literals, classes, Promises, Map/Set, Symbol, generators, spread/rest, for...of, and more
          - Built-in: `JSON`, `Math`, `Date`, `RegExp`, `Map`, `Set`, `Array` methods, `String` methods — all native JavaScript APIs
          - Console: `console.log()`, `console.warn()`, `console.error()`, `console.table()`, `console.dir()` — output is captured
          - Network: `fetch(url, options)` — synchronous bridge returning `{ok, status, text, json()}`. Supports GET/POST/PUT/DELETE with headers and body
          - Polyfills: `TextEncoder`/`TextDecoder`, `atob`/`btoa`, `setTimeout` (executes immediately)
          - Timeout: default 60s, pass `timeout` parameter (1-300s) per call, or set persistent default via `write_config` with key `javascript_timeout`
        """

        if isEnabled(.files, for: agent) {
            section += """

              - File system: `fs.*` — persistent agent file storage, all methods return Promises:
                - `await fs.list()` — list files in the agent folder
                - `await fs.read(name, {mode: 'base64'})` — read a file (text or base64)
                - `await fs.write(name, content, {encoding: 'base64'})` — write/create a file
                - `await fs.delete(name)` — delete a file
                - `await fs.info(name)` — get file metadata
            """
        }

        let enabledApple = ToolCategory.appleCategories.filter { isEnabled($0, for: agent) }
        if !enabledApple.isEmpty {
            let namespaces = enabledApple.map { "apple.\($0.rawValue).*" }.joined(separator: ", ")
            section += """

              - Apple ecosystem: \(namespaces) — all return Promises, use `await` in script mode (e.g. `let events = await apple.calendar.searchEvents({})`)
            """
        }

        section += """

          - Ideal for: JSON manipulation, string processing, DOM-less web API prototyping, algorithm implementation, data transformation
        - `save_code`: Save a code snippet for later reuse
        - `load_code`: Load a previously saved code snippet
        - `list_code`: List all saved code snippets
        - `run_snippet`: Execute a saved code snippet by name — loads and runs it directly without needing to `load_code` + `execute_javascript` separately. Supports optional `mode` and `timeout` overrides.
        - `delete_code`: Delete a saved code snippet by name
        """

        return section
    }

    private func buildSoulSection(_ soul: String) -> String {
        """
        ## Soul (Identity & Personality)

        \(soul)
        """
    }

    private func buildMemorySection(_ memory: String) -> String {
        """
        ## Memory (Persistent Knowledge)

        \(memory)
        """
    }

    private func buildUserSection(_ user: String) -> String {
        """
        ## User Profile

        \(user)
        """
    }

    private func buildSubAgentHints() -> String {
        """
        ## Sub-Agent Notice

        You are operating as a sub-agent. Your SOUL configuration has been inherited from your parent agent.

        - You can read your parent's MEMORY.md using `read_config` with key "MEMORY.md" for additional context.
        - Focus on the specific task assigned to you.
        - Return clear, structured results to your parent agent.
        """
    }

    private func buildInstalledSkillsSection(_ activeSkills: [InstalledSkill]) -> String {
        var parts: [String] = ["## Installed Skills\n\nThe following skills are active and provide specialized instructions:"]

        for installation in activeSkills {
            guard let skill = installation.skill else { continue }
            parts.append("""
            ### Skill: \(skill.name)
            \(skill.content)
            """)
        }

        return parts.joined(separator: "\n\n")
    }

    private func buildCustomConfigsIndex(_ agent: Agent) -> String {
        let keys = agent.customConfigs.map { "- `\($0.key)`" }.joined(separator: "\n")
        return """
        ## Additional Configs Available

        You have the following custom configuration files. Use `read_config` to access them:

        \(keys)
        """
    }
}
