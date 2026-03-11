import SwiftUI
import SwiftData

struct SkillLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var skills: [Skill] = []
    @State private var searchText = ""
    @State private var showCreateSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if filteredSkills.isEmpty && searchText.isEmpty {
                    ContentUnavailableView {
                        Label("No Skills", systemImage: "sparkles")
                    } description: {
                        Text("Create a skill or let your AI agent build one.")
                    } actions: {
                        Button("Create Skill") { showCreateSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if filteredSkills.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    skillList
                }
            }
            .navigationTitle("Skills")
            .searchable(text: $searchText, prompt: "Search skills...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreateSheet = true } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                SkillEditView { reload() }
            }
            .onAppear {
                ensureBuiltIns()
                reload()
            }
        }
    }

    private var filteredSkills: [Skill] {
        if searchText.isEmpty { return skills }
        let q = searchText.lowercased()
        return skills.filter {
            $0.name.lowercased().contains(q) ||
            $0.summary.lowercased().contains(q) ||
            $0.tags.contains(where: { $0.lowercased().contains(q) })
        }
    }

    private var skillList: some View {
        List {
            let builtIn = filteredSkills.filter { $0.isBuiltIn }
            let custom = filteredSkills.filter { !$0.isBuiltIn }

            if !custom.isEmpty {
                Section("Custom Skills") {
                    ForEach(custom, id: \.id) { skill in
                        NavigationLink {
                            SkillDetailView(skill: skill, onDelete: { reload() })
                        } label: {
                            SkillRowView(skill: skill)
                        }
                    }
                }
            }

            if !builtIn.isEmpty {
                Section("Built-in Skills") {
                    ForEach(builtIn, id: \.id) { skill in
                        NavigationLink {
                            SkillDetailView(skill: skill, onDelete: nil)
                        } label: {
                            SkillRowView(skill: skill)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func reload() {
        let service = SkillService(modelContext: modelContext)
        skills = service.fetchAllSkills()
    }

    private func ensureBuiltIns() {
        let service = SkillService(modelContext: modelContext)
        service.ensureBuiltInSkills()
    }
}

struct SkillRowView: View {
    let skill: Skill

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(skill.name)
                    .font(.headline)
                Spacer()
                if skill.isBuiltIn {
                    Text("built-in")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.blue.opacity(0.15)))
                        .foregroundStyle(.blue)
                }
            }

            Text(skill.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                if !skill.tags.isEmpty {
                    ForEach(skill.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.secondary.opacity(0.12)))
                    }
                }
                Spacer()
                if skill.installCount > 0 {
                    Label("\(skill.installCount)", systemImage: "cpu")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
