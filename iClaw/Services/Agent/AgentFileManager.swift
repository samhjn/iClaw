import Foundation
import UIKit
import os.log

private let fileLog = OSLog(subsystem: "com.iclaw.files", category: "agent-file-manager")

/// Manages per-agent file storage on disk.
///
/// Directory layout: `<Documents>/AgentFiles/<agentId>/`
/// Sub-agents share the top-level parent agent's folder via `resolveAgentId(for:)`.
final class AgentFileManager {

    static let shared = AgentFileManager()

    private let fm = FileManager.default

    private var rootDirectory: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentFiles", isDirectory: true)
    }

    // MARK: - Agent ID Resolution

    /// Walk the parentAgent chain to find the top-level (root) agent ID.
    /// Sub-agents share the root agent's file folder.
    ///
    /// - Important: This traverses SwiftData `@Relationship` properties (`parentAgent`).
    ///   All callers must be on `@MainActor` to avoid concurrent relationship faulting.
    func resolveAgentId(for agent: Agent) -> UUID {
        var current = agent
        while let parent = current.parentAgent {
            current = parent
        }
        return current.id
    }

    // MARK: - Directory

    func agentDirectory(for agentId: UUID) -> URL {
        rootDirectory.appendingPathComponent(agentId.uuidString, isDirectory: true)
    }

    @discardableResult
    private func ensureDirectory(for agentId: UUID) throws -> URL {
        let dir = agentDirectory(for: agentId)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - File CRUD

    func listFiles(agentId: UUID) -> [FileInfo] {
        let dir = agentDirectory(for: agentId)
        guard let contents = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents.compactMap { url in
            guard let attrs = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey]) else {
                return nil
            }
            let name = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            return FileInfo(
                name: name,
                size: Int64(attrs.fileSize ?? 0),
                createdAt: attrs.creationDate ?? Date(),
                modifiedAt: attrs.contentModificationDate ?? Date(),
                isImage: Self.imageExtensions.contains(ext),
                isVideo: Self.videoExtensions.contains(ext)
            )
        }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    @discardableResult
    func writeFile(agentId: UUID, name: String, data: Data) throws -> URL {
        guard Self.isSafeFilename(name) else {
            throw FileToolError.unsafeFilename(name)
        }
        let dir = try ensureDirectory(for: agentId)
        let url = dir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    func readFile(agentId: UUID, name: String) throws -> Data {
        guard Self.isSafeFilename(name) else {
            throw FileToolError.unsafeFilename(name)
        }
        let url = agentDirectory(for: agentId).appendingPathComponent(name)
        guard fm.fileExists(atPath: url.path) else {
            throw FileToolError.fileNotFound(name)
        }
        return try Data(contentsOf: url)
    }

    func deleteFile(agentId: UUID, name: String) throws {
        guard Self.isSafeFilename(name) else {
            throw FileToolError.unsafeFilename(name)
        }
        let url = agentDirectory(for: agentId).appendingPathComponent(name)
        guard fm.fileExists(atPath: url.path) else {
            throw FileToolError.fileNotFound(name)
        }
        try fm.removeItem(at: url)
    }

    func fileExists(agentId: UUID, name: String) -> Bool {
        guard Self.isSafeFilename(name) else { return false }
        return fm.fileExists(atPath: agentDirectory(for: agentId).appendingPathComponent(name).path)
    }

    func fileURL(agentId: UUID, name: String) -> URL {
        agentDirectory(for: agentId).appendingPathComponent(name)
    }

    func fileInfo(agentId: UUID, name: String) -> FileInfo? {
        guard Self.isSafeFilename(name) else { return nil }
        let url = agentDirectory(for: agentId).appendingPathComponent(name)
        guard let attrs = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey]),
              fm.fileExists(atPath: url.path) else { return nil }
        let ext = url.pathExtension.lowercased()
        return FileInfo(
            name: name,
            size: Int64(attrs.fileSize ?? 0),
            createdAt: attrs.creationDate ?? Date(),
            modifiedAt: attrs.contentModificationDate ?? Date(),
            isImage: Self.imageExtensions.contains(ext),
            isVideo: Self.videoExtensions.contains(ext)
        )
    }

    // MARK: - Image Support

    /// Save an image to the agent's folder, returning a `fileReference` string.
    /// The full-resolution image is written to disk; the caller should store a thumbnail in `imageData`.
    func saveImage(_ imageData: Data, mimeType: String, agentId: UUID) -> String? {
        let ext = Self.extensionForMime(mimeType)
        let name = "img_\(UUID().uuidString.prefix(8)).\(ext)"
        do {
            try writeFile(agentId: agentId, name: name, data: imageData)
            os_log(.info, log: fileLog, "Saved image %{public}@ for agent %{public}@", name, agentId.uuidString)
            return Self.makeFileReference(agentId: agentId, filename: name)
        } catch {
            os_log(.error, log: fileLog, "Failed to save image: %{public}@", error.localizedDescription)
            return nil
        }
    }

    /// Save video data to the agent's file directory and return the `agentfile://` reference.
    func saveVideo(_ videoData: Data, extension ext: String = "mp4", agentId: UUID) -> String? {
        let name = "vid_\(UUID().uuidString.prefix(8)).\(ext)"
        do {
            try writeFile(agentId: agentId, name: name, data: videoData)
            os_log(.info, log: fileLog, "Saved video %{public}@ for agent %{public}@", name, agentId.uuidString)
            return Self.makeFileReference(agentId: agentId, filename: name)
        } catch {
            os_log(.error, log: fileLog, "Failed to save video: %{public}@", error.localizedDescription)
            return nil
        }
    }

    /// Load image data from a `agentfile://` reference.
    func loadImageData(from fileReference: String) -> Data? {
        guard let (agentId, filename) = Self.parseFileReference(fileReference) else { return nil }
        return try? readFile(agentId: agentId, name: filename)
    }

    // MARK: - File Reference

    static let fileReferenceScheme = "agentfile"

    static func makeFileReference(agentId: UUID, filename: String) -> String {
        "\(fileReferenceScheme)://\(agentId.uuidString)/\(filename)"
    }

    /// Parse `agentfile://<agentId>/<filename>` → (agentId, filename)
    static func parseFileReference(_ ref: String) -> (UUID, String)? {
        guard ref.hasPrefix("\(fileReferenceScheme)://") else { return nil }
        let path = String(ref.dropFirst("\(fileReferenceScheme)://".count))
        guard let slashIdx = path.firstIndex(of: "/") else { return nil }
        let idStr = String(path[..<slashIdx])
        let filename = String(path[path.index(after: slashIdx)...])
        guard let uuid = UUID(uuidString: idStr), !filename.isEmpty, isSafeFilename(filename) else { return nil }
        return (uuid, filename)
    }

    // MARK: - Cleanup

    func cleanupAgentFiles(agentId: UUID) {
        let dir = agentDirectory(for: agentId)
        try? fm.removeItem(at: dir)
        os_log(.info, log: fileLog, "Cleaned up files for agent %{public}@", agentId.uuidString)
    }

    /// Remove directories that don't correspond to any known agent ID.
    func cleanupOrphanDirectories(knownAgentIds: Set<UUID>) {
        guard let contents = try? fm.contentsOfDirectory(
            at: rootDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }
        for url in contents {
            if let uuid = UUID(uuidString: url.lastPathComponent), !knownAgentIds.contains(uuid) {
                try? fm.removeItem(at: url)
                os_log(.info, log: fileLog, "Removed orphan dir %{public}@", url.lastPathComponent)
            }
        }
    }

    // MARK: - Safety

    static func isSafeFilename(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 255 else { return false }
        if name.contains("/") || name.contains("\\") || name.contains("\0") { return false }
        if name == "." || name == ".." || name.hasPrefix("..") { return false }
        return true
    }

    // MARK: - Helpers

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif", "svg"
    ]

    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "webm", "avi", "mkv"
    ]

    private static func extensionForMime(_ mime: String) -> String {
        switch mime.lowercased() {
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/heic": return "heic"
        case "image/bmp": return "bmp"
        case "image/tiff": return "tiff"
        case "image/svg+xml": return "svg"
        default: return "jpg"
        }
    }
}

// MARK: - FileInfo

struct FileInfo: Identifiable {
    let name: String
    let size: Int64
    let createdAt: Date
    let modifiedAt: Date
    let isImage: Bool
    let isVideo: Bool

    var id: String { name }

    var isTextPreviewable: Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return TextFilePreviewCoordinator.textExtensions.contains(ext)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - Errors

enum FileToolError: LocalizedError {
    case unsafeFilename(String)
    case fileNotFound(String)
    case fileAlreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .unsafeFilename(let name): return "Unsafe filename: \(name)"
        case .fileNotFound(let name): return "File not found: \(name)"
        case .fileAlreadyExists(let name): return "File already exists: \(name)"
        }
    }
}
