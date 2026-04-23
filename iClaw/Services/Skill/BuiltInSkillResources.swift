import Foundation

/// Loads locale-specific Markdown content for built-in skills. The iOS
/// Bundle system resolves `url(forResource:withExtension:subdirectory:)`
/// against the user's preferred localization and falls back to the
/// development language (en) when a translation is missing.
enum BuiltInSkillResources {
    /// Returns the Markdown `content` for a built-in skill. The file is
    /// looked up at `<locale>.lproj/BuiltInSkills/<skillName>.md`. Returns
    /// the English copy if the localized file is absent, or the raw skill
    /// name as a last-resort placeholder so upstream field-diffing in
    /// `upgradeBuiltInSkill` still has a non-empty value to compare.
    static func content(forSkillName skillName: String) -> String {
        if let url = Bundle.main.url(
            forResource: skillName,
            withExtension: "md",
            subdirectory: "BuiltInSkills"
        ), let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        return "# \(skillName)"
    }
}
