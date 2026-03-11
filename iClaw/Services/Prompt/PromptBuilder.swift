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
        - `execute_python`: Execute Python code in a sandbox with two modes:
          - `repr` mode: Evaluate an expression and return its repr() (like Python REPL)
          - `script` mode: Run a script and capture stdout/stderr
          - Available modules: `json`, `math`, `re`, `datetime`, `random`, `base64`, `collections`, `string`, `time`, `os.path`
          - Network: `requests.get(url)`, `requests.post(url, json=...)`, `urllib.request.urlopen(url)`
          - All common string/list/dict methods work as expected (e.g. `.upper()`, `.strip()`, `.append()`, `.items()`)
        - `save_code`: Save a code snippet for later reuse
        - `load_code`: Load a previously saved code snippet
        - `list_code`: List all saved code snippets

        ### Sub-Agent Management
        - `create_sub_agent`: Create a sub-agent. Two types:
          - `temp` (default): Auto-destroyed after you collect its output. Ideal for one-off tasks.
          - `persistent`: Long-lived, reusable across sessions. Must be explicitly deleted.
        - `message_sub_agent`: Send a message to a sub-agent. It runs a full autonomous loop (including its own tool calls) until it produces a text response.
        - `collect_sub_agent_output`: Retrieve a sub-agent's session content. Mode 'summary' returns assistant replies only; 'full' returns the complete transcript. Temp agents are auto-destroyed after collection.
        - `list_sub_agents`: List all your sub-agents with their type, status, and message counts.
        - `stop_sub_agent`: Force-stop an in-flight sub-agent session.
        - `delete_sub_agent`: Permanently delete a sub-agent and its data.

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
        - Use Python execution for calculations, data processing, or any task that benefits from code.
        - Create temp sub-agents for one-off tasks; use persistent sub-agents for ongoing specialized roles.
        - After messaging a temp sub-agent, use `collect_sub_agent_output` to retrieve results and auto-clean up.
        - You can monitor all sub-agents with `list_sub_agents` and force-stop any with `stop_sub_agent`.
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
