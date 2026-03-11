import Foundation
import os.log

private let mpyLog = OSLog(subsystem: "com.iclaw.micropython", category: "executor")

/// A Python executor backed by an embedded MicroPython C interpreter.
final class MicroPythonExecutor: CodeExecutor, @unchecked Sendable {
    let language = "python"
    let isAvailable = true

    private static let httpCallbackRegistered: Bool = {
        os_log(.error, log: mpyLog, "[MPY-Swift] Registering HTTP callback")
        let callback: @convention(c) (
            UnsafePointer<CChar>?,
            UnsafePointer<CChar>?,
            UnsafePointer<CChar>?,
            UnsafePointer<CChar>?
        ) -> UnsafePointer<CChar>? = { urlPtr, methodPtr, bodyPtr, headersPtr in
            guard let urlPtr, let methodPtr else { return nil }
            let urlString = String(cString: urlPtr)
            let method = String(cString: methodPtr)
            let body = bodyPtr.map { String(cString: $0) } ?? ""
            let headersJSON = headersPtr.map { String(cString: $0) } ?? "{}"

            return performSyncHTTPRequest(
                url: urlString,
                method: method,
                body: body,
                headersJSON: headersJSON
            )
        }
        mpy_set_http_callback(callback)
        os_log(.error, log: mpyLog, "[MPY-Swift] HTTP callback registered")
        return true
    }()

    private static var lastHTTPResponse: UnsafeMutablePointer<CChar>?

    private static func performSyncHTTPRequest(
        url urlString: String,
        method: String,
        body: String,
        headersJSON: String
    ) -> UnsafePointer<CChar>? {
        guard let url = URL(string: urlString) else {
            return storeResponse("{\"error\": \"Invalid URL\"}")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        if !body.isEmpty && method != "GET" && method != "HEAD" {
            request.httpBody = body.data(using: .utf8)
        }

        if let data = headersJSON.data(using: .utf8),
           let headers = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        let semaphore = DispatchSemaphore(value: 0)
        var responseBody = ""

        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            defer { semaphore.signal() }
            if let error {
                responseBody = "{\"error\": \"\(error.localizedDescription)\"}"
            } else if let data, let str = String(data: data, encoding: .utf8) {
                responseBody = str
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 30)
        return storeResponse(responseBody)
    }

    private static func storeResponse(_ str: String) -> UnsafePointer<CChar>? {
        lastHTTPResponse?.deallocate()
        let cStr = str.utf8CString
        let buf = UnsafeMutablePointer<CChar>.allocate(capacity: cStr.count)
        for (i, byte) in cStr.enumerated() {
            buf[i] = byte
        }
        lastHTTPResponse = buf
        return UnsafePointer(buf)
    }

    // MARK: - Execution with three-tier timeout

    func execute(code: String, mode: ExecutionMode, timeout: TimeInterval) async throws -> ExecutionResult {
        os_log(.error, log: mpyLog, "[MPY-Swift] execute called, mode=%{public}@, timeout=%{public}f", mode.rawValue, timeout)
        _ = Self.httpCallbackRegistered
        mpy_clear_timeout()

        os_log(.error, log: mpyLog, "[MPY-Swift] dispatching execution")

        return await withCheckedContinuation { continuation in
            let done = DispatchSemaphore(value: 0)
            var execResult: ExecutionResult?

            DispatchQueue.global(qos: .userInitiated).async {
                os_log(.error, log: mpyLog, "[MPY-Swift] background thread: calling executeSync")
                execResult = Self.executeSync(code: code, mode: mode)
                os_log(.error, log: mpyLog, "[MPY-Swift] background thread: executeSync returned, success=%{public}d", execResult?.exitCode == 0 ? 1 : 0)
                done.signal()
            }

            DispatchQueue.global(qos: .utility).async {
                os_log(.error, log: mpyLog, "[MPY-Swift] timeout thread: waiting %.0fs", timeout)
                let waitResult = done.wait(timeout: .now() + timeout)

                if waitResult == .success {
                    os_log(.error, log: mpyLog, "[MPY-Swift] timeout thread: completed within timeout")
                    mpy_clear_timeout()
                    continuation.resume(returning: execResult ?? .failure(stderr: "Unknown error"))
                    return
                }

                os_log(.error, log: mpyLog, "[MPY-Swift] timeout thread: SOFT TIMEOUT, requesting VM stop")
                mpy_request_timeout()
                let graceResult = done.wait(timeout: .now() + 3)

                if graceResult == .success {
                    os_log(.error, log: mpyLog, "[MPY-Swift] timeout thread: VM stopped after soft timeout")
                    mpy_clear_timeout()
                    continuation.resume(returning: execResult ?? .failure(
                        stderr: "Execution timed out after \(Int(timeout))s"
                    ))
                    return
                }

                os_log(.error, log: mpyLog, "[MPY-Swift] timeout thread: HARD TIMEOUT, forcing return")
                mpy_clear_timeout()
                continuation.resume(returning: .failure(
                    stderr: "Execution timed out after \(Int(timeout))s (forced termination)"
                ))
            }
        }
    }

    private static func executeSync(code: String, mode: ExecutionMode) -> ExecutionResult {
        os_log(.error, log: mpyLog, "[MPY-Swift] executeSync: mode=%{public}@", mode.rawValue)
        switch mode {
        case .script:
            os_log(.error, log: mpyLog, "[MPY-Swift] executeSync: calling mpy_exec_script")
            let success = mpy_exec_script(code)
            os_log(.error, log: mpyLog, "[MPY-Swift] executeSync: mpy_exec_script returned %{public}d", success ? 1 : 0)
            let stdout = String(cString: mpy_get_stdout())
            let stderr = String(cString: mpy_get_stderr())
            os_log(.error, log: mpyLog, "[MPY-Swift] executeSync: stdout=%{public}d bytes, stderr=%{public}d bytes", stdout.count, stderr.count)
            if success {
                return .success(stdout: stdout, stderr: stderr)
            } else {
                let errMsg = stderr.isEmpty ? "Unknown execution error" : stderr
                return .failure(stderr: errMsg)
            }

        case .repr:
            os_log(.error, log: mpyLog, "[MPY-Swift] executeSync: calling mpy_eval_repr")
            let reprResult = mpy_eval_repr(code)
            os_log(.error, log: mpyLog, "[MPY-Swift] executeSync: mpy_eval_repr returned %{public}@", reprResult != nil ? "non-nil" : "nil")
            let stdout = String(cString: mpy_get_stdout())
            let stderr = String(cString: mpy_get_stderr())
            if let reprPtr = reprResult {
                let reprStr = String(cString: reprPtr)
                return .success(stdout: stdout, stderr: stderr, repr: reprStr)
            } else {
                let errMsg = stderr.isEmpty ? "Expression evaluation failed" : stderr
                return .failure(stderr: errMsg)
            }
        }
    }
}
