import Foundation
import SwiftData

struct SkillTools {
    let agent: Agent
    let modelContext: ModelContext
    private let service: SkillService

    init(agent: Agent, modelContext: ModelContext) {
        self.agent = agent
        self.modelContext = modelContext
        self.service = SkillService(modelContext: modelContext)
    }

    func createSkill(arguments: [String: Any]) -> String {
        guard let name = arguments["name"] as? String else {
            return "[Error] Missing required parameter: name"
        }
        guard let content = arguments["content"] as? String else {
            return "[Error] Missing required parameter: content"
        }
        let summary = arguments["summary"] as? String ?? ""
        let tagsStr = arguments["tags"] as? String ?? ""
        let tags = tagsStr.isEmpty ? [] : tagsStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        // Parse optional scripts JSON
        var scripts: [SkillScript] = []
        if let scriptsJson = arguments["scripts"] as? String, let data = scriptsJson.data(using: .utf8) {
            scripts = (try? JSONDecoder().decode([SkillScript].self, from: data)) ?? []
        }

        // Parse optional tools JSON
        var customTools: [SkillToolDefinition] = []
        if let toolsJson = arguments["tools"] as? String, let data = toolsJson.data(using: .utf8) {
            customTools = (try? JSONDecoder().decode([SkillToolDefinition].self, from: data)) ?? []
        }

        if service.fetchSkill(name: name) != nil {
            return "[Error] A skill named '\(name)' already exists. Use a different name or update the existing skill."
        }

        let skill = service.createSkill(
            name: name,
            summary: summary,
            content: content,
            tags: tags,
            author: agent.name,
            scripts: scripts,
            customTools: customTools
        )

        var result = """
        Skill created successfully.
        - Name: \(skill.name)
        - ID: \(skill.id.uuidString)
        - Tags: \(skill.tags.isEmpty ? "(none)" : skill.tags.joined(separator: ", "))
        - Content: \(skill.content.count) characters
        """
        if !scripts.isEmpty {
            result += "\n- Scripts: \(scripts.count) (\(scripts.map { $0.name }.joined(separator: ", ")))"
        }
        if !customTools.isEmpty {
            result += "\n- Custom Tools: \(customTools.count) (\(customTools.map { $0.name }.joined(separator: ", ")))"
        }
        result += "\n\nUse `install_skill` to install this skill on an agent."
        return result
    }

    func deleteSkill(arguments: [String: Any]) -> String {
        guard let skillId = resolveSkillId(arguments) else {
            return "[Error] Provide either 'skill_id' (UUID) or 'name' to identify the skill"
        }
        guard let skill = service.fetchSkill(id: skillId) else {
            return "[Error] Skill not found"
        }
        if skill.isBuiltIn {
            return "[Error] Cannot delete built-in skills"
        }
        let name = skill.name
        service.deleteSkill(skill)
        return "Skill '\(name)' has been permanently deleted."
    }

    func installSkill(arguments: [String: Any]) -> String {
        guard let skillId = resolveSkillId(arguments) else {
            return "[Error] Provide either 'skill_id' (UUID) or 'name' to identify the skill"
        }
        guard let skill = service.fetchSkill(id: skillId) else {
            return "[Error] Skill not found"
        }

        if let _ = service.installSkill(skill, on: agent) {
            var msg = "Skill '\(skill.name)' installed on agent '\(agent.name)'. It will now be included in your system prompt."
            if !skill.scripts.isEmpty {
                msg += "\n- \(skill.scripts.count) script(s) registered as code snippets (use `run_snippet` to execute)"
            }
            if !skill.customTools.isEmpty {
                let toolNames = skill.customTools.map { PromptBuilder.skillToolName(skillName: skill.name, toolName: $0.name) }
                msg += "\n- \(skill.customTools.count) custom tool(s) now available: \(toolNames.joined(separator: ", "))"
            }
            return msg
        } else {
            return "Skill '\(skill.name)' is already installed on this agent."
        }
    }

