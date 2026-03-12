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
                Menu {
                    Button {
                        editingTitle = session.title
                        showTitleEditor = true
                    } label: {
                        Label(L10n.Chat.rename, systemImage: "pencil")
                    }

                    if let vm = viewModel {
                        Section {
                            Button {
                                vm.manualCompress()
                            } label: {
                                Label(L10n.Chat.compressContext, systemImage: "arrow.down.right.and.arrow.up.left")
                            }
                            .disabled(vm.isCompressing || vm.isLoading)
                        }

                        Section {
                            Text(vm.compressionInfo)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption)
                }
            }
        }
        .alert(L10n.Chat.renameSession, isPresented: $showTitleEditor) {
            TextField(L10n.Chat.title, text: $editingTitle)
            Button(L10n.Common.save) {
                let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    viewModel?.setCustomTitle(trimmed)
                }
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        }
        .onAppear {
            if viewModel == nil {
                viewModel = ChatViewModel(session: session, modelContext: modelContext)
            } else {
                viewModel?.onViewAppear()
            }
        }
        .onDisappear {
            viewModel?.onViewDisappear()
        }
    }
}

private struct ChatContentView: View {
    @Bindable var vm: ChatViewModel
    @State private var scrollPosition: UUID?
    @State private var hasRestoredScroll = false

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
                                if vm.isCancelling {
                                    Text(L10n.Chat.cancelling)
                                        .font(.subheadline)
                                        .foregroundStyle(.orange)
                                } else {
                                    Text(L10n.Chat.thinking)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding()
                            .id("loading")
                        }

                        if vm.isCompressing {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text(L10n.Chat.compressingContext)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .id("compressing")
                        }
                    }
                    .padding()
                }
                .scrollPosition(id: $scrollPosition, anchor: .top)
                .onAppear {
                    if !hasRestoredScroll {
                        hasRestoredScroll = true
                        if let target = vm.initialScrollTarget {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(target, anchor: .top)
                                }
                            }
                        } else if let lastId = vm.messages.last?.id {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
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
                .onDisappear {
                    if let visibleId = scrollPosition {
                        vm.saveScrollPosition(visibleId)
                    } else if let lastId = vm.messages.last?.id {
                        vm.saveScrollPosition(lastId)
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
                    Button(L10n.Common.dismiss) {
                        vm.errorMessage = nil
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }

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
                        Text(L10n.Common.refresh)
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
                isBlocked: !vm.canSend,
                isCancelling: vm.isCancelling,
                onSend: { vm.sendMessage() },
                onStop: { vm.cancelGeneration() }
            )
        }
    }
}
