import Foundation

/// Anchor class used to resolve the app bundle — `Bundle(for:)` reliably
/// returns the bundle containing this class, even in a unit-test host where
/// `Bundle.main` can point to the XCTest runner instead of the app.
private final class BuiltInSkillResourcesBundleAnchor {}

/// Loads locale-specific Markdown content for built-in skills.
///
/// The Markdown files ship as non-localized resources named
/// `<Skill>.<locale>.md` (e.g. `Deep Research.zh-Hans.md`) in
/// `iClaw/Resources/BuiltInSkills/`. We deliberately avoid the standard
/// `.lproj` localization machinery here — Xcode / XcodeGen flatten group
/// subdirectories and don't treat arbitrary `.md` files inside `.lproj`
/// as auto-variant resources, so a filename-based convention is more
/// reliable than `Bundle.url(forResource:withExtension:subdirectory:)`
/// against a localized subdirectory.
enum BuiltInSkillResources {
    /// Returns the Markdown `content` for a built-in skill, walking the
    /// user's preferred localizations and falling back to the development
    /// language. Returns a `"# <skillName>"` placeholder as a last resort
    /// so upstream field-diffing in `upgradeBuiltInSkill` still has a
    /// non-empty value to compare.
    static func content(forSkillName skillName: String) -> String {
        let bundle = Bundle(for: BuiltInSkillResourcesBundleAnchor.self)
        let dev = bundle.developmentLocalization ?? "en"
        let candidates = bundle.preferredLocalizations + [dev]
        var seen = Set<String>()
        for locale in candidates where seen.insert(locale).inserted {
            let resource = "\(skillName).\(locale)"
            if let url = bundle.url(forResource: resource, withExtension: "md"),
               let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }
        return "# \(skillName)"
    }
}
