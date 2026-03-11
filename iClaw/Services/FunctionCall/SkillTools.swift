import Foundation
import SwiftData

struct SkillTools {
    let agent: Agent
    let modelContext: ModelContext
    private var service: SkillService { SkillService(modelContext: modelContext) }

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

        if service.fetchSkill(name: name) != nil {
            return "[Error] A skill named '\(name)' already exists. Use a different name or update the existing skill."
        }

        let skill = service.createSkill(
            name: name,
            summary: summary,
            content: content,
            tags: tags,
            author: agent.name
        )

        return """
        Skill created successfully.
        - Name: \(skill.name)
        - ID: \(skill.id.uuidString)
        - Tags: \(skill.tags.isEmpty ? "(none)" : skill.tags.joined(separator: ", "))
        - Content: \(skill.content.count) characters

        Use `install_skill` to install this skill on an agent.
        """
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
            return "Skill '\(skill.name)' installed on agent '\(agent.name)'. It will now be included in your system prompt."
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

        return """
        # \(skill.name)
        **Summary**: \(skill.summary)
        **Tags**: \(skill.tags.joined(separator: ", "))
        **Author**: \(skill.author) | **Version**: \(skill.version)
        **Installed on \(skill.installCount) agent(s)**

        ---

        \(skill.content)
        """
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
