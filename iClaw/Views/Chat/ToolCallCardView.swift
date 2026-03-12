import SwiftUI

/// Displays tool calls from the assistant as styled, expandable cards.
struct ToolCallCardView: View {
    let toolCalls: [LLMToolCall]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(toolCalls, id: \.id) { call in
                SingleToolCallCard(call: call)
            }
        }
    }
}

private struct SingleToolCallCard: View {
    let call: LLMToolCall
    @State private var isExpanded = false

    private var toolMeta: ToolMeta {
        ToolMeta.resolve(call.function.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: toolMeta.icon)
                        .font(.caption)
                        .foregroundStyle(toolMeta.color)
                        .frame(width: 20, height: 20)
                        .background(toolMeta.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 5))

                    Text(toolMeta.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: true, vertical: false)

                    if let summary = parseSummary(call) {
                        Text(summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.horizontal, 10)
                Text(formatArguments(call.function.arguments))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(toolMeta.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(toolMeta.color.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func parseSummary(_ call: LLMToolCall) -> String? {
        guard let data = call.function.arguments.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        switch call.function.name {
        case "execute_python", "execute_javascript":
            let mode = dict["mode"] as? String ?? "script"
            return "(\(mode))"
        case "read_config", "write_config":
            return dict["key"] as? String
        case "schedule_cron":
            return dict["name"] as? String
        case "create_sub_agent":
            let name = dict["name"] as? String ?? ""
            let type = dict["type"] as? String ?? "temp"
            return name.isEmpty ? nil : "\(name) [\(type)]"
        case "message_sub_agent", "collect_sub_agent_output", "stop_sub_agent", "delete_sub_agent":
            if let id = dict["agent_id"] as? String {
                return String(id.prefix(8)) + "..."
            }
            return nil
        case "save_code":
            return dict["name"] as? String
        case "install_skill", "uninstall_skill":
            return dict["name"] as? String
        default:
            return nil
        }
    }

    private func formatArguments(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else {
            return json
        }
        return str
    }
}

/// Tool result card for displaying tool execution results in the chat.
struct ToolResultCardView: View {
    let message: Message
    @State private var isExpanded = false

    private var toolName: String {
        message.name ?? "tool"
    }

    private var content: String {
        message.content ?? ""
    }

    private var toolMeta: ToolMeta {
        ToolMeta.resolve(toolName)
    }

    private var isError: Bool {
        content.hasPrefix("[Error]") || content.hasPrefix("[stderr]")
    }

    private var isCodeExecution: Bool {
        toolName == "execute_python" || toolName == "execute_javascript"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                cardHeader
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.horizontal, 10)

                if isCodeExecution {
                    codeResultView
                } else {
                    Text(content)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(isError ? .red : .primary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isError ? Color.red.opacity(0.04) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isError ? Color.red.opacity(0.2) : Color(.systemGray4).opacity(0.3), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(isError ? .red : .green)

                Image(systemName: toolMeta.icon)
                    .font(.caption)
                    .foregroundStyle(toolMeta.color)

                Text(toolMeta.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Spacer(minLength: 4)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }

            if !isExpanded && !content.isEmpty {
                Text(content.prefix(120).replacingOccurrences(of: "\n", with: " "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var codeResultView: some View {
        VStack(alignment: .leading, spacing: 0) {
            let parts = parseCodeOutput(content)

            if let stdout = parts.stdout, !stdout.isEmpty {
                HStack {
                    Text("stdout")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    copyButton(stdout)
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 2)

                Text(stdout)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            if let stderr = parts.stderr, !stderr.isEmpty {
                Divider().padding(.horizontal, 10)
                HStack {
                    Text("stderr")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.red.opacity(0.7))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 2)

                Text(stderr)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            if let repr = parts.repr, !repr.isEmpty {
                Divider().padding(.horizontal, 10)
                HStack(spacing: 4) {
                    Text("→")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.blue)
                    Text(repr)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.blue)
                        .textSelection(.enabled)
                    Spacer()
                    copyButton(repr)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }

            if parts.stdout == nil && parts.stderr == nil && parts.repr == nil {
                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    private func copyButton(_ text: String) -> some View {
        Button {
            UIPasteboard.general.string = text
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func parseCodeOutput(_ output: String) -> (stdout: String?, stderr: String?, repr: String?) {
        var stdout: String?
        var stderr: String?
        var repr: String?
        var currentSection: [String] = []

        let lines = output.components(separatedBy: "\n")
        var mode = "stdout"

        for line in lines {
            if line.hasPrefix("[stderr] ") {
                if !currentSection.isEmpty && mode == "stdout" {
                    stdout = currentSection.joined(separator: "\n")
                    currentSection = []
                }
                mode = "stderr"
                currentSection.append(String(line.dropFirst(9)))
            } else if mode == "stderr" && !line.hasPrefix("[stderr]") {
                stderr = currentSection.joined(separator: "\n")
                currentSection = []
                mode = "repr"
                repr = line
            } else {
                currentSection.append(line)
            }
        }

        if !currentSection.isEmpty {
            switch mode {
            case "stdout":
                let joined = currentSection.joined(separator: "\n")
                if joined == "(No output)" {
                    // No output
                } else {
                    stdout = joined
                }
            case "stderr":
                stderr = currentSection.joined(separator: "\n")
            default:
                repr = currentSection.joined(separator: "\n")
            }
        }

        return (stdout, stderr, repr)
    }
}

// MARK: - Tool metadata

struct ToolMeta {
    let displayName: String
    let icon: String
    let color: Color

    static func resolve(_ toolName: String) -> ToolMeta {
        switch toolName {
        case "execute_python":
            return ToolMeta(displayName: "Python", icon: "terminal", color: .blue)
        case "execute_javascript":
            return ToolMeta(displayName: "JavaScript", icon: "terminal.fill", color: .yellow)
        case "read_config":
            return ToolMeta(displayName: "Read Config", icon: "doc.text", color: .purple)
        case "write_config":
            return ToolMeta(displayName: "Write Config", icon: "square.and.pencil", color: .purple)
        case "save_code":
            return ToolMeta(displayName: "Save Code", icon: "square.and.arrow.down", color: .blue)
        case "load_code":
            return ToolMeta(displayName: "Load Code", icon: "square.and.arrow.up", color: .blue)
        case "list_code":
            return ToolMeta(displayName: "List Code", icon: "list.bullet", color: .blue)
        case "create_sub_agent":
            return ToolMeta(displayName: "Create Agent", icon: "person.badge.plus", color: .orange)
        case "message_sub_agent":
            return ToolMeta(displayName: "Message Agent", icon: "bubble.left.and.bubble.right", color: .orange)
        case "collect_sub_agent_output":
            return ToolMeta(displayName: "Collect Output", icon: "tray.and.arrow.down", color: .orange)
        case "list_sub_agents":
            return ToolMeta(displayName: "List Agents", icon: "person.3", color: .orange)
        case "stop_sub_agent":
            return ToolMeta(displayName: "Stop Agent", icon: "stop.circle", color: .red)
        case "delete_sub_agent":
            return ToolMeta(displayName: "Delete Agent", icon: "person.badge.minus", color: .red)
        case "schedule_cron":
            return ToolMeta(displayName: "Schedule Job", icon: "clock.badge.checkmark", color: .green)
        case "unschedule_cron":
            return ToolMeta(displayName: "Remove Job", icon: "clock.badge.xmark", color: .red)
        case "list_cron":
            return ToolMeta(displayName: "List Jobs", icon: "clock", color: .green)
        case "create_skill", "delete_skill", "install_skill", "uninstall_skill", "list_skills", "read_skill":
            return ToolMeta(displayName: formatSkillToolName(toolName), icon: "sparkles", color: .indigo)
        case "set_model":
            return ToolMeta(displayName: "Set Model", icon: "cpu", color: .teal)
        case "get_model":
            return ToolMeta(displayName: "Get Model", icon: "cpu", color: .teal)
        case "list_models":
            return ToolMeta(displayName: "List Models", icon: "list.bullet.rectangle", color: .teal)
        default:
            return ToolMeta(displayName: toolName, icon: "wrench", color: .gray)
        }
    }

    private static func formatSkillToolName(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
