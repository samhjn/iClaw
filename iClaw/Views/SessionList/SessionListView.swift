import SwiftUI
import SwiftData

struct SessionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismissSearch) private var dismissSearch
    @State private var viewModel: SessionListViewModel?
    @State private var showNewSessionSheet = false
    @State private var selectedSession: Session?
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Group {
                if let vm = viewModel {
                    if vm.sessions.isEmpty && isSearchActive {
                        searchEmptyView
                    } else if vm.sessions.isEmpty {
                        emptyStateView
                    } else {
                        sessionsList(vm)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(L10n.Sessions.title)
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
                        selectedSession = session
                    }
                    showNewSessionSheet = false
                }
            }
            .searchable(text: $searchText, isPresented: $isSearchActive, prompt: L10n.Sessions.searchSessions)
            .onChange(of: searchText) { _, newValue in
                viewModel?.searchText = newValue
                viewModel?.applySearch()
            }
            .onChange(of: isSearchActive) { _, active in
                if !active && !searchText.isEmpty {
                    searchText = ""
                    viewModel?.searchText = ""
                    viewModel?.applySearch()
                }
            }
        } detail: {
            if let session = selectedSession {
                ChatView(session: session)
                    .id(session.id)
            } else {
                ContentUnavailableView {
                    Label(L10n.Sessions.selectSession, systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text(L10n.Sessions.selectSessionDescription)
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = SessionListViewModel(modelContext: modelContext)
            } else {
                viewModel?.fetchSessions()
            }
            viewModel?.startAutoRefresh()
        }
        .onDisappear {
            viewModel?.stopAutoRefresh()
        }
        .onChange(of: selectedSession) { oldValue, newValue in
            if oldValue != nil && newValue == nil {
                viewModel?.fetchSessions()
            }
        }
    }

    private var searchEmptyView: some View {
        ContentUnavailableView.search(text: searchText)
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(L10n.Sessions.noSessions, systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text(L10n.Sessions.noSessionsDescription)
        } actions: {
            Button(L10n.Sessions.newSession) {
                showNewSessionSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func sessionsList(_ vm: SessionListViewModel) -> some View {
        List(selection: $selectedSession) {
            ForEach(vm.sessions, id: \.id) { session in
                NavigationLink(value: session) {
                    SessionRowView(session: session, rowData: vm.rowDataCache[session.id])
                }
                .contextMenu {
                    Button(role: .destructive) {
                        vm.sessionToDelete = session
                    } label: {
                        Label(L10n.Common.delete, systemImage: "trash")
                    }
                }
            }
            .onDelete { offsets in
                guard let first = offsets.first else { return }
                vm.sessionToDelete = vm.sessions[first]
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            vm.fetchSessions()
        }
        .alert(L10n.Chat.deleteSessionTitle, isPresented: Binding(
            get: { vm.sessionToDelete != nil },
            set: { if !$0 { vm.sessionToDelete = nil } }
        )) {
            Button(L10n.Common.delete, role: .destructive) {
                if let session = vm.sessionToDelete {
                    if selectedSession?.id == session.id {
                        selectedSession = nil
                    }
                    vm.deleteSession(session)
                    vm.sessionToDelete = nil
                }
            }
            Button(L10n.Common.cancel, role: .cancel) {
                vm.sessionToDelete = nil
            }
        } message: {
            Text(L10n.Chat.deleteSessionMessage)
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
                        Label(L10n.Sessions.noAgents, systemImage: "cpu")
                    } description: {
                        Text(L10n.Sessions.noAgentsDescription)
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
                                    Text(L10n.Sessions.sessionsCount(agent.sessions.count))
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
            .navigationTitle(L10n.Sessions.selectAgent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
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
