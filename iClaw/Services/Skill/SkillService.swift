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

            ## Research Tools (in order of preference)

            1. **Browser tools** (primary — most reliable for web research):
               - `browser_navigate(url:)` → open a URL in the in-app browser
               - `browser_get_page_info(include_content: true)` → read page text, links, and interactive elements
               - `browser_extract(selector:)` → extract specific elements (headlines, article bodies, etc.)
               - **Search strategy**: navigate to `https://www.google.com/search?q=YOUR+QUERY` to find sources, then visit promising results
            2. **`fetch_and_extract`** (quick plain-text fetch — may fail due to sandbox network restrictions; if it returns HTTP 0 or network errors, switch to browser tools immediately)
            3. **Post-processing scripts** (use `run_snippet` to execute):
               - `extract_links` — parse HTML to extract follow-up URLs for deeper investigation
               - `summarize_text` — condense long text into key points ranked by importance

            ## Process
            1. **Decompose** the question into 2–5 focused sub-questions
            2. **Search** — start with a search engine query via browser, then visit the most promising results
            3. **Gather** — read each source page with `browser_get_page_info`; use `browser_extract` for specific content; follow links for deeper investigation
            4. **Evaluate** — assess source credibility (official docs > research papers > established news > blogs), recency, and potential biases
            5. **Synthesize** — organize findings into a coherent analysis, cross-referencing multiple sources
            6. **Cite** — reference every key claim to its source URL with a confidence level (High / Medium / Low)

            ## Iterative Deepening
            - After the first pass, identify gaps or conflicting information
            - Search for additional sources to fill gaps or resolve conflicts
            - Stop when key claims have 2–3 corroborating sources, or when additional sources add no new information

            ## Output Format
            - **Executive Summary** — 2–3 sentence overview of key findings
            - **Findings** — organized by sub-topic, each with inline source citations
            - **Source Table** — list of sources used with credibility rating (High / Medium / Low)
            - **Uncertainties** — flag conflicting information and knowledge gaps
            - **Conclusions** — actionable takeaways

            ## Guidelines
            - Prefer primary sources (official docs, research papers, raw data) over secondary (news articles, blog posts)
            - Note when information might be outdated — check publication dates
            - Distinguish clearly between established facts, expert opinions, and speculation
            - When a tool fails, switch to an alternative immediately — do not retry the same failing tool
            - Save key findings to MEMORY.md for future reference
            """,
            tags: ["research", "analysis", "methodology"],
            scripts: [
                SkillScript(
                    name: "extract_links",
                    language: "javascript",
                    code: """
                    const html = args.html || '';
                    const matches = [...html.matchAll(/<a[^>]+href=["']([^"']+)["'][^>]*>([^<]*)<\\/a>/gi)];
                    const links = matches
                        .map(m => ({ url: m[1], text: m[2].trim() }))
                        .filter(l => l.url.startsWith('http') && l.text.length > 0);
                    const unique = links.filter((l, i, arr) => arr.findIndex(x => x.url === l.url) === i);
                    console.log(JSON.stringify(unique.slice(0, 30), null, 2));
                    """,
                    description: "Extract links from HTML content (supports both single and double quoted href attributes)"
                ),
                SkillScript(
                    name: "summarize_text",
                    language: "javascript",
                    code: """
                    const text = args.text || '';
                    const maxLen = args.max_length || 2000;
                    const sentences = text.split(/(?<=[.!?])\\s+/).filter(s => s.trim().length > 20);
                    if (sentences.length === 0) { console.log(text.substring(0, maxLen)); }
                    else {
                        const scored = sentences.map((s, i) => ({
                            text: s.trim(),
                            score: (1 / (i + 1)) + Math.min(s.length / 200, 1)
                        }));
                        scored.sort((a, b) => b.score - a.score);
                        const top = scored.slice(0, 15);
                        top.sort((a, b) => {
                            const ai = sentences.findIndex(x => x.includes(a.text));
                            const bi = sentences.findIndex(x => x.includes(b.text));
                            return ai - bi;
                        });
                        console.log(top.map(s => s.text).join(' ').substring(0, maxLen));
                    }
                    """,
                    description: "Extract key sentences from long text, ranked by position and length importance"
                )
            ],
            customTools: [
                SkillToolDefinition(
                    name: "fetch_and_extract",
                    description: "Fetch a URL and extract readable text content. May fail due to sandbox CORS restrictions — use browser_navigate + browser_get_page_info as a reliable alternative.",
                    parameters: [
                        SkillToolParam(name: "url", type: "string", description: "The URL to fetch content from"),
                        SkillToolParam(name: "max_length", type: "number", description: "Maximum characters to return (default: 5000)", required: false)
                    ],
                    implementation: """
                    const url = args.url;
                    const maxLen = args.max_length || 5000;
                    try {
                        const resp = fetch(url);
                        if (!resp.ok) {
                            console.log(`[Error] HTTP ${resp.status}: ${resp.statusText}. Tip: use browser_navigate("${url}") + browser_get_page_info(include_content: true) instead.`);
                        } else {
                            const html = resp.text;
                            const text = html
                                .replace(/<script[^>]*>[\\s\\S]*?<\\/script>/gi, '')
                                .replace(/<style[^>]*>[\\s\\S]*?<\\/style>/gi, '')
                                .replace(/<nav[^>]*>[\\s\\S]*?<\\/nav>/gi, '')
                                .replace(/<header[^>]*>[\\s\\S]*?<\\/header>/gi, '')
                                .replace(/<footer[^>]*>[\\s\\S]*?<\\/footer>/gi, '')
                                .replace(/<[^>]+>/g, ' ')
                                .replace(/&nbsp;/g, ' ')
                                .replace(/&amp;/g, '&')
                                .replace(/&lt;/g, '<')
                                .replace(/&gt;/g, '>')
                                .replace(/&quot;/g, '"')
                                .replace(/&#39;/g, "'")
                                .replace(/\\s+/g, ' ')
                                .trim();
                            console.log(text.substring(0, maxLen));
                        }
                    } catch (e) {
                        console.log(`[Error] Failed to fetch: ${e.message}. Tip: use browser_navigate("${url}") + browser_get_page_info(include_content: true) instead.`);
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
        Template(
            name: "File Ops",
            summary: "Advanced file operations: copy, move, directory management, rich stat",
            content: """
            # File Ops Skill

            Install this skill when you need directory management, batch copies,
            moves/renames, or rich metadata beyond what the default `file_*` tools provide.

            ## When to use which tool
            - **Create directory**: `skill_file_ops_mkdir(path)` — creates intermediate parents.
            - **Copy**: `skill_file_ops_cp(src, dest, recursive?)` — `recursive` defaults to true.
            - **Move / rename**: `skill_file_ops_mv(src, dest)`.
            - **Rich metadata**: `skill_file_ops_stat(path)` — returns JSON `{name,path,size,is_file,is_dir,is_image,mtime_ms,ctime_ms}`.
            - **Directory tree**: `skill_file_ops_tree(path?, max_depth?)` — recursive listing.
            - **Check existence**: `skill_file_ops_exists(path)` — returns `"true"` or `"false"`.
            - **Touch**: `skill_file_ops_touch(path)` — create an empty file if missing.

            ## POSIX file descriptor operations
            For fine-grained I/O (seek, partial reads/writes, truncate), use `execute_javascript`
            with the `fs` namespace directly:

                let fd = await fs.open("log.txt", "a+");
                await fs.write(fd, "new line\\n");
                await fs.seek(fd, 0, "start");
                let head = await fs.read(fd, 100);
                await fs.close(fd);

            Open flags: `"r"`, `"r+"`, `"w"`, `"w+"`, `"a"`, `"a+"` (Node-compatible).
            Whence for seek: `"start"` | `"current"` | `"end"` (or `0` | `1` | `2`).

            File descriptors are scoped to a single `execute_javascript` call and
            auto-closed when that call ends — but closing explicitly is good hygiene.
            """,
            tags: ["files", "filesystem", "utilities"],
            customTools: [
                SkillToolDefinition(
                    name: "cp",
                    description: "Copy a file or directory. Recursive by default for directories.",
                    parameters: [
                        SkillToolParam(name: "src", type: "string", description: "Source path"),
                        SkillToolParam(name: "dest", type: "string", description: "Destination path"),
                        SkillToolParam(name: "recursive", type: "boolean",
                                       description: "Copy directories recursively (default: true)",
                                       required: false)
                    ],
                    implementation: """
                    const recursive = args.recursive !== false;
                    const res = await fs.cp(args.src, args.dest, {recursive: recursive});
                    console.log(res);
                    """
                ),
                SkillToolDefinition(
                    name: "mv",
                    description: "Move or rename a file or directory.",
                    parameters: [
                        SkillToolParam(name: "src", type: "string", description: "Source path"),
                        SkillToolParam(name: "dest", type: "string", description: "Destination path")
                    ],
                    implementation: """
                    const res = await fs.mv(args.src, args.dest);
                    console.log(res);
                    """
                ),
                SkillToolDefinition(
                    name: "stat",
                    description: "Return JSON metadata for a file or directory (size, mtime_ms, ctime_ms, is_file, is_dir).",
                    parameters: [
                        SkillToolParam(name: "path", type: "string", description: "Path to inspect")
                    ],
                    implementation: """
                    const res = await fs.stat(args.path);
                    console.log(res);
                    """
                ),
                SkillToolDefinition(
                    name: "mkdir",
                    description: "Create a directory (including intermediate components). Idempotent.",
                    parameters: [
                        SkillToolParam(name: "path", type: "string", description: "Directory path to create")
                    ],
                    implementation: """
                    const res = await fs.mkdir(args.path);
                    console.log(res);
                    """
                ),
                SkillToolDefinition(
                    name: "tree",
                    description: "Recursive directory listing with depth control. Returns a formatted text tree.",
                    parameters: [
                        SkillToolParam(name: "path", type: "string",
                                       description: "Root path (default: agent root)",
                                       required: false),
                        SkillToolParam(name: "max_depth", type: "number",
                                       description: "Maximum recursion depth (default: 4)",
                                       required: false)
                    ],
                    implementation: """
                    const maxDepth = args.max_depth || 4;
                    async function walk(path, depth, lines) {
                        if (depth > maxDepth) return;
                        const raw = await fs.list(path);
                        const entries = JSON.parse(raw);
                        for (const entry of entries) {
                            const rel = path ? path + '/' + entry.name : entry.name;
                            const indent = '  '.repeat(depth);
                            const tag = entry.is_dir ? '/' : '';
                            lines.push(indent + entry.name + tag);
                            if (entry.is_dir) await walk(rel, depth + 1, lines);
                        }
                    }
                    const root = args.path || '';
                    const lines = [root ? root + '/' : '.'];
                    await walk(root, 1, lines);
                    console.log(lines.join('\\n'));
                    """
                ),
                SkillToolDefinition(
                    name: "touch",
                    description: "Create an empty file if it doesn't exist (does nothing if the file already exists).",
                    parameters: [
                        SkillToolParam(name: "path", type: "string", description: "File path to touch")
                    ],
                    implementation: """
                    const present = await fs.exists(args.path);
                    if (present) { console.log('OK (already exists)'); }
                    else {
                        const res = await fs.writeFile(args.path, '');
                        console.log(res);
                    }
                    """
                ),
                SkillToolDefinition(
                    name: "exists",
                    description: "Check whether a file or directory exists. Returns 'true' or 'false'.",
                    parameters: [
                        SkillToolParam(name: "path", type: "string", description: "Path to check")
                    ],
                    implementation: """
                    const present = await fs.exists(args.path);
                    console.log(present ? 'true' : 'false');
                    """
                )
            ]
        ),
    ]
}
