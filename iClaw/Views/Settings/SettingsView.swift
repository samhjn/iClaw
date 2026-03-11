import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SettingsViewModel?
    @State private var showAddProvider = false

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    settingsList(vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showAddProvider) {
                if let vm = viewModel {
                    LLMProviderEditView(viewModel: vm)
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = SettingsViewModel(modelContext: modelContext)
            } else {
                viewModel?.fetchProviders()
            }
        }
    }

    private func settingsList(_ vm: SettingsViewModel) -> some View {
        List {
            Section("LLM Providers") {
                ForEach(vm.providers, id: \.id) { provider in
                    NavigationLink {
                        LLMProviderEditView(viewModel: vm, existingProvider: provider)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                    .font(.headline)
                                Text(provider.modelName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(provider.endpoint)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if provider.isDefault {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            vm.deleteProvider(provider)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        if !provider.isDefault {
                            Button {
                                vm.setDefault(provider)
                            } label: {
                                Label("Default", systemImage: "checkmark")
                            }
                            .tint(.green)
                        }
                    }
                }

                Button {
                    showAddProvider = true
                } label: {
                    Label("Add Provider", systemImage: "plus")
                }
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
