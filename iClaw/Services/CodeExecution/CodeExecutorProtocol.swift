import Foundation

enum ExecutionMode: String, Sendable {
    case repr
    case script
}

struct ExecutionResult: Sendable {
    let stdout: String
    let stderr: String
    let repr: String?
    let exitCode: Int

    static func success(stdout: String = "", stderr: String = "", repr: String? = nil) -> ExecutionResult {
        ExecutionResult(stdout: stdout, stderr: stderr, repr: repr, exitCode: 0)
    }

    static func failure(stderr: String, exitCode: Int = 1) -> ExecutionResult {
        ExecutionResult(stdout: "", stderr: stderr, repr: nil, exitCode: exitCode)
    }
}

protocol CodeExecutor: Sendable {
    var language: String { get }
    var isAvailable: Bool { get }
    func execute(code: String, mode: ExecutionMode) async throws -> ExecutionResult
}

enum CodeExecutorError: LocalizedError {
    case executorNotAvailable(String)
    case executionFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .executorNotAvailable(let lang): return "\(lang) executor is not available"
        case .executionFailed(let msg): return "Execution failed: \(msg)"
        case .timeout: return "Execution timed out"
        }
    }
}
