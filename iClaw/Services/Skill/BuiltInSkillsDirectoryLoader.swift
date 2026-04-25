import Foundation

/// Anchor class for `Bundle(for:)` so resource lookups work in both the host
/// app and the unit-test runner.
private final class BuiltInSkillsDirectoryAnchor {}

/// Builds `BuiltInSkills.ResolvedTemplate` values by reading the on-disk skill
/// packages under `Resources/BuiltInSkills/<slug>/`.
///
/// Runs alongside the legacy `BuiltInSkills.all` Swift-string templates while
/// `BuiltInSkills.loadFromDirectory` is `false`; flipping the flag swaps the
/// active source. The parity tests verify both paths produce the same
/// `ResolvedTemplate` for every shipped built-in.
///
/// All i18n is resolved against `Bundle.main.preferredLocalizations` by
/// `SkillPackage.parse` via per-locale overlay files (`SKILL.<lang>.md`,
/// `tools/<tool>.<lang>.json`, `scripts/<script>.<lang>.txt`) inside each
/// package — no `Localizable.strings` consultation.
///
/// Next step: flip the flag's default to `true` and delete the Swift-string
/// `BuiltInSkills.all` payloads.
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

        // Every i18n-bearing field below is already overlay-resolved by
        // `SkillPackage.parse` against `Bundle.main.preferredLocalizations`:
        //   - `pkg.displayName` / `pkg.description` / `pkg.body` come from the
        //     best-matching `SKILL.<locale>.md` overlay (canonical fallback).
        //   - `pkg.tools[i].meta.description` and parameter descriptions come
        //     from `tools/<tool>.<locale>.json`.
        //   - `pkg.scripts[i].description` comes from
        //     `scripts/<script>.<locale>.txt`.
        // No more `Localizable.strings` consultation — the package is the
        // single source of truth.

        let scripts: [SkillScript] = pkg.scripts.map { script in
            let scriptName = (script.fileName as NSString).deletingPathExtension
            return SkillScript(
                name: scriptName,
                language: "javascript",
                code: script.code,
                description: script.description
            )
        }

        let customTools: [SkillToolDefinition] = pkg.tools.map { tool in
            let params = tool.meta.parameters.map { p in
                SkillToolParam(
                    name: p.name,
                    type: p.type,
                    description: p.description ?? "",
                    required: p.required,
                    enumValues: p.enumValues
                )
            }
            return SkillToolDefinition(
                name: tool.meta.name,
                description: tool.meta.description,
                parameters: params,
                implementation: tool.body
            )
        }

        _ = fallbackName // currently unused — reserved for future per-skill
                         // fallback paths (e.g. when a SKILL.md is missing
                         // for a known built-in slug).

        return BuiltInSkills.ResolvedTemplate(
            name: frontmatter.name,
            displayName: pkg.displayName,
            summary: pkg.description,
            content: pkg.body,
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
