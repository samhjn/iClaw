import SwiftUI
import SwiftData

struct SessionListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SessionListViewModel?
    @State private var showNewSessionSheet = false
    @State private var navigateToSession: Session?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    if vm.sessions.isEmpty {
                        emptyStateView
                    } else {
                        sessionsList(vm)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewSessionSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showNewSessionSheet) {
                NewSessionSheet { agent in
                    if let vm = viewModel {
                        let session = vm.createSession(agent: agent)
                        navigateToSession = session
                    }
                    showNewSessionSheet = false
                }
            }
            .navigationDestination(item: $navigateToSession) { session in
                ChatView(session: session)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = SessionListViewModel(modelContext: modelContext)
            } else {
                viewModel?.fetchSessions()
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Sessions", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Create a new session to start chatting with an AI agent.")
        } actions: {
            Button("New Session") {
                showNewSessionSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func sessionsList(_ vm: SessionListViewModel) -> some View {
        List {
            ForEach(vm.sessions, id: \.id) { session in
                SessionRowView(session: session)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        navigateToSession = session
                    }
            }
            .onDelete { offsets in
                vm.deleteSessionAtOffsets(offsets)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            vm.fetchSessions()
        }
    }
}

struct NewSessionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let onSelect: (Agent) -> Void

    @State private var agents: [Agent] = []

    var body: some View {
        NavigationStack {
            List {
                if agents.isEmpty {
                    ContentUnavailableView {
                        Label("No Agents", systemImage: "cpu")
                    } description: {
                        Text("Create an agent first in the Agents tab.")
                    }
                } else {
                    ForEach(agents, id: \.id) { agent in
                        Button {
                            onSelect(agent)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(agent.name)
                                        .font(.headline)
                                    Text("\(agent.sessions.count) sessions")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
            .navigationTitle("Select Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            let descriptor = FetchDescriptor<Agent>(
                predicate: #Predicate { $0.parentAgent == nil },
                sortBy: [SortDescriptor(\.name)]
            )
            agents = (try? modelContext.fetch(descriptor)) ?? []
        }
    }
}
