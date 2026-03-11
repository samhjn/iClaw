import Foundation

// CodeExecutor registry for managing multiple executor types
final class CodeExecutorRegistry: @unchecked Sendable {
    static let shared = CodeExecutorRegistry()

    private var executors: [String: CodeExecutor] = [:]

    private init() {
        // JSCorePythonExecutor is the primary Python executor on iOS.
        // PythonKit requires a native Python dylib which is unavailable on iOS,
        // and its library loader uses try! which crashes before we can catch.
        let jsCoreExecutor = JSCorePythonExecutor()
        register(jsCoreExecutor)
    }

    func register(_ executor: CodeExecutor) {
        executors[executor.language] = executor
    }

    func executor(for language: String) -> CodeExecutor? {
        executors[language]
    }

    func availableLanguages() -> [String] {
        executors.filter { $0.value.isAvailable }.map { $0.key }
    }

    func defaultExecutor() -> CodeExecutor {
        executors["python"] ?? JSCorePythonExecutor()
    }
}
