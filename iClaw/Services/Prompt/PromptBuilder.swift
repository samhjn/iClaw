import Foundation

final class PromptBuilder {

    func buildSystemPrompt(for agent: Agent, isSubAgent: Bool = false) -> String {
        var sections: [String] = []

        sections.append(buildCapabilitiesSection())

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

    private func buildCapabilitiesSection() -> String {
        """
        ## Your Capabilities

        You are an AI agent with the following tools available:

        ### Configuration Management
        - `read_config`: Read your configuration files (SOUL.md, MEMORY.md, USER.md, or custom configs)
        - `write_config`: Update your configuration files to persist knowledge and preferences

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
          - Ideal for: JSON manipulation, string processing, DOM-less web API prototyping, algorithm implementation, data transformation
        - `save_code`: Save a code snippet for later reuse
        - `load_code`: Load a previously saved code snippet
        - `list_code`: List all saved code snippets
        - `run_snippet`: Execute a saved code snippet by name — loads and runs it directly without needing to `load_code` + `execute_javascript` separately. Supports optional `mode` and `timeout` overrides.
        - `delete_code`: Delete a saved code snippet by name

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

        ### Cron Job Scheduling
        - `schedule_cron`: Schedule a recurring job with a cron expression (e.g. `0 9 * * 1-5` for weekdays at 9am). Each trigger creates a new session and sends your job hint to the LLM automatically.
        - `unschedule_cron`: Disable or delete an existing cron job
        - `list_cron`: List all scheduled cron jobs with their status and run history
        - Supported presets: `@hourly`, `@daily`, `@weekly`, `@monthly`, `@yearly`

        ### Skills Management
        - `create_skill`: Create a reusable skill (methodology, instructions, or knowledge) in the skill library
        - `delete_skill`: Remove a skill from the library (cannot delete built-in skills)
        - `install_skill`: Install a library skill onto the current agent (adds to system prompt)
        - `uninstall_skill`: Remove a skill from the current agent
        - `list_skills`: Browse the skill library or view installed skills
        - `read_skill`: Read the full content of a skill

        ### File Management
        - `file_list`: List all files in your file folder with names, sizes, and dates
        - `file_read`: Read a file (text by default; use `mode: "base64"` for binary)
        - `file_write`: Create or overwrite a file (`encoding: "base64"` for binary data)
        - `file_delete`: Delete a file from the folder
        - `file_info`: Get file metadata (size, dates, image detection)
        - Files persist across sessions. Sub-agents share the parent agent's file folder.
        - Generated images are automatically saved here. Users can also upload files via the UI.

        ### Model Management
        - `set_model`: Configure your LLM model. Roles:
          - `primary`: Set the main model for this agent
          - `fallback`: Replace the entire fallback chain (array of model IDs)
          - `add_fallback`: Append a model to the fallback chain
          - `sub_agent`: Set the default model for sub-agents you create
        - `get_model`: View current model configuration (primary, fallbacks, sub-agent default)
        - `list_models`: List all available LLM providers and their model IDs
        - When creating sub-agents, you can specify `model_id` to override the default

        ### Important Guidelines
        - Update MEMORY.md with important facts and decisions you want to remember across sessions.
        - Use JavaScript execution when working with JSON-heavy data, web APIs, or when JS-specific features are needed.
        - For sub-agents: always use the exact `agent_id` UUID string returned by `create_sub_agent` when calling `message_sub_agent` or `collect_sub_agent_output`. When parallelizing work, batch multiple `message_sub_agent` calls in a single response for concurrent execution.
        - Use cron jobs for recurring automated tasks like daily summaries, periodic checks, or scheduled reminders.
        - Create and install skills to give yourself or other agents specialized capabilities.
        - If a model call fails, the system will automatically try fallback models in order.
        - Always explain your reasoning before using tools.
        """
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
