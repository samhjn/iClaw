import SwiftUI

struct AgentDetailView: View {
    @Bindable var agent: Agent
    let viewModel: AgentViewModel
    @State private var selectedConfig: ConfigType = .soul

    enum ConfigType: String, CaseIterable {
        case soul = "SOUL"
        case memory = "MEMORY"
        case user = "USER"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Config", selection: $selectedConfig) {
                ForEach(ConfigType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            MarkdownEditorView(
                content: bindingForConfig(selectedConfig),
                title: "\(selectedConfig.rawValue).md"
            )
        }
        .navigationTitle(agent.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    NavigationLink(L10n.AgentDetail.modelConfig) {
                        AgentModelConfigView(agent: agent)
                    }
                    NavigationLink(L10n.AgentDetail.skills) {
                        AgentSkillsView(agent: agent)
                    }
                    NavigationLink(L10n.AgentDetail.cronJobs) {
                        CronJobListView(agent: agent)
                    }
                    NavigationLink(L10n.AgentDetail.customConfigs) {
                        CustomConfigsView(agent: agent)
                    }
                    NavigationLink(L10n.AgentDetail.subAgents) {
                        SubAgentListView(parentAgent: agent)
                    }
                    NavigationLink(L10n.AgentDetail.codeSnippets) {
                        CodeSnippetListView(agent: agent)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onChange(of: agent.soulMarkdown) { _, _ in viewModel.updateAgent(agent) }
        .onChange(of: agent.memoryMarkdown) { _, _ in viewModel.updateAgent(agent) }
        .onChange(of: agent.userMarkdown) { _, _ in viewModel.updateAgent(agent) }
    }

    private func bindingForConfig(_ type: ConfigType) -> Binding<String> {
        switch type {
        case .soul: return $agent.soulMarkdown
        case .memory: return $agent.memoryMarkdown
        case .user: return $agent.userMarkdown
        }
    }
}

struct CustomConfigsView: View {
    let agent: Agent
    @Environment(\.modelContext) private var modelContext
    @State private var showAddSheet = false
    @State private var newKey = ""
    @State private var newContent = ""

    var body: some View {
        List {
            ForEach(agent.customConfigs, id: \.id) { config in
                NavigationLink {
                    MarkdownEditorView(
                        content: Binding(
                            get: { config.content },
                            set: {
                                config.content = $0
                                config.updatedAt = Date()
                                try? modelContext.save()
                            }
                        ),
                        title: config.key
                    )
                } label: {
                    VStack(alignment: .leading) {
                        Text(config.key).font(.headline)
                        Text(config.content.prefix(80))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .navigationTitle(L10n.AgentDetail.customConfigs)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert(L10n.AgentDetail.newConfig, isPresented: $showAddSheet) {
            TextField(L10n.AgentDetail.keyPlaceholder, text: $newKey)
            Button(L10n.Common.create) {
                let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty {
                    let config = AgentConfig(key: key, content: "", agent: agent)
                    modelContext.insert(config)
                    try? modelContext.save()
                }
                newKey = ""
            }
            Button(L10n.Common.cancel, role: .cancel) { newKey = "" }
        }
    }
}

struct SubAgentListView: View {
    let parentAgent: Agent
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            if parentAgent.subAgents.isEmpty {
                ContentUnavailableView(
                    L10n.AgentDetail.noSubAgents,
                    systemImage: "cpu",
                    description: Text(L10n.AgentDetail.subAgentsDescription)
                )
            } else {
                ForEach(parentAgent.subAgents, id: \.id) { sub in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(sub.name).font(.headline)
                            Spacer()
                            Text(sub.subAgentType ?? L10n.Common.unknown)
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(sub.isTempSubAgent ? .orange : .blue)
                                )
                        }

                        HStack(spacing: 12) {
                            let hasActive = sub.sessions.contains { $0.isActive }
                            if hasActive {
                                HStack(spacing: 4) {
                                    Circle().fill(.green).frame(width: 6, height: 6)
                                    Text(L10n.Common.active)
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                }
                            }

                            Text(L10n.AgentDetail.sessionsCount(sub.sessions.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let lastSession = sub.sessions.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
                                Text(L10n.AgentDetail.msgsCount(lastSession.messages.count))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            modelContext.delete(sub)
                            try? modelContext.save()
                        } label: {
                            Label(L10n.Common.delete, systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.AgentDetail.subAgentsTitle(parentAgent.subAgents.count))
    }
}

struct CodeSnippetListView: View {
    let agent: Agent

    var body: some View {
        List {
            if agent.codeSnippets.isEmpty {
                ContentUnavailableView(
                    L10n.AgentDetail.noCodeSnippets,
                    systemImage: "doc.text",
                    description: Text(L10n.AgentDetail.codeSnippetsDescription)
                )
            } else {
                ForEach(agent.codeSnippets, id: \.id) { snippet in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(snippet.name).font(.headline)
                            Spacer()
                            Text(snippet.language)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.secondary.opacity(0.2)))
                        }
                        Text(snippet.code.prefix(120))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(L10n.AgentDetail.codeSnippets)
    }
}