    func uninstallSkill(arguments: [String: Any]) -> String {
        guard let skillId = resolveSkillId(arguments) else {
            return "[Error] Provide either 'skill_id' (UUID) or 'name' to identify the skill"
        }
        guard let skill = service.fetchSkill(id: skillId) else {
            return "[Error] Skill not found"
        }

        if service.uninstallSkill(skill, from: agent) {
            return "Skill '\(skill.name)' uninstalled from agent '\(agent.name)'."
        } else {
            return "Skill '\(skill.name)' is not installed on this agent."
        }
    }

    func listSkills(arguments: [String: Any]) -> String {
        let query = arguments["query"] as? String ?? ""
        let scope = arguments["scope"] as? String ?? "all"

        switch scope {
        case "installed":
            return formatInstalledSkills()
        case "library", "all":
            let skills = service.searchSkills(query: query)
            if skills.isEmpty {
                return query.isEmpty ? "(No skills in the library)" : "(No skills matching '\(query)')"
            }
            return formatLibrarySkills(skills)
        default:
            return formatLibrarySkills(service.fetchAllSkills())
        }
    }

    func readSkill(arguments: [String: Any]) -> String {
        guard let skillId = resolveSkillId(arguments) else {
            return "[Error] Provide either 'skill_id' (UUID) or 'name' to identify the skill"
        }
        guard let skill = service.fetchSkill(id: skillId) else {
            return "[Error] Skill not found"
        }

        var result = """
        # \(skill.name)
        **Summary**: \(skill.summary)
        **Tags**: \(skill.tags.joined(separator: ", "))
        **Author**: \(skill.author) | **Version**: \(skill.version)
        **Installed on \(skill.installCount) agent(s)**

        ---

        \(skill.content)
        """

        if !skill.scripts.isEmpty {
            result += "\n\n---\n\n**Scripts (\(skill.scripts.count)):**"
            for script in skill.scripts {
                let desc = script.description ?? script.name
                result += "\n- `\(script.name)` [\(script.language)] — \(desc)"
            }
        }

        if !skill.customTools.isEmpty {
            result += "\n\n**Custom Tools (\(skill.customTools.count)):**"
            for tool in skill.customTools {
                let params = tool.parameters.map { "\($0.name):\($0.type)" }.joined(separator: ", ")
                result += "\n- `\(tool.name)(\(params))` — \(tool.description)"
            }
        }

        return result
    }

    // MARK: - Helpers

    private func resolveSkillId(_ arguments: [String: Any]) -> UUID? {
        if let idStr = arguments["skill_id"] as? String, let id = UUID(uuidString: idStr) {
            return id
        }
        if let name = arguments["name"] as? String, let skill = service.fetchSkill(name: name) {
            return skill.id
        }
        return nil
    }

    private func formatInstalledSkills() -> String {
        let installed = service.installedSkills(for: agent)
        if installed.isEmpty {
            return "(No skills installed on this agent)"
        }
        return installed.compactMap { inst in
            guard let skill = inst.skill else { return nil }
            let status = inst.isEnabled ? "active" : "disabled"
            return "- **\(skill.name)** [\(status)] — \(skill.summary)\n  ID: \(skill.id.uuidString)"
        }.joined(separator: "\n\n")
    }

    private func formatLibrarySkills(_ skills: [Skill]) -> String {
        let installed = Set(agent.installedSkills.compactMap { $0.skill?.id })
        return skills.map { skill in
            let marker = installed.contains(skill.id) ? " [installed]" : ""
            let builtIn = skill.isBuiltIn ? " (built-in)" : ""
            let tags = skill.tags.isEmpty ? "" : " [\(skill.tags.joined(separator: ", "))]"
            return "- **\(skill.name)**\(marker)\(builtIn)\(tags)\n  \(skill.summary)\n  ID: \(skill.id.uuidString)"
        }.joined(separator: "\n\n")
    }
}
