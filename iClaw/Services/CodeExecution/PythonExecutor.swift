import Foundation

/// Legacy PythonExecutor stub. Python execution is handled by JSCorePythonExecutor.
/// PythonKit requires a native Python dylib unavailable on iOS, so this is kept
/// only as a no-op placeholder.
final class PythonExecutor: CodeExecutor, @unchecked Sendable {
    let language = "python"
    let isAvailable = false

    func execute(code: String, mode: ExecutionMode) async throws -> ExecutionResult {
        throw CodeExecutorError.executorNotAvailable(
            "Native Python is not available on iOS. Use JSCorePythonExecutor instead."
        )
    }
}
