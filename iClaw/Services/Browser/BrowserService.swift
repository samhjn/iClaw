import Foundation
import WebKit
import Observation

@MainActor
@Observable
final class BrowserService: NSObject {
    static let shared = BrowserService()

    private(set) var webView: WKWebView
    private(set) var currentURL: URL?
    private(set) var pageTitle: String?
    private(set) var isLoading: Bool = false
    private(set) var canGoBack: Bool = false
    private(set) var canGoForward: Bool = false
    private(set) var estimatedProgress: Double = 0

    // MARK: - Mutex Lock

    private(set) var lockedBySessionId: UUID?
    private(set) var lockedByAgentName: String?
    private(set) var lockTimestamp: Date?

    private static let lockTimeout: TimeInterval = 120

    var isAgentControlled: Bool {
        guard lockedBySessionId != nil, let ts = lockTimestamp else { return false }
        if Date().timeIntervalSince(ts) > Self.lockTimeout {
            forceReleaseLock()
            return false
        }
        return true
    }

    /// Try to acquire the browser lock for an agent session.
    /// Returns nil on success, or an error message if locked by another session.
    func acquireLock(sessionId: UUID, agentName: String) -> String? {
        expireStaleLock()
        if let existing = lockedBySessionId, existing != sessionId {
            return "[Error] Browser is locked by agent \"\(lockedByAgentName ?? "unknown")\" (session \(existing.uuidString.prefix(8))…). Wait for it to finish or ask the user to take over from the Browser tab."
        }
        lockedBySessionId = sessionId
        lockedByAgentName = agentName
        lockTimestamp = Date()
        return nil
    }

    /// Refresh the lock timestamp (called on each successful tool operation).
    func refreshLock(sessionId: UUID) {
        if lockedBySessionId == sessionId {
            lockTimestamp = Date()
        }
    }

    /// Release the lock for a specific session.
    func releaseLock(sessionId: UUID) {
        if lockedBySessionId == sessionId {
            forceReleaseLock()
        }
    }

    /// Force-release regardless of owner (user "Take Over").
    func forceReleaseLock() {
        lockedBySessionId = nil
        lockedByAgentName = nil
        lockTimestamp = nil
    }

    private func expireStaleLock() {
        guard let ts = lockTimestamp else { return }
        if Date().timeIntervalSince(ts) > Self.lockTimeout {
            forceReleaseLock()
        }
    }

    private var navigationContinuation: CheckedContinuation<Bool, Never>?
    private var kvoTokens: [NSKeyValueObservation] = []

