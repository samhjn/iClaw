import SwiftUI
import SwiftData

struct AgentApplePermissionsView: View {
    @Bindable var agent: Agent
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            Section {
                Text(L10n.ApplePermissions.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(AppleToolCategory.allCases) { category in
                CategoryPermissionRow(agent: agent, category: category) {
                    try? modelContext.save()
                }
            }

            Section {
                Button(L10n.ApplePermissions.enableAll) {
                    agent.appleToolPermissionsRaw = nil
                    try? modelContext.save()
                }
                Button(L10n.ApplePermissions.readOnlyAll) {
                    var perms: [String: AppleToolPermissionLevel] = [:]
                    for cat in AppleToolCategory.allCases {
                        if cat.hasWriteTools {
                            perms[cat.rawValue] = .readOnly
                        }
                    }
                    agent.appleToolPermissions = perms
                    try? modelContext.save()
                }
                Button(L10n.ApplePermissions.disableAll, role: .destructive) {
                    var perms: [String: AppleToolPermissionLevel] = [:]
                    for cat in AppleToolCategory.allCases {
                        perms[cat.rawValue] = .disabled
                    }
                    agent.appleToolPermissions = perms
                    try? modelContext.save()
                }
            }
        }
        .navigationTitle(L10n.ApplePermissions.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CategoryPermissionRow: View {
    @Bindable var agent: Agent
    let category: AppleToolCategory
    let onSave: () -> Void

    private var currentLevel: AppleToolPermissionLevel {
        agent.permissionLevel(for: category)
    }

    var body: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: category.systemImage)
                    .font(.title2)
                    .foregroundStyle(colorForLevel(currentLevel))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.displayName)
                        .font(.headline)
                    Text(permissionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("", selection: Binding(
                    get: { currentLevel },
                    set: { newLevel in
                        agent.setPermissionLevel(newLevel, for: category)
                        onSave()
                    }
                )) {
                    ForEach(category.availableLevels, id: \.self) { level in
                        Text(level.displayLabel).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .tint(colorForLevel(currentLevel))
            }
            .padding(.vertical, 4)

            if currentLevel != .disabled {
                ToolListPreview(category: category, level: currentLevel)
            }
        }
    }

    private var permissionSummary: String {
        let readCount = category.readToolNames.count
        let writeCount = category.writeToolNames.count
        switch currentLevel {
        case .readWrite:
            return L10n.ApplePermissions.summaryReadWrite(readCount + writeCount)
        case .readOnly:
            return L10n.ApplePermissions.summaryReadOnly(readCount)
        case .writeOnly:
            return L10n.ApplePermissions.summaryWriteOnly(writeCount)
        case .disabled:
            return L10n.ApplePermissions.summaryDisabled
        }
    }

    private func colorForLevel(_ level: AppleToolPermissionLevel) -> Color {
        switch level {
        case .readWrite: return .green
        case .readOnly:  return .blue
        case .writeOnly: return .orange
        case .disabled:  return .gray
        }
    }
}

private struct ToolListPreview: View {
    let category: AppleToolCategory
    let level: AppleToolPermissionLevel

    var body: some View {
        let enabledTools = enabledToolNames
        if !enabledTools.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(enabledTools, id: \.self) { name in
                    HStack(spacing: 6) {
                        Image(systemName: AppleToolCategory.isWriteTool(name) ? "pencil" : "eye")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        Text(name)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.leading, 44)
        }
    }

    private var enabledToolNames: [String] {
        var tools: [String] = []
        if level.allowsRead {
            tools.append(contentsOf: category.readToolNames)
        }
        if level.allowsWrite {
            tools.append(contentsOf: category.writeToolNames)
        }
        return tools
    }
}
