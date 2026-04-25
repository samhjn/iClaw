import Foundation

/// Bridges the legacy Swift-string `BuiltInSkills.all` payload and the new
/// on-disk packages under `Resources/BuiltInSkills/<slug>/` (Phase 2 of the
/// skill standard-alignment proposal).
///
/// The single entry point — `BuiltInSkills.allResolvedTemplates()` — reads
/// the `iclaw.skill.builtins_from_directory` UserDefault and dispatches to
/// either the existing `template.resolved()` path or the new
/// `BuiltInSkillsDirectoryLoader.loadAll()`. Default is the legacy path so
/// shipping Phase 2 is invisible to users until parity is verified and the
/// flag is flipped.
extension BuiltInSkills {

    /// UserDefaults key controlling which loader path is used.
    /// `false` (default) → Swift-string templates. `true` → directory packages.
    static let loadFromDirectoryKey = "iclaw.skill.builtins_from_directory"

    /// Read the current setting. Phase 2 default is `false`.
    static var loadFromDirectory: Bool {
        get { UserDefaults.standard.bool(forKey: loadFromDirectoryKey) }
        set { UserDefaults.standard.set(newValue, forKey: loadFromDirectoryKey) }
    }

    /// Return the resolved templates for every shipped built-in skill, using
    /// whichever loader the feature flag selects. If the directory loader is
    /// enabled but a particular slug fails to parse, that one falls back to
    /// the Swift-string template — a single broken package can never make a
    /// previously-installed built-in disappear.
    static func allResolvedTemplates() -> [ResolvedTemplate] {
        if loadFromDirectory {
            let directoryByName = Dictionary(
                uniqueKeysWithValues: BuiltInSkillsDirectoryLoader.loadAll().map { ($0.name, $0) }
            )
            return all.map { template in
                directoryByName[template.name] ?? template.resolved()
            }
        }
        return all.map { $0.resolved() }
    }
}