    private override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        setupKVO()
    }

    private func setupKVO() {
        kvoTokens.append(webView.observe(\.isLoading) { [weak self] wv, _ in
            Task { @MainActor in self?.isLoading = wv.isLoading }
        })
        kvoTokens.append(webView.observe(\.canGoBack) { [weak self] wv, _ in
            Task { @MainActor in self?.canGoBack = wv.canGoBack }
        })
        kvoTokens.append(webView.observe(\.canGoForward) { [weak self] wv, _ in
            Task { @MainActor in self?.canGoForward = wv.canGoForward }
        })
        kvoTokens.append(webView.observe(\.estimatedProgress) { [weak self] wv, _ in
            Task { @MainActor in self?.estimatedProgress = wv.estimatedProgress }
        })
        kvoTokens.append(webView.observe(\.url) { [weak self] wv, _ in
            Task { @MainActor in self?.currentURL = wv.url }
        })
        kvoTokens.append(webView.observe(\.title) { [weak self] wv, _ in
            Task { @MainActor in self?.pageTitle = wv.title }
        })
    }

    // MARK: - Close / Reset

    func closeAllPages() {
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        currentURL = nil
        pageTitle = nil
    }

    // MARK: - Navigation

    @discardableResult
    func navigate(to urlString: String) async -> Result<String, BrowserError> {
        guard let url = URL(string: urlString) ?? URL(string: "https://\(urlString)") else {
            return .failure(.invalidURL(urlString))
        }
        let request = URLRequest(url: url)
        webView.load(request)
        let success = await waitForNavigation(timeout: 30)
        if success {
            return .success("Navigated to \(webView.url?.absoluteString ?? urlString) — \(webView.title ?? "")")
        } else {
            return .failure(.navigationTimeout)
        }
    }

    func goBack() async -> Result<String, BrowserError> {
        guard webView.canGoBack else { return .failure(.cannotGoBack) }
        webView.goBack()
        let _ = await waitForNavigation(timeout: 15)
        return .success("Went back to \(webView.url?.absoluteString ?? "unknown")")
    }

    func goForward() async -> Result<String, BrowserError> {
        guard webView.canGoForward else { return .failure(.cannotGoForward) }
        webView.goForward()
        let _ = await waitForNavigation(timeout: 15)
        return .success("Went forward to \(webView.url?.absoluteString ?? "unknown")")
    }

    func reload() async -> Result<String, BrowserError> {
        webView.reload()
        let _ = await waitForNavigation(timeout: 15)
        return .success("Reloaded \(webView.url?.absoluteString ?? "unknown")")
    }

    // MARK: - JavaScript Execution

    private static let jsErrorPrefix = "__ICLAW_JS_ERR__:"

    func executeJavaScript(_ script: String) async -> Result<String, BrowserError> {
        // Wrap in try-catch to prevent errors from propagating to the
        // host page's error boundaries (e.g. React ErrorBoundary).
        let safeScript = "try { \(script) } catch(__iclaw_e) { '\(Self.jsErrorPrefix)' + String(__iclaw_e) }"
        do {
            let result = try await webView.evaluateJavaScript(safeScript)
            if let result = result {
                let str = String(describing: result)
                if str.hasPrefix(Self.jsErrorPrefix) {
                    return .failure(.javaScriptError(String(str.dropFirst(Self.jsErrorPrefix.count))))
                }
                return .success(str)
            }
            return .success("(undefined)")
        } catch {
            return .failure(.javaScriptError(error.localizedDescription))
        }
    }

    /// Execute user-provided JavaScript with `return` and `await` support.
    /// Uses `callAsyncJavaScript` which wraps code in an async function body,
    /// and includes try-catch for error isolation from the host page.
    func executeUserJavaScript(_ code: String) async -> Result<String, BrowserError> {
        let wrappedCode = """
        try {
            \(code)
        } catch(__iclaw_e) {
            return '\(Self.jsErrorPrefix)' + String(__iclaw_e);
        }
        """
        do {
            let result = try await webView.callAsyncJavaScript(
                wrappedCode, arguments: [:], in: nil, contentWorld: .page
            )
            if let result = result {
                let str = String(describing: result)
                if str.hasPrefix(Self.jsErrorPrefix) {
                    return .failure(.javaScriptError(String(str.dropFirst(Self.jsErrorPrefix.count))))
                }
                return .success(str)
            }
            return .success("(undefined)")
        } catch {
            return .failure(.javaScriptError(error.localizedDescription))
        }
    }

    // MARK: - Page Content

    func getPageInfo(includeHTML: Bool = false, simplified: Bool = true) async -> Result<String, BrowserError> {
        let url = webView.url?.absoluteString ?? "(no page loaded)"
        let title = webView.title ?? "(untitled)"

        var info = "URL: \(url)\nTitle: \(title)"

        if includeHTML {
            let script = simplified ? Self.simplifiedDOMScript : "document.documentElement.outerHTML"
            let htmlResult = await executeJavaScript(script)
            switch htmlResult {
            case .success(let html):
                let truncated = html.count > 15000 ? String(html.prefix(15000)) + "\n...(truncated)" : html
                info += "\n\nContent:\n\(truncated)"
            case .failure(let err):
                info += "\n\n[Failed to get content: \(err.localizedDescription)]"
            }
        }

        return .success(info)
    }

    // MARK: - Keyboard Suppression

    /// Dismiss the keyboard by resigning first responder from the web view.
    func dismissKeyboard() {
        webView.resignFirstResponder()
        webView.endEditing(true)
        // Also blur any focused element inside the web content
        webView.evaluateJavaScript("document.activeElement && document.activeElement.blur()") { _, _ in }
    }

    /// If the browser is agent-controlled, dismiss the keyboard after a short delay
    /// to allow the JS operation to complete first.
    private func dismissKeyboardIfAgentControlled() {
        guard isAgentControlled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.dismissKeyboard()
        }
    }

    // MARK: - Element Interaction

    func click(selector: String) async -> Result<String, BrowserError> {
        let script = """
        (function() {
            const el = \(resolveSelector(selector));
            if (!el) return JSON.stringify({error: 'Element not found: \(selector.replacingOccurrences(of: "'", with: "\\'"))'});
            el.click();
            var r = JSON.stringify({ok: true, tag: el.tagName, text: (el.textContent || '').trim().substring(0, 100)});
            if (document.activeElement) document.activeElement.blur();
            return r;
        })()
        """
        let result = await executeJavaScript(script)
        dismissKeyboardIfAgentControlled()
        return parseJSResult(result, action: "click")
    }

    func input(selector: String, text: String, clearFirst: Bool = true) async -> Result<String, BrowserError> {
        let clearScript = clearFirst ? "el.value = '';" : ""
        let script = """
        (function() {
            const el = \(resolveSelector(selector));
            if (!el) return JSON.stringify({error: 'Element not found: \(selector.replacingOccurrences(of: "'", with: "\\'"))'});
            el.focus();
            \(clearScript)
            const nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set
                || Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value')?.set;
            if (nativeInputValueSetter) {
                nativeInputValueSetter.call(el, \(jsEscape(text)));
            } else {
                el.value = \(jsEscape(text));
            }
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
            el.blur();
            return JSON.stringify({ok: true, tag: el.tagName, value: el.value.substring(0, 100)});
        })()
        """
        let result = await executeJavaScript(script)
        dismissKeyboardIfAgentControlled()
        return parseJSResult(result, action: "input")
    }

    func select(selector: String, value: String) async -> Result<String, BrowserError> {
        let script = """
        (function() {
            const el = \(resolveSelector(selector));
            if (!el || el.tagName !== 'SELECT') return JSON.stringify({error: 'SELECT element not found: \(selector.replacingOccurrences(of: "'", with: "\\'"))'});
            el.value = \(jsEscape(value));
            el.dispatchEvent(new Event('change', {bubbles: true}));
            el.blur();
            return JSON.stringify({ok: true, selectedValue: el.value, selectedText: el.options[el.selectedIndex]?.text || ''});
        })()
        """
        let result = await executeJavaScript(script)
        dismissKeyboardIfAgentControlled()
        return parseJSResult(result, action: "select")
    }

    func extract(selector: String, attribute: String? = nil) async -> Result<String, BrowserError> {
        let attrCode: String
        if let attribute = attribute {
            attrCode = "el.getAttribute(\(jsEscape(attribute))) || ''"
        } else {
            attrCode = "(el.innerText || el.textContent || '').trim()"
        }
        let script = """
        (function() {
            const els = \(resolveSelector(selector, all: true));
            if (els.length === 0) return JSON.stringify({error: 'No elements found: \(selector.replacingOccurrences(of: "'", with: "\\'"))'});
            const results = [];
            els.forEach(function(el, i) {
                if (i < 50) results.push(\(attrCode));
            });
            return JSON.stringify({ok: true, count: els.length, results: results});
        })()
        """
        let result = await executeJavaScript(script)
        switch result {
        case .success(let json):
            if let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let error = dict["error"] as? String {
                    return .failure(.elementNotFound(error))
                }
                let count = dict["count"] as? Int ?? 0
                let results = dict["results"] as? [String] ?? []
                let output = results.enumerated().map { "[\($0.offset)] \($0.element)" }.joined(separator: "\n")
                return .success("\(count) element(s) found:\n\(output)")
            }
            return .success(json)
        case .failure(let err):
            return .failure(err)
        }
    }

    func waitForElement(selector: String, timeout: TimeInterval = 10) async -> Result<String, BrowserError> {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !Task.isCancelled {
            let script = "(\(resolveSelector(selector))) !== null"
            let result = await executeJavaScript(script)
            if case .success(let value) = result, value == "1" || value == "true" {
                return .success("Element found: \(selector)")
            }
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { break }
        }
        return .failure(.waitTimeout(selector, timeout))
    }

    func scroll(direction: String = "down", pixels: Int = 500) async -> Result<String, BrowserError> {
        let y = direction == "up" ? -pixels : pixels
        let script = "window.scrollBy(0, \(y)); JSON.stringify({scrollY: window.scrollY, scrollHeight: document.body.scrollHeight})"
        let result = await executeJavaScript(script)
        switch result {
        case .success(let json):
            return .success("Scrolled \(direction) \(abs(pixels))px — \(json)")
        case .failure(let err):
            return .failure(err)
        }
    }

    // MARK: - Private Helpers

    private func waitForNavigation(timeout: TimeInterval) async -> Bool {
        if !webView.isLoading { return true }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.navigationContinuation = continuation
                Task {
                    try? await Task.sleep(for: .seconds(timeout))
                    if let c = self.navigationContinuation {
                        self.navigationContinuation = nil
                        c.resume(returning: false)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if let c = self?.navigationContinuation {
                    self?.navigationContinuation = nil
                    c.resume(returning: false)
                }
            }
        }
    }

    private func completeNavigation(success: Bool) {
        if let c = navigationContinuation {
            navigationContinuation = nil
            c.resume(returning: success)
        }
    }

    // MARK: - Selector Resolution

    /// Matches `:contains("text")` or `:contains('text')` pseudo-selectors.
    static let containsRegex = try! NSRegularExpression(
        pattern: #":contains\(([\"'])(.*?)\1\)"#
    )

    /// Convert a selector to a JS expression that evaluates to the matched element(s).
    /// Handles `:contains("text")` by converting to querySelectorAll + textContent filter,
    /// since `:contains()` is not a valid native CSS pseudo-selector.
    func resolveSelector(_ selector: String, all: Bool = false) -> String {
        let range = NSRange(selector.startIndex..., in: selector)
        guard let match = Self.containsRegex.firstMatch(in: selector, range: range) else {
            return all
                ? "document.querySelectorAll(\(jsEscape(selector)))"
                : "document.querySelector(\(jsEscape(selector)))"
        }
        let matchRange = Range(match.range, in: selector)!
        let baseSelector = String(selector[..<matchRange.lowerBound])
        let textRange = Range(match.range(at: 2), in: selector)!
        let searchText = String(selector[textRange])

        if all {
            return "Array.from(document.querySelectorAll(\(jsEscape(baseSelector)))).filter(function(el){return (el.textContent||'').indexOf(\(jsEscape(searchText)))!==-1})"
        } else {
            return "Array.from(document.querySelectorAll(\(jsEscape(baseSelector)))).find(function(el){return (el.textContent||'').indexOf(\(jsEscape(searchText)))!==-1})||null"
        }
    }

    func jsEscape(_ str: String) -> String {
        let escaped = str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "'\(escaped)'"
    }

    private func parseJSResult(_ result: Result<String, BrowserError>, action: String) -> Result<String, BrowserError> {
        switch result {
        case .success(let json):
            if let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let error = dict["error"] as? String {
                    return .failure(.elementNotFound(error))
                }
                return .success("\(action) succeeded: \(json)")
            }
            return .success(json)
        case .failure(let err):
            return .failure(err)
        }
    }

    /// Extracts a simplified readable DOM: text, links, inputs, buttons, etc.
    private static let simplifiedDOMScript = """
    (function() {
        function walk(node, depth) {
            if (depth > 15) return '';
            const skip = new Set(['SCRIPT','STYLE','NOSCRIPT','SVG','PATH','META','LINK']);
            if (skip.has(node.tagName)) return '';
            let out = '';
            const tag = (node.tagName || '').toLowerCase();
            if (tag === 'a') {
                const href = node.getAttribute('href') || '';
                const text = (node.innerText || '').trim().substring(0, 80);
                if (text) out += '[link: ' + text + ' -> ' + href + '] ';
            } else if (tag === 'input') {
                const t = node.type || 'text';
                const n = node.name || node.id || '';
                const v = node.value || '';
                const p = node.placeholder || '';
                out += '[input(' + t + ') name=' + n + ' value="' + v.substring(0,50) + '" placeholder="' + p.substring(0,50) + '"] ';
            } else if (tag === 'textarea') {
                const n = node.name || node.id || '';
                out += '[textarea name=' + n + ' value="' + (node.value || '').substring(0,100) + '"] ';
            } else if (tag === 'button' || (tag === 'input' && (node.type === 'submit' || node.type === 'button'))) {
                out += '[button: ' + (node.innerText || node.value || '').trim().substring(0,50) + '] ';
            } else if (tag === 'select') {
                const n = node.name || node.id || '';
                const opts = Array.from(node.options).map(o => o.value + '=' + o.text).join(', ');
                out += '[select name=' + n + ' options: ' + opts.substring(0,200) + '] ';
            } else if (tag === 'img') {
                out += '[img: ' + (node.alt || node.src || '').substring(0,80) + '] ';
            } else if (node.nodeType === 3) {
                const t = node.textContent.trim();
                if (t.length > 0) out += t + ' ';
            }
            if (node.childNodes) {
                for (let c of node.childNodes) { out += walk(c, depth + 1); }
            }
            if (['P','DIV','LI','TR','H1','H2','H3','H4','H5','H6','BR','HR','SECTION','ARTICLE','HEADER','FOOTER','MAIN','NAV'].includes(node.tagName)) {
                out += '\\n';
            }
            return out;
        }
        return walk(document.body || document.documentElement, 0).replace(/\\n{3,}/g, '\\n\\n').trim();
    })()
    """
}

// MARK: - WKNavigationDelegate

extension BrowserService: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in completeNavigation(success: true) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in completeNavigation(success: false) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in completeNavigation(success: false) }
    }
}

// MARK: - Errors

enum BrowserError: LocalizedError {
    case invalidURL(String)
    case navigationTimeout
    case cannotGoBack
    case cannotGoForward
    case javaScriptError(String)
    case elementNotFound(String)
    case waitTimeout(String, TimeInterval)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .navigationTimeout: return "Navigation timed out"
        case .cannotGoBack: return "Cannot go back — no history"
        case .cannotGoForward: return "Cannot go forward — no forward history"
        case .javaScriptError(let msg): return "JavaScript error: \(msg)"
        case .elementNotFound(let msg): return msg
        case .waitTimeout(let sel, let t): return "Timed out waiting for '\(sel)' after \(Int(t))s"
        }
    }
}
