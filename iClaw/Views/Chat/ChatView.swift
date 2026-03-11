import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    let session: Session
    @State private var viewModel: ChatViewModel?
    @State private var showTitleEditor = false
    @State private var editingTitle = ""

    var body: some View {
        Group {
            if let vm = viewModel {
                ChatContentView(vm: vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingTitle = session.title
                    showTitleEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
            }
        }
        .alert("Rename Session", isPresented: $showTitleEditor) {
            TextField("Title", text: $editingTitle)
            Button("Save") {
                let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    viewModel?.setCustomTitle(trimmed)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            if viewModel == nil {
                viewModel = ChatViewModel(session: session, modelContext: modelContext)
            }
        }
    }
}

private struct ChatContentView: View {
    @Bindable var vm: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(vm.messages, id: \.id) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }

                        if vm.isLoading && !vm.streamingContent.isEmpty {
                            MessageBubbleView(
                                streamingContent: vm.streamingContent
                            )
                            .id("streaming")
                        }

                        if vm.isLoading && vm.streamingContent.isEmpty {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text("Thinking...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .id("loading")
                        }
                    }
                    .padding()
                }
                .onChange(of: vm.messages.count) {
                    withAnimation {
                        proxy.scrollTo(vm.messages.last?.id, anchor: .bottom)
                    }
                }
                .onChange(of: vm.streamingContent) {
                    withAnimation {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }

            if let error = vm.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") {
                        vm.errorMessage = nil
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }

            // Blocked reason banner
            if let reason = vm.sendBlockedReason {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        vm.checkActiveSessionLock()
                    } label: {
                        Text("刷新")
                            .font(.caption)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
            }

            if let modelName = vm.activeModelName {
                Text(modelName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 2)
            }

            InputBarView(
                text: $vm.inputText,
                isLoading: vm.isLoading,
                isBlocked: !vm.canSend
            ) {
                vm.sendMessage()
            }
        }
    }
}
