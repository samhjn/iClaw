import Foundation

#if canImport(PythonKit)
import PythonKit

final class PythonExecutor: CodeExecutor, @unchecked Sendable {
    let language = "python"

    var isAvailable: Bool {
        do {
            _ = try Python.attemptImport("sys")
            return true
        } catch {
            return false
        }
    }

    func execute(code: String, mode: ExecutionMode) async throws -> ExecutionResult {
        guard isAvailable else {
            throw CodeExecutorError.executorNotAvailable("python")
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.runPython(code: code, mode: mode)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runPython(code: String, mode: ExecutionMode) throws -> ExecutionResult {
        let sys = try Python.attemptImport("sys")
        let io = try Python.attemptImport("io")

        let oldStdout = sys.stdout
        let oldStderr = sys.stderr
        let capturedStdout = io.StringIO()
        let capturedStderr = io.StringIO()
        sys.stdout = capturedStdout
        sys.stderr = capturedStderr

        defer {
            sys.stdout = oldStdout
            sys.stderr = oldStderr
        }

        let builtins = Python.import("builtins")

        switch mode {
        case .repr:
            let result = builtins.eval(code)
            let stdout = String(capturedStdout.getvalue()) ?? ""
            let stderr = String(capturedStderr.getvalue()) ?? ""
            let repr = String(builtins.repr(result)) ?? String(describing: result)
            return .success(stdout: stdout, stderr: stderr, repr: repr)

        case .script:
            builtins.exec(code)
            let stdout = String(capturedStdout.getvalue()) ?? ""
            let stderr = String(capturedStderr.getvalue()) ?? ""
            return .success(stdout: stdout, stderr: stderr)
        }
    }
}

#else

final class PythonExecutor: CodeExecutor, @unchecked Sendable {
    let language = "python"
    let isAvailable = false

    func execute(code: String, mode: ExecutionMode) async throws -> ExecutionResult {
        throw CodeExecutorError.executorNotAvailable(
            "PythonKit is not available. Build with PythonKit framework to enable Python execution."
        )
    }
}

#endif
