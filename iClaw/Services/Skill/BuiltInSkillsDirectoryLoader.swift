import Foundation

/// Anchor class for `Bundle(for:)` so resource lookups work in both the host
/// app and the unit-test runner.
private final class BuiltInSkillsDirectoryAnchor {}

/// Phase-2 parallel loader: builds `BuiltInSkills.ResolvedTemplate` values by
/// reading the on-disk skill packages under `Resources/BuiltInSkills/<slug>/`.
///
/// This runs alongside the existing `BuiltInSkills.all` Swift-string templates
/// — neither replaces the other yet. A feature flag (see
/// `BuiltInSkills.loadFromDirectory`) controls which source `SkillService`
/// uses; default is the existing Swift-string path. The parity tests verify
/// both paths produce the same `ResolvedTemplate` for every shipped built-in.
///
/// Phase 3 will:
///   1. Flip the flag's default to `true`.
///   2. Migrate per-tool / per-script translations from `Localizable.strings`
///      into per-locale overlay files inside each package directory.
///   3. Delete the Swift-string `BuiltInSkills.all` payloads.
enum BuiltInSkillsDirectoryLoader {

    /// Bundle holding the `Resources/BuiltInSkills/` directory. Same anchor
    /// trick as `BuiltInSkillResources` — works under XCTest too.
    private static var bundle: Bundle {
        Bundle(for: BuiltInSkillsDirectoryAnchor.self)
    }

    /// Load every shipped built-in skill from its on-disk package and produce
    /// the same `ResolvedTemplate` shape `BuiltInSkills.Template.resolved()`
    /// emits. Skills whose package fails to parse are skipped silently —
    /// callers (`ensureBuiltInSkills`) will fall back to the Swift-string
    /// payload for that name.
    static func loadAll() -> [BuiltInSkills.ResolvedTemplate] {
        // Slug list is derived from `BuiltInSkills.all` so adding a new
        // built-in is a single Swift edit (matches today's mental model) —
        // even though the *content* lives on disk now.
        BuiltInSkills.all.compactMap { template in
            let slug = SkillPackage.derivedSlug(forName: template.name)
            return load(slug: slug, fallbackName: template.name)
        }
    }

    /// Load a single built-in by slug. Returns `nil` if the package is missing
    /// or its frontmatter / META declarations fail to parse.
    static func load(slug: String, fallbackName: String) -> BuiltInSkills.ResolvedTemplate? {
        guard let url = packageURL(forSlug: slug) else { return nil }
        let (parsed, report) = SkillPackage.parse(at: url)
        guard report.ok, let pkg = parsed else { return nil }

        let frontmatter = pkg.frontmatter
        let localizationKey = frontmatter.iclaw.localizationKey ?? slug

        // Display name / summary: fall back to Localizable.strings via the
        // localization key, matching today's per-locale behavior. Phase 3
        // replaces this with `SKILL.<lang>.md` overlays and trims the
        // `Localizable.strings` entries.
        let displayName = L10n.Skills.BuiltIn.displayName(localizationKey)
        let summary = L10n.Skills.BuiltIn.summary(localizationKey)

        // Body: prefer the per-locale `<lang>.lproj/<name>.md` file (existing
        // behavior). The directory's `SKILL.md` body is the canonical English
        // — Phase 3 moves the per-locale `.md` files into `SKILL.<lang>.md`
        // overlays and the parser's overlay resolution does this work.
        let content = BuiltInSkillResources.content(forSkillName: frontmatter.name)

        // Scripts: keep order alphabetic by filename (matches `SkillPackage`
        // sort). Today's Swift-template order can't be reproduced from disk
        // alone; the parity test sorts both sides by name before comparing.
        let scripts: [SkillScript] = pkg.scripts.map { script in
            let scriptName = (script.fileName as NSString).deletingPathExtension
            let desc = L10n.Skills.BuiltIn.scriptDescription(localizationKey, scriptName)
            return SkillScript(
                name: scriptName,
                language: "javascript",
                code: script.code,
                description: desc
            )
        }

        // Tools: same treatment. The `body` (post-META JS) replaces the
        // hand-rolled `implementation` strings with byte-for-byte parity.
        let customTools: [SkillToolDefinition] = pkg.tools.map { tool in
            let params = tool.meta.parameters.map { p in
                SkillToolParam(
                    name: p.name,
                    type: p.type,
                    description: L10n.Skills.BuiltIn.toolParamDescription(
                        localizationKey, tool.meta.name, p.name
                    ),
                    required: p.required,
                    enumValues: p.enumValues
                )
            }
            return SkillToolDefinition(
                name: tool.meta.name,
                description: L10n.Skills.BuiltIn.toolDescription(localizationKey, tool.meta.name),
                parameters: params,
                implementation: tool.body
            )
        }

        _ = fallbackName // currently unused — reserved for future per-skill
                         // fallback paths (e.g. when a SKILL.md is missing
                         // for a known built-in slug).

        return BuiltInSkills.ResolvedTemplate(
            name: frontmatter.name,
            displayName: displayName,
            summary: summary,
            content: content,
            tags: frontmatter.iclaw.tags,
            scripts: scripts,
            customTools: customTools,
            configSchema: []
        )
    }

    /// Locate a built-in skill's package directory in the app bundle.
    private static func packageURL(forSlug slug: String) -> URL? {
        // Bundle.url(forResource:withExtension:subdirectory:) accepts a
        // subdirectory path. Lookup target: "BuiltInSkills/<slug>/SKILL.md"
        // — we use the SKILL.md as the anchor and return its parent.
        if let skillMd = bundle.url(
            forResource: "SKILL",
            withExtension: "md",
            subdirectory: "BuiltInSkills/\(slug)"
        ) {
            return skillMd.deletingLastPathComponent()
        }
        return nil
    }
}
