import Foundation
import UIKit

/// Implements file management tool calls for an agent's file folder.
struct FileTools {
    let agent: Agent
    private let fm = AgentFileManager.shared

    private var agentId: UUID { fm.resolveAgentId(for: agent) }

    func listFiles(arguments: [String: Any]) -> String {
        let files = fm.listFiles(agentId: agentId)
        if files.isEmpty {
            return "Agent file folder is empty."
        }
        var lines = ["Files (\(files.count)):"]
        for f in files {
            let badge = f.isImage ? " [image]" : ""
            lines.append("  \(f.name) — \(f.formattedSize)\(badge)  (modified: \(Self.dateFormatter.string(from: f.modifiedAt)))")
        }
        return lines.joined(separator: "\n")
    }

    func readFile(arguments: [String: Any]) -> String {
        guard let name = arguments["name"] as? String, !name.isEmpty else {
            return "[Error] Missing required parameter: name"
        }
        let mode = (arguments["mode"] as? String) ?? "text"
        do {
            let data = try fm.readFile(agentId: agentId, name: name)
            if mode == "base64" {
                return data.base64EncodedString()
            }
            if let text = String(data: data, encoding: .utf8) {
                return text
            }
            return "[Error] File is binary; use mode='base64' to read."
        } catch {
            return "[Error] \(error.localizedDescription)"
        }
    }

    func writeFile(arguments: [String: Any]) -> String {
        guard let name = arguments["name"] as? String, !name.isEmpty else {
            return "[Error] Missing required parameter: name"
        }
        let content = arguments["content"] as? String ?? ""
        let encoding = (arguments["encoding"] as? String) ?? "text"

        let data: Data
        if encoding == "base64" {
            guard let decoded = Data(base64Encoded: content, options: .ignoreUnknownCharacters) else {
                return "[Error] Invalid base64 content."
            }
            data = decoded
        } else {
            data = Data(content.utf8)
        }

        do {
            try fm.writeFile(agentId: agentId, name: name, data: data)
            return "File '\(name)' written successfully (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))."
        } catch {
            return "[Error] \(error.localizedDescription)"
        }
    }

    func deleteFile(arguments: [String: Any]) -> String {
        guard let name = arguments["name"] as? String, !name.isEmpty else {
            return "[Error] Missing required parameter: name"
        }
        do {
            try fm.deleteFile(agentId: agentId, name: name)
            return "File '\(name)' deleted."
        } catch {
            return "[Error] \(error.localizedDescription)"
        }
    }

    func fileInfo(arguments: [String: Any]) -> String {
        guard let name = arguments["name"] as? String, !name.isEmpty else {
            return "[Error] Missing required parameter: name"
        }
        guard let info = fm.fileInfo(agentId: agentId, name: name) else {
            return "[Error] File not found: \(name)"
        }
        return """
        name: \(info.name)
        size: \(info.formattedSize)
        is_image: \(info.isImage)
        created: \(Self.dateFormatter.string(from: info.createdAt))
        modified: \(Self.dateFormatter.string(from: info.modifiedAt))
        """
    }

    // MARK: - Multimodal

    private static let supportedImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif"
    ]

    func attachMedia(arguments: [String: Any]) -> ToolCallResult {
        guard let name = arguments["name"] as? String, !name.isEmpty else {
            return ToolCallResult("[Error] Missing required parameter: name")
        }

        let ext = (name as NSString).pathExtension.lowercased()
        let modality = arguments["modality"] as? String ?? detectModality(ext: ext)

        switch modality {
        case "image":
            guard Self.supportedImageExtensions.contains(ext) else {
                return ToolCallResult("[Error] Unsupported image format '.\(ext)'. Supported: jpg, png, gif, webp, heic, bmp, tiff.")
            }
            do {
                let data = try fm.readFile(agentId: agentId, name: name)
                let mimeType = mimeTypeForExtension(ext)
                let width: Int
                let height: Int
                let thumbnail: Data
                if let image = UIImage(data: data) {
                    width = Int(image.size.width * image.scale)
                    height = Int(image.size.height * image.scale)
                    thumbnail = ImageAttachment.generateThumbnail(from: image)
                } else {
                    width = 512; height = 512
                    thumbnail = Data()
                }
                let ref = AgentFileManager.makeFileReference(agentId: agentId, filename: name)
                let attachment = ImageAttachment(
                    id: UUID(),
                    imageData: thumbnail,
                    mimeType: mimeType,
                    width: width,
                    height: height,
                    fileReference: ref
                )
                return ToolCallResult(
                    "Image '\(name)' (\(width)x\(height), \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))) attached to conversation.",
                    imageAttachments: [attachment]
                )
            } catch {
                return ToolCallResult("[Error] \(error.localizedDescription)")
            }

        case "audio":
            return ToolCallResult("[Error] Audio modality is not yet supported. Currently only image files can be attached.")

        case "video":
            return ToolCallResult("[Error] Video modality is not yet supported. Currently only image files can be attached.")

        default:
            return ToolCallResult("[Error] Unknown modality '\(modality)'. Supported: image. Planned: audio, video.")
        }
    }

    private func detectModality(ext: String) -> String {
        if Self.supportedImageExtensions.contains(ext) { return "image" }
        let audioExts: Set<String> = ["mp3", "wav", "m4a", "aac", "ogg", "flac", "aiff"]
        if audioExts.contains(ext) { return "audio" }
        let videoExts: Set<String> = ["mp4", "mov", "avi", "mkv", "webm", "m4v"]
        if videoExts.contains(ext) { return "video" }
        return "unknown"
    }

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext {
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic", "heif": return "image/heic"
        case "bmp": return "image/bmp"
        case "tiff", "tif": return "image/tiff"
        default: return "image/jpeg"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
