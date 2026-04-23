import Foundation

/// Anchor class used to resolve the app bundle — `Bundle(for:)` reliably
/// returns the bundle containing this class, even in a unit-test host where
/// `Bundle.main` can point to the XCTest runner instead of the app.
private final class BuiltInSkillResourcesBundleAnchor {}

/// Loads locale-specific Markdown content for built-in skills. The iOS
/// Bundle system resolves `url(forResource:withExtension:)` against the
/// user's preferred localization and falls back to the development language
/// (en) when a translation is missing.
enum BuiltInSkillResources {
    /// Returns the Markdown `content` for a built-in skill. The file is
    /// looked up at `<locale>.lproj/<skillName>.md` in the app bundle.
    /// Returns the English copy if the localized file is absent, or a raw
    /// placeholder so upstream field-diffing in `upgradeBuiltInSkill` still
    /// has a non-empty value to compare.
    static func content(forSkillName skillName: String) -> String {
        let bundle = Bundle(for: BuiltInSkillResourcesBundleAnchor.self)
        if let url = bundle.url(forResource: skillName, withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        return "# \(skillName)"
    }
}
