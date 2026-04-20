import Foundation

/// Kind of a staged file, determined by the Share Extension at loadItem time.
/// Drives how the main app materializes the file into the target session's
/// compose area (image bar, video bar, or file bar).
enum HandoffFileKind: String, Codable {
    case image
    case video
    case file
    case text
}

/// One file inside a `HandoffManifest`.
struct HandoffFile: Codable, Identifiable, Hashable {
    /// Filename relative to the handoff's staging directory.
    let name: String
    let kind: HandoffFileKind
    /// Display name to show the user, if different from the on-disk name.
    let displayName: String?

    var id: String { name }
}

/// JSON manifest the Share Extension drops into each handoff directory so the
/// main app can enumerate staged files without trusting directory scanning or
/// percent-encoded filename lists in the deep-link URL.
struct HandoffManifest: Codable {
    let version: Int
    let createdAt: Date
    let agentId: UUID
    let files: [HandoffFile]

    static let currentVersion = 1
    static let filename = "manifest.json"

    /// Load the manifest from a staging directory.
    static func load(from directory: URL) -> HandoffManifest? {
        let url = directory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HandoffManifest.self, from: data)
    }

    /// Persist the manifest into a staging directory.
    func write(to directory: URL) throws {
        let url = directory.appendingPathComponent(HandoffManifest.filename)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
