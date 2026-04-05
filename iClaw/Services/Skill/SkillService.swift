import Foundation
import SwiftData

final class SkillService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - CRUD

    func createSkill(
        name: String,
        summary: String,
        content: String,
        tags: [String] = [],
        author: String = "user"
    ) -> Skill {
        let skill = Skill(
            name: name,
            summary: summary,
            content: content,
            tags: tags,
            author: author
        )
        modelContext.insert(skill)
        try? modelContext.save()
        return skill
    }

    func updateSkill(_ skill: Skill, name: String? = nil, summary: String? = nil, content: String? = nil, tags: [String]? = nil) {
        if let name { skill.name = name }
        if let summary { skill.summary = summary }
        if let content { skill.content = content }
        if let tags { skill.tags = tags }
        skill.updatedAt = Date()
        try? modelContext.save()
    }

    func deleteSkill(_ skill: Skill) {
        guard !skill.isBuiltIn else { return }
        modelContext.delete(skill)
        try? modelContext.save()
    }

    func fetchSkill(id: UUID) -> Skill? {
        let descriptor = FetchDescriptor<Skill>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func fetchSkill(name: String) -> Skill? {
        let descriptor = FetchDescriptor<Skill>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.first { $0.name.lowercased() == name.lowercased() }
    }

    func fetchAllSkills() -> [Skill] {
        let descriptor = FetchDescriptor<Skill>(
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func searchSkills(query: String) -> [Skill] {
        let all = fetchAllSkills()
        if query.isEmpty { return all }
        let q = query.lowercased()
        return all.filter {
            $0.name.lowercased().contains(q) ||
            $0.summary.lowercased().contains(q) ||
            $0.tags.contains(where: { $0.lowercased().contains(q) })
        }
    }

    // MARK: - Installation

    func installSkill(_ skill: Skill, on agent: Agent) -> InstalledSkill? {
        if agent.installedSkills.contains(where: { $0.skill?.id == skill.id }) {
            return nil
        }
        let installation = InstalledSkill()
        modelContext.insert(installation)
        agent.installedSkills.append(installation)
        installation.skill = skill
        agent.updatedAt = Date()
        try? modelContext.save()
        return installation
    }

    func uninstallSkill(_ skill: Skill, from agent: Agent) -> Bool {
        guard let installation = agent.installedSkills.first(where: { $0.skill?.id == skill.id }) else {
            return false
        }
        modelContext.delete(installation)
        agent.updatedAt = Date()
        try? modelContext.save()
        return true
    }

    func toggleSkill(_ installation: InstalledSkill) {
        installation.isEnabled.toggle()
        installation.agent?.updatedAt = Date()
        try? modelContext.save()
    }

    func isInstalled(_ skill: Skill, on agent: Agent) -> Bool {
        agent.installedSkills.contains { $0.skill?.id == skill.id }
    }

    func installedSkills(for agent: Agent) -> [InstalledSkill] {
        agent.installedSkills.sorted { ($0.skill?.name ?? "") < ($1.skill?.name ?? "") }
    }

    // MARK: - Built-in Skills

    func ensureBuiltInSkills() {
        let existing = fetchAllSkills().filter { $0.isBuiltIn }
        let existingNames = Set(existing.map { $0.name })

        for template in BuiltInSkills.all {
            if !existingNames.contains(template.name) {
                let skill = Skill(
                    name: template.name,
                    summary: template.summary,
                    content: template.content,
                    tags: template.tags,
                    author: "system",
                    isBuiltIn: true
                )
                modelContext.insert(skill)
            }
        }
        try? modelContext.save()
    }
}

// MARK: - Built-in skill templates

enum BuiltInSkills {
    struct Template {
        let name: String
        let summary: String
        let content: String
        let tags: [String]
    }

    static let all: [Template] = [
        Template(
            name: "Deep Research",
            summary: "Systematic research methodology with source evaluation and synthesis",
            content: """
            # Deep Research Skill

            When asked to research a topic, follow this methodology:

            ## Process
            1. **Decompose** the question into sub-questions
            2. **Search** for information using available tools (JavaScript for web scraping, etc.)
            3. **Evaluate** source credibility and recency
            4. **Synthesize** findings into a coherent analysis
            5. **Cite** sources and note confidence levels

            ## Output Format
            - Start with an executive summary
            - Present findings organized by sub-topic
            - Flag uncertainties and conflicting information
            - End with actionable conclusions

            ## Guidelines
            - Prefer primary sources over secondary
            - Note when information might be outdated
            - Distinguish between facts and opinions
            - Save key findings to MEMORY.md for future reference
            """,
            tags: ["research", "analysis", "methodology"]
        ),
        Template(
            name: "Code Review",
            summary: "Structured code review with security, performance, and maintainability checks",
            content: """
            # Code Review Skill

            When reviewing code, systematically check:

            ## Checklist
            1. **Correctness**: Does the code do what it's supposed to?
            2. **Security**: SQL injection, XSS, auth issues, secret leaks?
            3. **Performance**: N+1 queries, unnecessary allocations, algorithmic complexity?
            4. **Readability**: Clear naming, appropriate comments, consistent style?
            5. **Maintainability**: DRY, single responsibility, proper abstractions?
            6. **Edge Cases**: Null handling, boundary conditions, error states?
            7. **Testing**: Adequate coverage, meaningful assertions?

            ## Output Format
            - Severity levels: CRITICAL / WARNING / SUGGESTION / NITPICK
            - Reference specific line numbers or code sections
            - Provide concrete fix suggestions, not just complaints
            - Summarize overall assessment at the end
            """,
            tags: ["coding", "review", "quality"]
        ),
        Template(
            name: "Daily Planner",
            summary: "Help organize daily tasks with priorities and time blocks",
            content: """
            # Daily Planner Skill

            Help the user organize their day effectively.

            ## Process
            1. Gather the user's tasks and commitments
            2. Categorize by urgency/importance (Eisenhower matrix)
            3. Estimate time needed for each task
            4. Create time-blocked schedule
            5. Save the plan to MEMORY.md

            ## Principles
            - Front-load cognitively demanding tasks
            - Include buffer time between blocks
            - Schedule breaks (Pomodoro-style)
            - Flag tasks that could be delegated or eliminated
            - Review and adjust at midday

            ## Output
            - Formatted schedule with time slots
            - Priority flags for must-do items
            - Reminder to check back for adjustments
            """,
            tags: ["productivity", "planning", "daily"]
        ),
        Template(
            name: "Creative Writer",
            summary: "Creative writing assistance with style adaptation and narrative techniques",
            content: """
            # Creative Writer Skill

            Assist with creative writing in any genre or format.

            ## Capabilities
            - **Fiction**: Plot development, character arcs, dialogue, world-building
            - **Non-fiction**: Structuring arguments, narrative non-fiction, essays
            - **Poetry**: Meter, rhyme schemes, imagery, forms
            - **Copywriting**: Headlines, hooks, CTAs, brand voice

            ## Process
            1. Understand the target audience and purpose
            2. Establish voice, tone, and style parameters
            3. Create outline or structure
            4. Draft with attention to pacing and flow
            5. Revise for clarity, impact, and consistency

            ## Guidelines
            - Show, don't tell
            - Use active voice by default
            - Vary sentence length for rhythm
            - Save style preferences to MEMORY.md for consistency
            """,
            tags: ["writing", "creative", "content"]
        ),
    ]
}
