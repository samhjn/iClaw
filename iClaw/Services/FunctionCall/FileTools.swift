import Foundation

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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
