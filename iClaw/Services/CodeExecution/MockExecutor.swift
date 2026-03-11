import Foundation

final class MockExecutor: CodeExecutor, @unchecked Sendable {
    let language = "python"
    let isAvailable = true

    func execute(code: String, mode: ExecutionMode) async throws -> ExecutionResult {
        try await Task.sleep(for: .milliseconds(300))

        switch mode {
        case .repr:
            return simulateRepr(code: code)
        case .script:
            return simulateScript(code: code)
        }
    }

    private func simulateRepr(code: String) -> ExecutionResult {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)

        if let number = evaluateSimpleMath(trimmed) {
            return .success(repr: String(number))
        }

        if trimmed.hasPrefix("\"") || trimmed.hasPrefix("'") {
            return .success(repr: trimmed)
        }

        if trimmed.hasPrefix("[") || trimmed.hasPrefix("{") || trimmed.hasPrefix("(") {
            return .success(repr: trimmed)
        }

        if trimmed.hasPrefix("len(") {
            return .success(repr: "3")
        }

        if trimmed.hasPrefix("type(") {
            return .success(repr: "<class 'str'>")
        }

        return .success(repr: "[mock] repr of: \(trimmed.prefix(50))")
    }

    private func simulateScript(code: String) -> ExecutionResult {
        var output: [String] = []

        let lines = code.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("print(") {
                let content = extractPrintContent(trimmed)
                output.append(content)
            }
        }

        if output.isEmpty {
            output.append("[mock] Script executed successfully (\(lines.count) lines)")
        }

        return .success(stdout: output.joined(separator: "\n"))
    }

    private func extractPrintContent(_ line: String) -> String {
        guard let start = line.firstIndex(of: "("),
              let end = line.lastIndex(of: ")") else {
            return line
        }
        var content = String(line[line.index(after: start)..<end])

        if (content.hasPrefix("\"") && content.hasSuffix("\"")) ||
           (content.hasPrefix("'") && content.hasSuffix("'")) {
            content = String(content.dropFirst().dropLast())
        }

        if content.hasPrefix("f\"") || content.hasPrefix("f'") {
            content = String(content.dropFirst(2).dropLast())
        }

        return content
    }

    private func evaluateSimpleMath(_ expr: String) -> Double? {
        let sanitized = expr.filter { "0123456789+-*/.() ".contains($0) }
        guard sanitized == expr else { return nil }

        let expression = NSExpression(format: sanitized)
        return expression.expressionValue(with: nil, context: nil) as? Double
    }
}
