import Foundation
import JavaScriptCore
import os.log

private let jsLog = OSLog(subsystem: "com.iclaw.javascript", category: "executor")

/// Native JavaScript executor backed by JavaScriptCore.
/// Provides console capture, timer polyfills, and synchronous HTTP bridge.
final class JavaScriptExecutor: CodeExecutor, @unchecked Sendable {
    let language = "javascript"
    let isAvailable = true

    func execute(code: String, mode: ExecutionMode, timeout: TimeInterval) async throws -> ExecutionResult {
        os_log(.info, log: jsLog, "[JS] execute called, mode=%{public}@, timeout=%{public}f", mode.rawValue, timeout)

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            let lock = NSLock()

            func resumeOnce(with result: Result<ExecutionResult, Error>) {
                lock.lock()
                guard !resumed else { lock.unlock(); return }
                resumed = true
                lock.unlock()
                continuation.resume(with: result)
            }

            let workItem = DispatchWorkItem {
                let result = Self.run(code: code, mode: mode)
                resumeOnce(with: .success(result))
            }

            DispatchQueue.global(qos: .userInitiated).async(execute: workItem)

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                workItem.cancel()
                resumeOnce(with: .failure(CodeExecutorError.timeout))
            }
        }
    }

    // MARK: - Core Execution

    private static func run(code: String, mode: ExecutionMode) -> ExecutionResult {
        let ctx = JSContext()!
        var jsException: String?

        ctx.exceptionHandler = { _, exception in
            jsException = exception?.toString()
        }

        injectRuntime(ctx)

        switch mode {
        case .repr:
            let wrapped = """
            (function() {
                try {
                    var __result = eval(\(escapeForJS(code)));
                    return __result;
                } catch(e) {
                    __stderr += String(e) + '\\n';
                    return undefined;
                }
            })()
            """
            let result = ctx.evaluateScript(wrapped)

            let stdout = ctx.evaluateScript("__stdout")?.toString() ?? ""
            let stderr = ctx.evaluateScript("__stderr")?.toString() ?? ""

            if let ex = jsException {
                return .failure(stderr: stderr.isEmpty ? ex : stderr + "\n" + ex)
            }

            let repr = formatJSValue(result, in: ctx)
            return .success(stdout: stdout, stderr: stderr, repr: repr)

        case .script:
            ctx.evaluateScript(code)

            let stdout = ctx.evaluateScript("__stdout")?.toString() ?? ""
            let stderr = ctx.evaluateScript("__stderr")?.toString() ?? ""

            if let ex = jsException {
                let combinedErr = stderr.isEmpty ? ex : stderr + "\n" + ex
                return .failure(stderr: combinedErr)
            }
            return .success(stdout: stdout, stderr: stderr)
        }
    }

    // MARK: - Runtime Injection

    private static func injectRuntime(_ ctx: JSContext) {
        ctx.evaluateScript(Self.runtimeScript)
        injectNetworkBridge(ctx)
    }

    private static func injectNetworkBridge(_ ctx: JSContext) {
        let httpRequest: @convention(block) (String, String, String, String) -> String = { urlString, method, body, headersJSON in
            guard let url = URL(string: urlString) else {
                return "{\"error\":\"Invalid URL: \(urlString)\",\"status\":0}"
            }

            var request = URLRequest(url: url)
            request.httpMethod = method.uppercased()

            if !body.isEmpty && method.uppercased() != "GET" && method.uppercased() != "HEAD" {
                request.httpBody = body.data(using: .utf8)
            }

            if let data = headersJSON.data(using: .utf8),
               let headers = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }

            let sem = DispatchSemaphore(value: 0)
            var responseText = ""
            var statusCode = 0

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                defer { sem.signal() }
                if let httpResp = response as? HTTPURLResponse {
                    statusCode = httpResp.statusCode
                }
                if let error {
                    responseText = "{\"error\":\"\(error.localizedDescription)\"}"
                } else if let data, let str = String(data: data, encoding: .utf8) {
                    responseText = str
                }
            }
            task.resume()
            _ = sem.wait(timeout: .now() + 30)

            let meta = "{\"status\":\(statusCode),\"ok\":\(statusCode >= 200 && statusCode < 300)}"
            return "\(meta)\n\(responseText)"
        }
        ctx.setObject(httpRequest, forKeyedSubscript: "__native_http" as NSString)
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

    private static func formatJSValue(_ value: JSValue?, in ctx: JSContext) -> String {
        guard let value else { return "undefined" }
        if value.isUndefined { return "undefined" }
        if value.isNull { return "null" }

        let jsonAttempt = ctx.evaluateScript("""
        (function(v) {
            if (v === undefined) return 'undefined';
            if (v === null) return 'null';
            if (typeof v === 'function') return v.toString();
            try { return JSON.stringify(v, null, 2); } catch(e) { return String(v); }
        })
        """)
        if let fn = jsonAttempt, !fn.isUndefined {
            let result = fn.call(withArguments: [value])
            return result?.toString() ?? String(describing: value)
        }

        return value.toString()
    }

    // MARK: - JavaScript Runtime

    static let runtimeScript: String = """
    var __stdout = '';
    var __stderr = '';

    // --- Console ---
    var console = {
        log: function() {
            var args = Array.prototype.slice.call(arguments);
            __stdout += args.map(function(a) {
                if (a === null) return 'null';
                if (a === undefined) return 'undefined';
                if (typeof a === 'object') { try { return JSON.stringify(a); } catch(e) { return String(a); } }
                return String(a);
            }).join(' ') + '\\n';
        },
        warn: function() {
            var args = Array.prototype.slice.call(arguments);
            __stderr += '[warn] ' + args.map(String).join(' ') + '\\n';
        },
        error: function() {
            var args = Array.prototype.slice.call(arguments);
            __stderr += '[error] ' + args.map(String).join(' ') + '\\n';
        },
        info: function() { console.log.apply(null, arguments); },
        debug: function() { console.log.apply(null, arguments); },
        table: function(data) { console.log(JSON.stringify(data, null, 2)); },
        time: function() {},
        timeEnd: function() {},
        assert: function(cond, msg) { if (!cond) __stderr += '[assert] ' + (msg || 'Assertion failed') + '\\n'; },
        dir: function(obj) { console.log(JSON.stringify(obj, null, 2)); },
        clear: function() { __stdout = ''; __stderr = ''; }
    };

    function print() {
        console.log.apply(null, arguments);
    }

    // --- Timer polyfills (synchronous: run immediately) ---
    var __timerId = 0;
    function setTimeout(fn, delay) { try { fn(); } catch(e) {} return ++__timerId; }
    function setInterval(fn, delay) { return ++__timerId; }
    function clearTimeout(id) {}
    function clearInterval(id) {}

    // --- Network: fetch ---
    function fetch(url, options) {
        options = options || {};
        var method = (options.method || 'GET').toUpperCase();
        var body = options.body || '';
        var headers = options.headers || {};
        var headersJSON = JSON.stringify(headers);
        var raw = __native_http(url, method, body, headersJSON);
        var idx = raw.indexOf('\\n');
        var metaStr = raw.substring(0, idx);
        var bodyStr = raw.substring(idx + 1);
        var meta = JSON.parse(metaStr);
        return {
            ok: meta.ok,
            status: meta.status,
            text: bodyStr,
            json: function() { return JSON.parse(bodyStr); },
            headers: {},
            statusText: meta.ok ? 'OK' : 'Error'
        };
    }

    // --- Polyfills for common missing APIs ---
    if (typeof globalThis === 'undefined') { var globalThis = this; }

    if (typeof TextEncoder === 'undefined') {
        function TextEncoder() {}
        TextEncoder.prototype.encode = function(s) {
            var arr = [];
            for (var i = 0; i < s.length; i++) {
                var c = s.charCodeAt(i);
                if (c < 128) arr.push(c);
                else if (c < 2048) { arr.push(192 | (c >> 6)); arr.push(128 | (c & 63)); }
                else { arr.push(224 | (c >> 12)); arr.push(128 | ((c >> 6) & 63)); arr.push(128 | (c & 63)); }
            }
            return arr;
        };
    }

    if (typeof TextDecoder === 'undefined') {
        function TextDecoder() {}
        TextDecoder.prototype.decode = function(arr) {
            if (typeof arr === 'string') return arr;
            var s = '';
            for (var i = 0; i < arr.length; i++) s += String.fromCharCode(arr[i]);
            return s;
        };
    }

    if (typeof atob === 'undefined') {
        var __b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
        function atob(s) {
            var o = ''; s = s.replace(/=+$/, '');
            for (var i = 0; i < s.length; i += 4) {
                var b = (__b64chars.indexOf(s[i]) << 18) | (__b64chars.indexOf(s[i+1]) << 12) |
                        (__b64chars.indexOf(s[i+2] || '=') << 6) | __b64chars.indexOf(s[i+3] || '=');
                o += String.fromCharCode((b >> 16) & 255);
                if (s[i+2] !== undefined) o += String.fromCharCode((b >> 8) & 255);
                if (s[i+3] !== undefined) o += String.fromCharCode(b & 255);
            }
            return o;
        }
        function btoa(s) {
            var o = '';
            for (var i = 0; i < s.length; i += 3) {
                var a = s.charCodeAt(i), b = s.charCodeAt(i+1), c = s.charCodeAt(i+2);
                var bits = (a << 16) | ((b || 0) << 8) | (c || 0);
                o += __b64chars[(bits >> 18) & 63] + __b64chars[(bits >> 12) & 63];
                o += (i + 1 < s.length) ? __b64chars[(bits >> 6) & 63] : '=';
                o += (i + 2 < s.length) ? __b64chars[bits & 63] : '=';
            }
            return o;
        }
    }
    """
}
