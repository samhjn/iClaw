import SwiftUI

/// Renders markdown content with support for headers, code blocks, inline code,
/// bold, italic, links, lists, blockquotes, and horizontal rules.
struct MarkdownContentView: View {
    let content: String
    let isUserMessage: Bool

    init(_ content: String, isUser: Bool = false) {
        self.content = content
        self.isUserMessage = isUser
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            renderHeading(level: level, text: text)
        case .codeBlock(let language, let code):
            CodeBlockView(code: code, language: language)
        case .paragraph(let text):
            renderInlineText(text)
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                            .foregroundStyle(isUserMessage ? .white.opacity(0.7) : .secondary)
                        renderInlineText(item)
                    }
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(index + 1).")
                            .foregroundStyle(isUserMessage ? .white.opacity(0.7) : .secondary)
                            .monospacedDigit()
                        renderInlineText(item)
                    }
                }
            }
        case .blockquote(let text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(isUserMessage ? Color.white.opacity(0.4) : Color.accentColor.opacity(0.5))
                    .frame(width: 3)
                renderInlineText(text)
                    .foregroundStyle(isUserMessage ? .white.opacity(0.8) : .secondary)
            }
            .padding(.vertical, 2)
        case .horizontalRule:
            Divider()
                .padding(.vertical, 4)
        case .empty:
            EmptyView()
        }
    }

    @ViewBuilder
    private func renderHeading(level: Int, text: String) -> some View {
        let font: Font = switch level {
        case 1: .title2.bold()
        case 2: .title3.bold()
        case 3: .headline
        default: .subheadline.bold()
        }
        Text(text)
            .font(font)
            .foregroundStyle(isUserMessage ? .white : .primary)
            .padding(.top, level <= 2 ? 4 : 2)
    }

    @ViewBuilder
    private func renderInlineText(_ text: String) -> some View {
        let attributed = parseInlineMarkdown(text)
        Text(attributed)
            .font(.body)
            .foregroundStyle(isUserMessage ? .white : .primary)
            .textSelection(.enabled)
    }

    // MARK: - Block Parsing

    private func parseBlocks() -> [MarkdownBlock] {
        let lines = content.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Code block
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(language: lang.isEmpty ? "text" : lang, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Empty line
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Heading
            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                if level <= 6 {
                    let text = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                    blocks.append(.heading(level: level, text: text))
                    i += 1
                    continue
                }
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // Blockquote
            if trimmed.hasPrefix("> ") {
                var quoteLines: [String] = []
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let ql = lines[i].trimmingCharacters(in: .whitespaces)
                    quoteLines.append(ql.hasPrefix("> ") ? String(ql.dropFirst(2)) : String(ql.dropFirst(1)))
                    i += 1
                }
                blocks.append(.blockquote(text: quoteLines.joined(separator: " ")))
                continue
            }

            // Bullet list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
                        items.append(String(t.dropFirst(2)))
                        i += 1
                    } else if t.isEmpty {
                        break
                    } else if !items.isEmpty {
                        items[items.count - 1] += " " + t
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.bulletList(items: items))
                continue
            }

            // Ordered list
            if let _ = trimmed.range(of: "^\\d+[.)]+\\s", options: .regularExpression) {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if let range = t.range(of: "^\\d+[.)]+\\s", options: .regularExpression) {
                        items.append(String(t[range.upperBound...]))
                        i += 1
                    } else if t.isEmpty {
                        break
                    } else if !items.isEmpty {
                        items[items.count - 1] += " " + t
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.orderedList(items: items))
                continue
            }

            // Paragraph (collect consecutive non-empty lines)
            var paraLines: [String] = []
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("#") || t.hasPrefix("```") || t.hasPrefix("> ") ||
                   t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") ||
                   t == "---" || t == "***" || t == "___" ||
                   t.range(of: "^\\d+[.)]+\\s", options: .regularExpression) != nil {
                    break
                }
                paraLines.append(t)
                i += 1
            }
            if !paraLines.isEmpty {
                blocks.append(.paragraph(text: paraLines.joined(separator: " ")))
            }
        }

        return blocks
    }

    // MARK: - Inline Parsing

    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        var result = AttributedString()
        let scanner = Scanner(string: text)
        scanner.charactersToBeSkipped = nil
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            // Inline code: `code`
            if remaining.hasPrefix("`") {
                let after = remaining.dropFirst()
                if let endIdx = after.firstIndex(of: "`") {
                    let code = String(after[after.startIndex..<endIdx])
                    var attr = AttributedString(code)
                    attr.font = .system(.body, design: .monospaced)
                    attr.backgroundColor = isUserMessage ? .white.opacity(0.15) : Color(.systemGray5)
                    result.append(attr)
                    remaining = after[after.index(after: endIdx)...]
                    continue
                }
            }

            // Bold: **text** or __text__
            if remaining.hasPrefix("**") {
                let after = remaining.dropFirst(2)
                if let endRange = after.range(of: "**") {
                    let boldText = String(after[after.startIndex..<endRange.lowerBound])
                    var attr = parseInlineMarkdown(boldText)
                    attr.font = .body.bold()
                    result.append(attr)
                    remaining = after[endRange.upperBound...]
                    continue
                }
            }

            // Italic: *text* or _text_
            if (remaining.hasPrefix("*") && !remaining.hasPrefix("**")) ||
               (remaining.hasPrefix("_") && !remaining.hasPrefix("__")) {
                let marker = remaining.first!
                let after = remaining.dropFirst()
                if let endIdx = after.firstIndex(of: marker) {
                    let italicText = String(after[after.startIndex..<endIdx])
                    var attr = parseInlineMarkdown(italicText)
                    attr.font = .body.italic()
                    result.append(attr)
                    remaining = after[after.index(after: endIdx)...]
                    continue
                }
            }

            // Strikethrough: ~~text~~
            if remaining.hasPrefix("~~") {
                let after = remaining.dropFirst(2)
                if let endRange = after.range(of: "~~") {
                    let strikeText = String(after[after.startIndex..<endRange.lowerBound])
                    var attr = AttributedString(strikeText)
                    attr.strikethroughStyle = .single
                    result.append(attr)
                    remaining = after[endRange.upperBound...]
                    continue
                }
            }

            // Link: [text](url)
            if remaining.hasPrefix("[") {
                let after = remaining.dropFirst()
                if let closeBracket = after.firstIndex(of: "]") {
                    let linkText = String(after[after.startIndex..<closeBracket])
                    let afterBracket = after[after.index(after: closeBracket)...]
                    if afterBracket.hasPrefix("(") {
                        let urlPart = afterBracket.dropFirst()
                        if let closeParen = urlPart.firstIndex(of: ")") {
                            let urlStr = String(urlPart[urlPart.startIndex..<closeParen])
                            var attr = AttributedString(linkText)
                            if let url = URL(string: urlStr) {
                                attr.link = url
                            }
                            attr.foregroundColor = .blue
                            attr.underlineStyle = .single
                            result.append(attr)
                            remaining = urlPart[urlPart.index(after: closeParen)...]
                            continue
                        }
                    }
                }
            }

            // Regular character
            let char = remaining.first!
            result.append(AttributedString(String(char)))
            remaining = remaining.dropFirst()
        }

        return result
    }
}

// MARK: - Markdown Block Types

private enum MarkdownBlock {
    case heading(level: Int, text: String)
    case codeBlock(language: String, code: String)
    case paragraph(text: String)
    case bulletList(items: [String])
    case orderedList(items: [String])
    case blockquote(text: String)
    case horizontalRule
    case empty
}
