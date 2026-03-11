import Foundation
import SwiftData

struct CodeExecutionTools {
    let agent: Agent
    let modelContext: ModelContext
    let executor: CodeExecutor

    func executePython(arguments: [String: Any]) async -> String {
        guard let code = arguments["code"] as? String else {
            return "[Error] Missing required parameter: code"
        }

        let modeStr = arguments["mode"] as? String ?? "script"
        let mode: ExecutionMode = modeStr == "repr" ? .repr : .script
        let timeout = resolveTimeout(arguments: arguments)

        do {
            let result = try await executor.execute(code: code, mode: mode, timeout: timeout)
            var output = ""
            if !result.stdout.isEmpty {
                output += result.stdout
            }
            if !result.stderr.isEmpty {
                if !output.isEmpty { output += "\n" }
                output += "[stderr] \(result.stderr)"
            }
            if let repr = result.repr {
                if !output.isEmpty { output += "\n" }
                output += repr
            }
            return output.isEmpty ? "(No output)" : output
        } catch CodeExecutorError.timeout {
            return "[Error] Execution timed out after \(Int(timeout))s"
        } catch {
            return "[Error] \(error.localizedDescription)"
        }
    }

    /// Resolve timeout in order: tool call argument > agent config > default (60s).
    /// Clamped to [1, 300] seconds.
    private func resolveTimeout(arguments: [String: Any]) -> TimeInterval {
        if let t = arguments["timeout"] as? Double, t > 0 {
            return min(max(t, 1), 300)
        }
        if let t = arguments["timeout"] as? Int, t > 0 {
            return min(max(TimeInterval(t), 1), 300)
        }
        if let config = agent.customConfigs.first(where: { $0.key == "python_timeout" }),
           let t = Double(config.content), t > 0 {
            return min(max(t, 1), 300)
        }
        return 60
    }

    func saveCode(arguments: [String: Any]) -> String {
        guard let name = arguments["name"] as? String else {
            return "[Error] Missing required parameter: name"
        }
        guard let code = arguments["code"] as? String else {
            return "[Error] Missing required parameter: code"
        }
        let language = arguments["language"] as? String ?? "python"

        if let existing = agent.codeSnippets.first(where: { $0.name == name }) {
            existing.code = code
            existing.language = language
            existing.updatedAt = Date()
        } else {
            let snippet = CodeSnippet(name: name, language: language, code: code, agent: agent)
            modelContext.insert(snippet)
        }
        try? modelContext.save()
        return "Saved code snippet '\(name)' (\(language), \(code.count) chars)"
    }

    func loadCode(arguments: [String: Any]) -> String {
        guard let name = arguments["name"] as? String else {
            return "[Error] Missing required parameter: name"
        }

        if let snippet = agent.codeSnippets.first(where: { $0.name == name }) {
            return "[\(snippet.language)] \(snippet.name):\n\(snippet.code)"
        } else {
            let available = agent.codeSnippets.map { $0.name }.joined(separator: ", ")
            return "[Error] Code snippet '\(name)' not found. Available: \(available.isEmpty ? "(none)" : available)"
        }
    }

    func listCode() -> String {
        let snippets = agent.codeSnippets
        if snippets.isEmpty {
            return "(No saved code snippets)"
        }
        return snippets.map { "- \($0.name) [\($0.language)] (\($0.code.count) chars)" }.joined(separator: "\n")
    }
}
