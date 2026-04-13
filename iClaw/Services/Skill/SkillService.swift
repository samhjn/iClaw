import Foundation
import SwiftData

final class SkillService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            print("[SkillService] Save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - CRUD

    func createSkill(
        name: String,
        summary: String,
        content: String,
        tags: [String] = [],
        author: String = "user",
        scripts: [SkillScript] = [],
        customTools: [SkillToolDefinition] = [],
        configSchema: [SkillConfigField] = []
    ) -> Skill {
        let skill = Skill(
            name: name,
            summary: summary,
            content: content,
            tags: tags,
            author: author,
            scripts: scripts,
            customTools: customTools,
            configSchema: configSchema
        )
        modelContext.insert(skill)
        save()
        return skill
    }

    func updateSkill(_ skill: Skill, name: String? = nil, summary: String? = nil, content: String? = nil, tags: [String]? = nil) {
        if let name {
            skill.name = name
            skill.nameLowercase = name.lowercased()
        }
        if let summary { skill.summary = summary }
        if let content { skill.content = content }
        if let tags { skill.tags = tags }
        skill.updatedAt = Date()
        save()
    }

    func deleteSkill(_ skill: Skill) {
        guard !skill.isBuiltIn else { return }
        modelContext.delete(skill)
        save()
    }

    func fetchSkill(id: UUID) -> Skill? {
        var descriptor = FetchDescriptor<Skill>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func fetchSkill(name: String) -> Skill? {
        let lowered = name.lowercased()
        var descriptor = FetchDescriptor<Skill>(
            predicate: #Predicate { $0.nameLowercase == lowered }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func fetchAllSkills() -> [Skill] {
        let descriptor = FetchDescriptor<Skill>(
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func searchSkills(query: String) -> [Skill] {
        guard !query.isEmpty else { return fetchAllSkills() }
        let descriptor = FetchDescriptor<Skill>(
            predicate: #Predicate {
                $0.name.localizedStandardContains(query) ||
                $0.summary.localizedStandardContains(query) ||
                $0.tagsRaw.localizedStandardContains(query)
            },
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
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

        // Register skill scripts as CodeSnippets on the agent
        for script in skill.scripts {
            let snippetName = "skill:\(skill.name):\(script.name)"
            if !agent.codeSnippets.contains(where: { $0.name == snippetName }) {
                let snippet = CodeSnippet(name: snippetName, language: script.language, code: script.code)
                modelContext.insert(snippet)
                agent.codeSnippets.append(snippet)
            }
        }

        agent.updatedAt = Date()
        save()
        return installation
    }

    func uninstallSkill(_ skill: Skill, from agent: Agent) -> Bool {
        guard let installation = agent.installedSkills.first(where: { $0.skill?.id == skill.id }) else {
            return false
        }
        modelContext.delete(installation)

        // Clean up skill-registered CodeSnippets
        let prefix = "skill:\(skill.name):"
        let toRemove = agent.codeSnippets.filter { $0.name.hasPrefix(prefix) }
        for snippet in toRemove {
            modelContext.delete(snippet)
        }

        agent.updatedAt = Date()
        save()
        return true
    }

    func toggleSkill(_ installation: InstalledSkill) {
        installation.isEnabled.toggle()
        installation.agent?.updatedAt = Date()
        save()
    }

    func isInstalled(_ skill: Skill, on agent: Agent) -> Bool {
        agent.installedSkills.contains { $0.skill?.id == skill.id }
    }

    func installedSkills(for agent: Agent) -> [InstalledSkill] {
        agent.installedSkills.sorted { ($0.skill?.name ?? "") < ($1.skill?.name ?? "") }
    }

    // MARK: - Built-in Skills

    func ensureBuiltInSkills() {
        let descriptor = FetchDescriptor<Skill>(
            predicate: #Predicate { $0.isBuiltIn == true }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let existingByName = Dictionary(uniqueKeysWithValues: existing.map { ($0.name, $0) })

        for template in BuiltInSkills.all {
            if let skill = existingByName[template.name] {
                // Upgrade existing built-in skill if template has changed
                upgradeBuiltInSkill(skill, from: template)
            } else {
                let skill = Skill(
                    name: template.name,
                    summary: template.summary,
                    content: template.content,
                    tags: template.tags,
                    author: "system",
                    isBuiltIn: true,
                    scripts: template.scripts,
                    customTools: template.customTools,
                    configSchema: template.configSchema
                )
                modelContext.insert(skill)
            }
        }
        save()
    }

    /// Update an existing built-in skill to match the latest template.
    /// Only updates fields that have changed to avoid unnecessary writes.
    private func upgradeBuiltInSkill(_ skill: Skill, from template: BuiltInSkills.Template) {
        var changed = false

        if skill.content != template.content {
            skill.content = template.content
            changed = true
        }
        if skill.summary != template.summary {
            skill.summary = template.summary
            changed = true
        }
        if skill.tags != template.tags {
            skill.tags = template.tags
            changed = true
        }
        if skill.scripts != template.scripts {
            skill.scripts = template.scripts
            changed = true
        }
        if skill.customTools != template.customTools {
            skill.customTools = template.customTools
            changed = true
        }
        if skill.configSchema != template.configSchema {
            skill.configSchema = template.configSchema
            changed = true
        }
        // Backfill nameLowercase for skills created before this field existed
        if skill.nameLowercase.isEmpty {
            skill.nameLowercase = skill.name.lowercased()
            changed = true
        }

        if changed {
            skill.updatedAt = Date()
        }
    }
}

// MARK: - Built-in skill templates

enum BuiltInSkills {
    struct Template {
        let name: String
        let summary: String
        let content: String
        let tags: [String]
        var scripts: [SkillScript] = []
        var customTools: [SkillToolDefinition] = []
        var configSchema: [SkillConfigField] = []
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
            2. **Search** for information using available tools — use the custom tools provided by this skill
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
            - Use `fetch_and_extract` to gather content from URLs
            - Use the `extract_links` script to find follow-up sources
            """,
            tags: ["research", "analysis", "methodology"],
            scripts: [
                SkillScript(
                    name: "extract_links",
                    language: "javascript",
                    code: """
                    const html = args.html || '';
                    const matches = [...html.matchAll(/<a[^>]+href="([^"]+)"[^>]*>([^<]*)<\\/a>/gi)];
                    const links = matches
                        .map(m => ({ url: m[1], text: m[2].trim() }))
                        .filter(l => l.url.startsWith('http'));
                    console.log(JSON.stringify(links.slice(0, 30), null, 2));
                    """,
                    description: "Extract links from HTML content for further research"
                ),
                SkillScript(
                    name: "summarize_text",
                    language: "javascript",
                    code: """
                    const text = args.text || '';
                    const maxLen = args.max_length || 2000;
                    const sentences = text.split(/[.!?]+/).filter(s => s.trim().length > 10);
                    const summary = sentences.slice(0, Math.min(sentences.length, 20)).join('. ') + '.';
                    console.log(summary.substring(0, maxLen));
                    """,
                    description: "Extract key sentences from long text"
                )
            ],
            customTools: [
                SkillToolDefinition(
                    name: "fetch_and_extract",
                    description: "Fetch a URL and extract readable text content, stripping HTML tags",
                    parameters: [
                        SkillToolParam(name: "url", type: "string", description: "The URL to fetch content from"),
                        SkillToolParam(name: "max_length", type: "number", description: "Maximum characters to return", required: false)
                    ],
                    implementation: """
                    const url = args.url;
                    const maxLen = args.max_length || 3000;
                    try {
                        const resp = fetch(url);
                        if (!resp.ok) {
                            console.log(`[Error] HTTP ${resp.status}: ${resp.statusText}`);
                        } else {
                            const html = resp.text;
                            // Strip HTML tags and normalize whitespace
                            const text = html
                                .replace(/<script[^>]*>[\\s\\S]*?<\\/script>/gi, '')
                                .replace(/<style[^>]*>[\\s\\S]*?<\\/style>/gi, '')
                                .replace(/<[^>]+>/g, ' ')
                                .replace(/&nbsp;/g, ' ')
                                .replace(/&amp;/g, '&')
                                .replace(/&lt;/g, '<')
                                .replace(/&gt;/g, '>')
                                .replace(/\\s+/g, ' ')
                                .trim();
                            console.log(text.substring(0, maxLen));
                        }
                    } catch (e) {
                        console.log(`[Error] Failed to fetch: ${e.message}`);
                    }
                    """
                )
            ]
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
