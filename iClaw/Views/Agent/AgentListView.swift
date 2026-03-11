import SwiftUI
import SwiftData

struct AgentListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: AgentViewModel?
    @State private var showCreateSheet = false
    @State private var newAgentName = ""

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    if vm.agents.isEmpty {
                        emptyStateView
                    } else {
                        agentList(vm)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Agents")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newAgentName = ""
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .alert("New Agent", isPresented: $showCreateSheet) {
                TextField("Agent Name", text: $newAgentName)
                Button("Create") {
                    let name = newAgentName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        _ = viewModel?.createAgent(name: name)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter a name for the new agent.")
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = AgentViewModel(modelContext: modelContext)
            } else {
                viewModel?.fetchAgents()
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Agents", systemImage: "cpu")
        } description: {
            Text("Create an AI agent to get started.")
        } actions: {
            Button("Create Agent") {
                newAgentName = ""
                showCreateSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func agentList(_ vm: AgentViewModel) -> some View {
        List {
            ForEach(vm.agents, id: \.id) { agent in
                NavigationLink {
                    AgentDetailView(agent: agent, viewModel: vm)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(agent.name)
                            .font(.headline)
                        HStack(spacing: 12) {
                            Label("\(agent.sessions.count)", systemImage: "bubble.left")
                            Label("\(agent.activeSkills.count)", systemImage: "sparkles")
                            Label("\(agent.cronJobs.count)", systemImage: "clock.badge")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    vm.deleteAgent(vm.agents[index])
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
