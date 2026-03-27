import Foundation
import os.log

private let jsLog = OSLog(subsystem: "com.iclaw.javascript", category: "executor")

/// JavaScript executor backed by a WKWebView sandbox.
/// Console output is captured; a synchronous `fetch` polyfill (via XHR) and
/// common polyfills are injected automatically.
final class JavaScriptExecutor: CodeExecutor, @unchecked Sendable {
    let language = "javascript"
    let isAvailable = true

    func execute(code: String, mode: ExecutionMode, timeout: TimeInterval) async throws -> ExecutionResult {
        try await execute(code: code, mode: mode, timeout: timeout, blockedBridgeActions: [], execId: nil)
    }

    /// Execute JS with per-agent Apple bridge permission enforcement.
    ///
    /// - Parameters:
    ///   - blockedBridgeActions: Bridge actions blocked for this agent (from `ToolCategory.blockedBridgeActions(for:)`).
    ///   - execId: Unique ID for this execution context, used for native-layer permission verification.
    func execute(
        code: String,
        mode: ExecutionMode,
        timeout: TimeInterval,
        blockedBridgeActions: Set<String>,
        execId: String?
    ) async throws -> ExecutionResult {
        os_log(.info, log: jsLog, "[JS] execute called, mode=%{public}@, timeout=%{public}f", mode.rawValue, timeout)

        let effectiveExecId = execId ?? UUID().uuidString
        let script = Self.buildScript(code: code, mode: mode, blockedBridgeActions: blockedBridgeActions, execId: effectiveExecId)

        // Register native-layer permission checker if we have blocked actions
        let needsPermissionRegistration = !blockedBridgeActions.isEmpty
        if needsPermissionRegistration {
            await AppleEcosystemBridge.shared.registerPermissions(execId: effectiveExecId) { action in
                !blockedBridgeActions.contains(action)
            }
        }

        defer {
            if needsPermissionRegistration {
                Task { @MainActor in
                    AppleEcosystemBridge.shared.unregisterPermissions(execId: effectiveExecId)
                }
            }
        }

        // If the WebContent process crashes (OOM, etc.), the runtime auto-recreates.
        // Retry once so transient crashes are transparent to the caller.
        let dict: [String: Any]
        do {
            dict = try await WKWebViewJSRuntime.shared.evaluate(script: script, timeout: timeout)
        } catch CodeExecutorError.runtimeCrashed {
            os_log(.info, log: jsLog, "[JS] Runtime crashed, retrying once after auto-recovery")
            dict = try await WKWebViewJSRuntime.shared.evaluate(script: script, timeout: timeout)
        }

        let stdout = dict["stdout"] as? String ?? ""
        let stderr = dict["stderr"] as? String ?? ""
        let error  = dict["error"] as? String

        if let error, !error.isEmpty {
            let combinedErr = stderr.isEmpty ? error : stderr + "\n" + error
            return .failure(stderr: combinedErr)
        }

        switch mode {
        case .repr:
            let repr = dict["result"] as? String
            return .success(stdout: stdout, stderr: stderr, repr: repr)
        case .script:
            return .success(stdout: stdout, stderr: stderr)
        }
    }

    // MARK: - Script Builder

    private static func buildScript(
        code: String,
        mode: ExecutionMode,
        blockedBridgeActions: Set<String>,
        execId: String
    ) -> String {
        let userCode: String
        switch mode {
        case .repr:
            userCode = """
            var __val = eval(\(escapeForJS(code)));
            if (__val && typeof __val.then === 'function') __val = await __val;
            var __repr = __formatJSValue(__val);
            return {stdout: __stdout, stderr: __stderr, result: __repr, error: null};
            """
        case .script:
            userCode = """
            \(code)
            return {stdout: __stdout, stderr: __stderr, result: null, error: null};
            """
        }

        let preamble = AppleEcosystemBridge.jsPreamble(blockedActions: blockedBridgeActions, execId: execId)

        return """
        \(runtimeScript)
        \(preamble)
        try {
            \(userCode)
        } catch(__e) {
            __appendErr(String(__e) + '\\n');
            return {stdout: __stdout, stderr: __stderr, result: null, error: String(__e)};
        }
        """
    }

    // MARK: - Helpers

    private static func escapeForJS(_ code: String) -> String {
        let escaped = code
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    // MARK: - JavaScript Runtime

    static let runtimeScript: String = """
    var __stdout = '';
    var __stderr = '';

    function __appendOut(s) { __stdout += s; }
    function __appendErr(s) { __stderr += s; }

    // --- Console ---
    var console = {
        log: function() {
            var args = Array.prototype.slice.call(arguments);
            __appendOut(args.map(function(a) {
                if (a === null) return 'null';
                if (a === undefined) return 'undefined';
                if (typeof a === 'object') { try { return JSON.stringify(a); } catch(e) { return String(a); } }
                return String(a);
            }).join(' ') + '\\n');
        },
        warn: function() {
            var args = Array.prototype.slice.call(arguments);
            __appendErr('[warn] ' + args.map(String).join(' ') + '\\n');
        },
        error: function() {
            var args = Array.prototype.slice.call(arguments);
            __appendErr('[error] ' + args.map(String).join(' ') + '\\n');
        },
        info: function() { console.log.apply(null, arguments); },
        debug: function() { console.log.apply(null, arguments); },
        table: function(data) { console.log(JSON.stringify(data, null, 2)); },
        time: function() {},
        timeEnd: function() {},
        assert: function(cond, msg) { if (!cond) __appendErr('[assert] ' + (msg || 'Assertion failed') + '\\n'); },
        dir: function(obj) { console.log(JSON.stringify(obj, null, 2)); },
        clear: function() { __stdout = ''; __stderr = ''; }
    };

    function print() { console.log.apply(null, arguments); }

    // --- Timer polyfills (synchronous: run immediately) ---
    var __timerId = 0;
    function setTimeout(fn, delay) { try { fn(); } catch(e) {} return ++__timerId; }
    function setInterval(fn, delay) { return ++__timerId; }
    function clearTimeout(id) {}
    function clearInterval(id) {}

    // --- Network: synchronous fetch via XMLHttpRequest ---
    function fetch(url, options) {
        options = options || {};
        var method = (options.method || 'GET').toUpperCase();
        var body = options.body || null;
        var headers = options.headers || {};

        var xhr = new XMLHttpRequest();
        xhr.open(method, typeof url === 'string' ? url : url.toString(), false);
        for (var key in headers) {
            if (headers.hasOwnProperty(key)) xhr.setRequestHeader(key, headers[key]);
        }
        try { xhr.send(body); } catch(e) {
            return {ok: false, status: 0, text: '', json: function(){ return {}; },
                    headers: {}, statusText: 'Network error: ' + e.message};
        }
        var responseText = xhr.responseText;
        var status = xhr.status;
        return {
            ok: status >= 200 && status < 300,
            status: status,
            text: responseText,
            json: function() { return JSON.parse(responseText); },
            headers: {},
            statusText: xhr.statusText || (status >= 200 && status < 300 ? 'OK' : 'Error')
        };
    }

    // --- Format JS value for repr ---
    function __formatJSValue(v) {
        if (v === undefined) return 'undefined';
        if (v === null) return 'null';
        if (typeof v === 'function') return v.toString();
        try { return JSON.stringify(v, null, 2); } catch(e) { return String(v); }
    }
    """
}
