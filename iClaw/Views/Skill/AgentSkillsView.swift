import SwiftUI
import SwiftData

struct AgentSkillsView: View {
    let agent: Agent
    @Environment(\.modelContext) private var modelContext
    @State private var showLibraryPicker = false

    var body: some View {
        List {
            if agent.installedSkills.isEmpty {
                ContentUnavailableView {
                    Label("No Skills Installed", systemImage: "sparkles")
                } description: {
                    Text("Install skills from the library to give this agent specialized capabilities.")
                } actions: {
                    Button("Browse Library") { showLibraryPicker = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Section {
                    ForEach(sortedInstallations, id: \.id) { installation in
                        if let skill = installation.skill {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(skill.name)
                                            .font(.headline)
                                        if skill.isBuiltIn {
                                            Text("built-in")
                                                .font(.caption2)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Capsule().fill(.blue.opacity(0.15)))
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    Text(skill.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { installation.isEnabled },
                                    set: { _ in
                                        SkillService(modelContext: modelContext).toggleSkill(installation)
                                    }
                                ))
                                .labelsHidden()
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    let service = SkillService(modelContext: modelContext)
                                    _ = service.uninstallSkill(skill, from: agent)
                                } label: {
                                    Label("Uninstall", systemImage: "minus.circle")
                                }
                            }
                        }
                    }
                } header: {
                    Text("\(agent.activeSkills.count) active / \(agent.installedSkills.count) installed")
                }
            }
        }
        .navigationTitle("Skills")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showLibraryPicker = true } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showLibraryPicker) {
            SkillPickerSheet(agent: agent)
        }
    }

    private var sortedInstallations: [InstalledSkill] {
        agent.installedSkills.sorted { ($0.skill?.name ?? "") < ($1.skill?.name ?? "") }
    }
}

// MARK: - Skill Picker (install from library)

struct SkillPickerSheet: View {
    let agent: Agent
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var allSkills: [Skill] = []
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredSkills, id: \.id) { skill in
                    let installed = agent.installedSkills.contains { $0.skill?.id == skill.id }
                    Button {
                        let service = SkillService(modelContext: modelContext)
                        if installed {
                            _ = service.uninstallSkill(skill, from: agent)
                        } else {
                            _ = service.installSkill(skill, on: agent)
                        }
                        reload()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(skill.name).font(.headline)
                                    if skill.isBuiltIn {
                                        Text("built-in")
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                    }
                                }
                                Text(skill.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: installed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(installed ? .green : .secondary)
                        }
                    }
                    .tint(.primary)
                }
            }
            .searchable(text: $searchText, prompt: "Search skills...")
            .navigationTitle("Skill Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { reload() }
        }
    }

    private var filteredSkills: [Skill] {
        if searchText.isEmpty { return allSkills }
        let q = searchText.lowercased()
        return allSkills.filter {
            $0.name.lowercased().contains(q) ||
            $0.summary.lowercased().contains(q) ||
            $0.tags.contains(where: { $0.lowercased().contains(q) })
        }
    }

    private func reload() {
        let service = SkillService(modelContext: modelContext)
        service.ensureBuiltInSkills()
        allSkills = service.fetchAllSkills()
    }
}
