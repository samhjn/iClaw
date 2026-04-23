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
                $0.displayName.localizedStandardContains(query) ||
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

        let resolved = BuiltInSkills.all.map { $0.resolved() }
        let templateNames = Set(resolved.map(\.name))

        for template in resolved {
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
                skill.displayName = template.displayName
                modelContext.insert(skill)
            }
        }

        // Demote any previously-built-in skill whose template has been removed.
        // Keep the record so existing installations keep working, but flip
        // `isBuiltIn` so users can edit/delete them like ordinary skills.
        for skill in existing where !templateNames.contains(skill.name) {
            skill.isBuiltIn = false
            skill.author = "system (legacy)"
            skill.displayName = ""
            skill.updatedAt = Date()
        }

        save()
    }

    /// Update an existing built-in skill to match the latest template.
    /// Only updates fields that have changed to avoid unnecessary writes.
    /// Diffing on `content` / `summary` / `displayName` also naturally handles
    /// UI-language switches: resolving the template in a new locale produces
    /// different strings, which trip the diff and rewrite the DB row.
    private func upgradeBuiltInSkill(_ skill: Skill, from template: BuiltInSkills.ResolvedTemplate) {
        var changed = false

        if skill.displayName != template.displayName {
            skill.displayName = template.displayName
            changed = true
        }
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
    /// Stable-identifier template for a built-in skill. User-visible strings
    /// (display name, summary, content, tool/script/param/config descriptions)
    /// are looked up per UI locale by `resolved()` — keeping this struct free
    /// of inline English prose.
    struct Template {
        /// Stable English identifier. Used as the matching key in
        /// `ensureBuiltInSkills`, as the skill-prefix for generated tool names
        /// (`skill_<name>_<tool>`), and as the CodeSnippet registration prefix.
        /// Never translated.
        let name: String
        /// Short lowercase key composed into Localizable.strings lookups,
        /// e.g. `"deep_research"` → `"skill.deep_research.summary"`.
        let localizationKey: String
        /// Tags are kept in English for search stability across locales.
        let tags: [String]
        var scripts: [ScriptTemplate] = []
        var customTools: [ToolTemplate] = []
        var configSchema: [ConfigFieldTemplate] = []
    }

    struct ScriptTemplate {
        let name: String
        let language: String
        let code: String
    }

    struct ToolTemplate {
        let name: String
        let parameters: [ToolParamTemplate]
        let implementation: String
    }

    struct ToolParamTemplate {
        let name: String
        let type: String
        let required: Bool
        let enumValues: [String]?

        init(name: String, type: String = "string", required: Bool = true, enumValues: [String]? = nil) {
            self.name = name
            self.type = type
            self.required = required
            self.enumValues = enumValues
        }
    }

    struct ConfigFieldTemplate {
        let key: String
        let type: String
        let required: Bool
        let defaultValue: String?

        init(key: String, type: String = "string", required: Bool = false, defaultValue: String? = nil) {
            self.key = key
            self.type = type
            self.required = required
            self.defaultValue = defaultValue
        }
    }

    /// Fully resolved template with locale-specific strings. Consumed by
    /// `SkillService.ensureBuiltInSkills` to insert/upgrade DB rows.
    struct ResolvedTemplate {
        let name: String
        let displayName: String
        let summary: String
        let content: String
        let tags: [String]
        let scripts: [SkillScript]
        let customTools: [SkillToolDefinition]
        let configSchema: [SkillConfigField]
    }

    // Note: "Code Review", "Daily Planner", and "Creative Writer" were previously
    // registered as built-in templates. They have been removed — their content was
    // pure prose with no executable scripts or custom tools, so they add cognitive
    // load without providing capabilities the model couldn't improvise on its own.
    // `ensureBuiltInSkills()` demotes any pre-existing copies to user-owned skills
    // so installed users can edit or delete them.
    static let all: [Template] = [
        Template(
            name: "Deep Research",
            localizationKey: "deep_research",
            tags: ["research", "analysis", "methodology"],
            scripts: [
                ScriptTemplate(
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
                    """
                ),
                ScriptTemplate(
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
                    """
                )
            ],
            customTools: [
                ToolTemplate(
                    name: "fetch_and_extract",
                    parameters: [
                        ToolParamTemplate(name: "url", type: "string"),
                        ToolParamTemplate(name: "max_length", type: "number", required: false)
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
            name: "File Ops",
            localizationKey: "file_ops",
            tags: ["files", "filesystem", "utilities"],
            customTools: [
                ToolTemplate(
                    name: "cp",
                    parameters: [
                        ToolParamTemplate(name: "src", type: "string"),
                        ToolParamTemplate(name: "dest", type: "string"),
                        ToolParamTemplate(name: "recursive", type: "boolean", required: false)
                    ],
                    implementation: """
                    const recursive = args.recursive !== false;
                    const res = await fs.cp(args.src, args.dest, {recursive: recursive});
                    console.log(res);
                    """
                ),
                ToolTemplate(
                    name: "mv",
                    parameters: [
                        ToolParamTemplate(name: "src", type: "string"),
                        ToolParamTemplate(name: "dest", type: "string")
                    ],
                    implementation: """
                    const res = await fs.mv(args.src, args.dest);
                    console.log(res);
                    """
                ),
                ToolTemplate(
                    name: "stat",
                    parameters: [
                        ToolParamTemplate(name: "path", type: "string")
                    ],
                    implementation: """
                    const res = await fs.stat(args.path);
                    console.log(res);
                    """
                ),
                ToolTemplate(
                    name: "mkdir",
                    parameters: [
                        ToolParamTemplate(name: "path", type: "string")
                    ],
                    implementation: """
                    const res = await fs.mkdir(args.path);
                    console.log(res);
                    """
                ),
                ToolTemplate(
                    name: "tree",
                    parameters: [
                        ToolParamTemplate(name: "path", type: "string", required: false),
                        ToolParamTemplate(name: "max_depth", type: "number", required: false)
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
                ToolTemplate(
                    name: "touch",
                    parameters: [
                        ToolParamTemplate(name: "path", type: "string")
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
                ToolTemplate(
                    name: "exists",
                    parameters: [
                        ToolParamTemplate(name: "path", type: "string")
                    ],
                    implementation: """
                    const present = await fs.exists(args.path);
                    console.log(present ? 'true' : 'false');
                    """
                )
            ]
        ),
        Template(
            name: "Health Plus",
            localizationKey: "health_plus",
            tags: ["health", "fitness", "wellness"],
            customTools: [
                ToolTemplate(
                    name: "read_blood_pressure",
                    parameters: [
                        ToolParamTemplate(name: "start_date", type: "string", required: false),
                        ToolParamTemplate(name: "end_date", type: "string", required: false)
                    ],
                    implementation: """
                    const res = await apple.health.readBloodPressure(args);
                    console.log(JSON.stringify(res));
                    """
                ),
                ToolTemplate(
                    name: "read_blood_glucose",
                    parameters: [
                        ToolParamTemplate(name: "start_date", type: "string", required: false),
                        ToolParamTemplate(name: "end_date", type: "string", required: false)
                    ],
                    implementation: """
                    const res = await apple.health.readBloodGlucose(args);
                    console.log(JSON.stringify(res));
                    """
                ),
                ToolTemplate(
                    name: "read_blood_oxygen",
                    parameters: [
                        ToolParamTemplate(name: "start_date", type: "string", required: false),
                        ToolParamTemplate(name: "end_date", type: "string", required: false)
                    ],
                    implementation: """
                    const res = await apple.health.readBloodOxygen(args);
                    console.log(JSON.stringify(res));
                    """
                ),
                ToolTemplate(
                    name: "read_body_temperature",
                    parameters: [
                        ToolParamTemplate(name: "start_date", type: "string", required: false),
                        ToolParamTemplate(name: "end_date", type: "string", required: false),
                        ToolParamTemplate(name: "unit", type: "string", required: false, enumValues: ["c", "f"])
                    ],
                    implementation: """
                    const res = await apple.health.readBodyTemperature(args);
                    console.log(JSON.stringify(res));
                    """
                ),
                ToolTemplate(
                    name: "write_blood_pressure",
                    parameters: [
                        ToolParamTemplate(name: "systolic", type: "number"),
                        ToolParamTemplate(name: "diastolic", type: "number"),
                        ToolParamTemplate(name: "date", type: "string", required: false)
                    ],
                    implementation: """
                    const res = await apple.health.writeBloodPressure(args);
                    console.log(res);
                    """
                ),
                ToolTemplate(
                    name: "write_blood_glucose",
                    parameters: [
                        ToolParamTemplate(name: "value", type: "number"),
                        ToolParamTemplate(name: "unit", type: "string", required: false, enumValues: ["mmol/l", "mg/dl"]),
                        ToolParamTemplate(name: "date", type: "string", required: false)
                    ],
                    implementation: """
                    const res = await apple.health.writeBloodGlucose(args);
                    console.log(res);
                    """
                ),
                ToolTemplate(
                    name: "write_blood_oxygen",
                    parameters: [
                        ToolParamTemplate(name: "percentage", type: "number"),
                        ToolParamTemplate(name: "date", type: "string", required: false)
                    ],
                    implementation: """
                    const res = await apple.health.writeBloodOxygen(args);
                    console.log(res);
                    """
                ),
                ToolTemplate(
                    name: "write_body_temperature",
                    parameters: [
                        ToolParamTemplate(name: "value", type: "number"),
                        ToolParamTemplate(name: "unit", type: "string", required: false, enumValues: ["c", "f"]),
                        ToolParamTemplate(name: "date", type: "string", required: false)
                    ],
                    implementation: """
                    const res = await apple.health.writeBodyTemperature(args);
                    console.log(res);
                    """
                ),
                ToolTemplate(
                    name: "write_body_fat",
                    parameters: [
                        ToolParamTemplate(name: "percentage", type: "number"),
                        ToolParamTemplate(name: "date", type: "string", required: false)
                    ],
                    implementation: """
                    const res = await apple.health.writeBodyFat(args);
                    console.log(res);
                    """
                ),
                ToolTemplate(
                    name: "write_height",
                    parameters: [
                        ToolParamTemplate(name: "value", type: "number"),
                        ToolParamTemplate(name: "unit", type: "string", required: false, enumValues: ["cm", "m", "in", "ft"]),
                        ToolParamTemplate(name: "date", type: "string", required: false)
                    ],
                    implementation: """
                    const res = await apple.health.writeHeight(args);
                    console.log(res);
                    """
                ),
                ToolTemplate(
                    name: "write_heart_rate",
                    parameters: [
                        ToolParamTemplate(name: "bpm", type: "number"),
                        ToolParamTemplate(name: "date", type: "string", required: false)
                    ],
                    implementation: """
                    const res = await apple.health.writeHeartRate(args);
                    console.log(res);
                    """
                ),
                ToolTemplate(
                    name: "write_dietary_carbohydrates",
                    parameters: [
                        ToolParamTemplate(name: "grams", type: "number"),
                        ToolParamTemplate(name: "date", type: "string", required: false)
                    ],
                    implementation: """
                    const res = await apple.health.writeDietaryCarbohydrates(args);
                    console.log(res);
                    """
                ),
                ToolTemplate(
                    name: "write_dietary_protein",
                    parameters: [
                        ToolParamTemplate(name: "grams", type: "number"),
                        ToolParamTemplate(name: "date", type: "string", required: false)
                    ],
                    implementation: """
                    const res = await apple.health.writeDietaryProtein(args);
                    console.log(res);
                    """
                ),
                ToolTemplate(
                    name: "write_dietary_fat",
                    parameters: [
                        ToolParamTemplate(name: "grams", type: "number"),
                        ToolParamTemplate(name: "date", type: "string", required: false)
                    ],
                    implementation: """
                    const res = await apple.health.writeDietaryFat(args);
                    console.log(res);
                    """
                ),
                ToolTemplate(
                    name: "write_workout",
                    parameters: [
                        ToolParamTemplate(name: "activity_type", type: "string", required: false),
                        ToolParamTemplate(name: "start_date", type: "string"),
                        ToolParamTemplate(name: "end_date", type: "string"),
                        ToolParamTemplate(name: "energy_kcal", type: "number", required: false),
                        ToolParamTemplate(name: "distance_km", type: "number", required: false)
                    ],
                    implementation: """
                    const res = await apple.health.writeWorkout(args);
                    console.log(res);
                    """
                )
            ]
        ),
    ]
}

// MARK: - Template resolution (locale-aware)

extension BuiltInSkills.Template {
    /// Resolve this template against the current UI locale — pulling display
    /// name, summary, content, and every description from `Localizable.strings`
    /// and the per-locale `BuiltInSkills/<name>.md` file.
    func resolved() -> BuiltInSkills.ResolvedTemplate {
        BuiltInSkills.ResolvedTemplate(
            name: name,
            displayName: L10n.Skills.BuiltIn.displayName(localizationKey),
            summary: L10n.Skills.BuiltIn.summary(localizationKey),
            content: BuiltInSkillResources.content(forSkillName: name),
            tags: tags,
            scripts: scripts.map { $0.resolved(skillKey: localizationKey) },
            customTools: customTools.map { $0.resolved(skillKey: localizationKey) },
            configSchema: configSchema.map { $0.resolved(skillKey: localizationKey) }
        )
    }
}

extension BuiltInSkills.ScriptTemplate {
    func resolved(skillKey: String) -> SkillScript {
        SkillScript(
            name: name,
            language: language,
            code: code,
            description: L10n.Skills.BuiltIn.scriptDescription(skillKey, name)
        )
    }
}

extension BuiltInSkills.ToolTemplate {
    func resolved(skillKey: String) -> SkillToolDefinition {
        SkillToolDefinition(
            name: name,
            description: L10n.Skills.BuiltIn.toolDescription(skillKey, name),
            parameters: parameters.map { $0.resolved(skillKey: skillKey, toolName: name) },
            implementation: implementation
        )
    }
}

extension BuiltInSkills.ToolParamTemplate {
    func resolved(skillKey: String, toolName: String) -> SkillToolParam {
        SkillToolParam(
            name: name,
            type: type,
            description: L10n.Skills.BuiltIn.toolParamDescription(skillKey, toolName, name),
            required: required,
            enumValues: enumValues
        )
    }
}

extension BuiltInSkills.ConfigFieldTemplate {
    func resolved(skillKey: String) -> SkillConfigField {
        SkillConfigField(
            key: key,
            label: L10n.Skills.BuiltIn.configLabel(skillKey, key),
            type: type,
            required: required,
            defaultValue: defaultValue
        )
    }
}
