import SwiftUI

/// Renders markdown content with support for headers, code blocks, inline code,
/// bold, italic, strikethrough, links, images, tables, task lists, lists,
/// blockquotes, and horizontal rules.
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

    // MARK: - Block Rendering

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
        case .taskList(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                            .font(.caption)
                            .foregroundStyle(item.checked
                                ? (isUserMessage ? .white : .accentColor)
                                : (isUserMessage ? .white.opacity(0.5) : .secondary))
                        renderInlineText(item.text)
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
        case .table(let table):
            MarkdownTableView(table: table, isUserMessage: isUserMessage)
        case .image(let alt, let url):
            MarkdownImageView(alt: alt, urlString: url, isUserMessage: isUserMessage)
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

            // Image (block-level): ![alt](url)
            if let imageMatch = parseBlockImage(trimmed) {
                blocks.append(.image(alt: imageMatch.alt, url: imageMatch.url))
                i += 1
                continue
            }

            // Blockquote
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                var quoteLines: [String] = []
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let ql = lines[i].trimmingCharacters(in: .whitespaces)
                    quoteLines.append(ql.hasPrefix("> ") ? String(ql.dropFirst(2)) : String(ql.dropFirst(1)))
                    i += 1
                }
                blocks.append(.blockquote(text: quoteLines.joined(separator: " ")))
                continue
            }

            // Table: detect by checking if current and next line look like a table
            if trimmed.contains("|"), i + 1 < lines.count {
                let nextTrimmed = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if isTableSeparator(nextTrimmed) {
                    let table = parseTable(lines: lines, from: &i)
                    if let table {
                        blocks.append(.table(table))
                        continue
                    }
                }
            }

            // Task list: - [ ] or - [x]
            if isTaskListItem(trimmed) {
                var items: [TaskListItem] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if let taskItem = parseTaskListItem(t) {
                        items.append(taskItem)
                        i += 1
                    } else if t.isEmpty {
                        break
                    } else if !items.isEmpty {
                        items[items.count - 1] = TaskListItem(
                            checked: items[items.count - 1].checked,
                            text: items[items.count - 1].text + " " + t
                        )
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.taskList(items: items))
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
                if t.isEmpty || t.hasPrefix("#") || t.hasPrefix("```") || t.hasPrefix("> ") || t == ">" ||
                   t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") ||
                   t == "---" || t == "***" || t == "___" ||
                   isTaskListItem(t) ||
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

    // MARK: - Table Parsing

    private func isTableSeparator(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        guard stripped.contains("|") else { return false }
        let cells = splitTableRow(stripped)
        return cells.allSatisfy { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            return c.isEmpty || c.allSatisfy({ $0 == "-" || $0 == ":" || $0 == " " }) && c.contains("-")
        }
    }

    private func splitTableRow(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") { row = String(row.dropFirst()) }
        if row.hasSuffix("|") { row = String(row.dropLast()) }
        return row.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func parseAlignment(_ cell: String) -> TableAlignment {
        let c = cell.trimmingCharacters(in: .whitespaces)
        let left = c.hasPrefix(":")
        let right = c.hasSuffix(":")
        if left && right { return .center }
        if right { return .trailing }
        return .leading
    }

    private func parseTable(lines: [String], from i: inout Int) -> MarkdownTable? {
        let headerLine = lines[i].trimmingCharacters(in: .whitespaces)
        let separatorLine = lines[i + 1].trimmingCharacters(in: .whitespaces)

        let headers = splitTableRow(headerLine)
        let separatorCells = splitTableRow(separatorLine)
        let alignments = separatorCells.map { parseAlignment($0) }

        i += 2

        var rows: [[String]] = []
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.isEmpty || !t.contains("|") { break }
            if isTableSeparator(t) { i += 1; continue }
            let cells = splitTableRow(t)
            rows.append(cells)
            i += 1
        }

        guard !headers.isEmpty else { return nil }

        let columnCount = headers.count
        let normalizedAlignments = (0..<columnCount).map { idx in
            idx < alignments.count ? alignments[idx] : .leading
        }
        let normalizedRows = rows.map { row in
            (0..<columnCount).map { idx in idx < row.count ? row[idx] : "" }
        }

        return MarkdownTable(
            headers: headers,
            alignments: normalizedAlignments,
            rows: normalizedRows
        )
    }

    // MARK: - Image Parsing

    private func parseBlockImage(_ line: String) -> (alt: String, url: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("![") else { return nil }
        let after = trimmed.dropFirst(2)
        guard let closeBracket = after.firstIndex(of: "]") else { return nil }
        let alt = String(after[after.startIndex..<closeBracket])
        let afterBracket = after[after.index(after: closeBracket)...]
        guard afterBracket.hasPrefix("(") else { return nil }
        let urlPart = afterBracket.dropFirst()
        guard let closeParen = urlPart.firstIndex(of: ")") else { return nil }
        let url = String(urlPart[urlPart.startIndex..<closeParen])
        // Verify this is the entire line content (block-level image)
        let remaining = urlPart[urlPart.index(after: closeParen)...].trimmingCharacters(in: .whitespaces)
        guard remaining.isEmpty else { return nil }
        return (alt, url)
    }

    // MARK: - Task List Parsing

    private func isTaskListItem(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("- [ ] ") || t.hasPrefix("- [x] ") || t.hasPrefix("- [X] ") ||
               t.hasPrefix("* [ ] ") || t.hasPrefix("* [x] ") || t.hasPrefix("* [X] ")
    }

    private func parseTaskListItem(_ line: String) -> TaskListItem? {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("- [ ] ") || t.hasPrefix("* [ ] ") {
            return TaskListItem(checked: false, text: String(t.dropFirst(6)))
        }
        if t.hasPrefix("- [x] ") || t.hasPrefix("- [X] ") || t.hasPrefix("* [x] ") || t.hasPrefix("* [X] ") {
            return TaskListItem(checked: true, text: String(t.dropFirst(6)))
        }
        return nil
    }

    // MARK: - Inline Parsing

    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        var result = AttributedString()
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            // Image inline: ![alt](url) → render as [🖼 alt] link
            if remaining.hasPrefix("![") {
                let after = remaining.dropFirst(2)
                if let closeBracket = after.firstIndex(of: "]") {
                    let altText = String(after[after.startIndex..<closeBracket])
                    let afterBracket = after[after.index(after: closeBracket)...]
                    if afterBracket.hasPrefix("(") {
                        let urlPart = afterBracket.dropFirst()
                        if let closeParen = urlPart.firstIndex(of: ")") {
                            let urlStr = String(urlPart[urlPart.startIndex..<closeParen])
                            var attr = AttributedString("🖼 \(altText.isEmpty ? urlStr : altText)")
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

            // Bold+Italic: ***text*** or ___text___
            if remaining.hasPrefix("***") {
                let after = remaining.dropFirst(3)
                if let endRange = after.range(of: "***") {
                    let inner = String(after[after.startIndex..<endRange.lowerBound])
                    var attr = parseInlineMarkdown(inner)
                    attr.font = .body.bold().italic()
                    result.append(attr)
                    remaining = after[endRange.upperBound...]
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

// MARK: - Block Types

private enum MarkdownBlock {
    case heading(level: Int, text: String)
    case codeBlock(language: String, code: String)
    case paragraph(text: String)
    case bulletList(items: [String])
    case orderedList(items: [String])
    case taskList(items: [TaskListItem])
    case blockquote(text: String)
    case table(MarkdownTable)
    case image(alt: String, url: String)
    case horizontalRule
    case empty
}

private struct TaskListItem {
    let checked: Bool
    let text: String
}

// MARK: - Table Types

enum TableAlignment {
    case leading, center, trailing

    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

struct MarkdownTable {
    let headers: [String]
    let alignments: [TableAlignment]
    let rows: [[String]]
}

// MARK: - Table View

private struct MarkdownTableView: View {
    let table: MarkdownTable
    let isUserMessage: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { colIdx, header in
                        cellView(
                            text: header,
                            alignment: colIdx < table.alignments.count ? table.alignments[colIdx] : .leading,
                            isHeader: true,
                            columnIndex: colIdx
                        )
                    }
                }
                .background(isUserMessage ? Color.white.opacity(0.1) : Color(.systemGray5))

                // Separator
                Rectangle()
                    .fill(isUserMessage ? Color.white.opacity(0.3) : Color(.systemGray4))
                    .frame(height: 1)

                // Data rows
                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIdx, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIdx, cell in
                            cellView(
                                text: cell,
                                alignment: colIdx < table.alignments.count ? table.alignments[colIdx] : .leading,
                                isHeader: false,
                                columnIndex: colIdx
                            )
                        }
                    }
                    .background(rowIdx % 2 == 1
                        ? (isUserMessage ? Color.white.opacity(0.05) : Color(.systemGray6).opacity(0.5))
                        : Color.clear)

                    if rowIdx < table.rows.count - 1 {
                        Rectangle()
                            .fill(isUserMessage ? Color.white.opacity(0.1) : Color(.systemGray5))
                            .frame(height: 0.5)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isUserMessage ? Color.white.opacity(0.2) : Color(.systemGray4), lineWidth: 0.5)
            )
        }
    }

    @ViewBuilder
    private func cellView(text: String, alignment: TableAlignment, isHeader: Bool, columnIndex: Int) -> some View {
        Text(text)
            .font(isHeader ? .caption.bold() : .caption)
            .foregroundStyle(isUserMessage ? .white : .primary)
            .multilineTextAlignment(alignment.textAlignment)
            .frame(minWidth: 60, alignment: Alignment(horizontal: alignment.horizontal, vertical: .center))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .textSelection(.enabled)

        if columnIndex < table.headers.count - 1 {
            Rectangle()
                .fill(isUserMessage ? Color.white.opacity(0.1) : Color(.systemGray5))
                .frame(width: 0.5)
        }
    }
}

// MARK: - Image View

private struct MarkdownImageView: View {
    let alt: String
    let urlString: String
    let isUserMessage: Bool

    var body: some View {
        if let url = URL(string: urlString) {
            VStack(alignment: .leading, spacing: 4) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(L10n.Chat.loadingImage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: 100)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 400, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .failure:
                        HStack(spacing: 6) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .foregroundStyle(.secondary)
                            Text(L10n.Chat.imageLoadFailed)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray6))
                        )
                    @unknown default:
                        EmptyView()
                    }
                }

                if !alt.isEmpty {
                    Text(alt)
                        .font(.caption)
                        .foregroundStyle(isUserMessage ? .white.opacity(0.6) : .secondary)
                        .italic()
                }
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "link.badge.plus")
                    .foregroundStyle(.secondary)
                Text(alt.isEmpty ? urlString : alt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
