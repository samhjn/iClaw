import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AgentFileBrowserView: View {
    let agent: Agent
    @State private var files: [FileInfo] = []
    @State private var showDocumentPicker = false
    @State private var showDeleteConfirm: FileInfo?
    @State private var errorMessage: String?

    private var agentId: UUID {
        AgentFileManager.shared.resolveAgentId(for: agent)
    }

    var body: some View {
        List {
            if files.isEmpty {
                ContentUnavailableView(
                    L10n.AgentFiles.empty,
                    systemImage: "folder",
                    description: Text(L10n.AgentFiles.emptyDescription)
                )
            } else {
                ForEach(files) { file in
                    FileRowView(file: file, agentId: agentId)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                showDeleteConfirm = file
                            } label: {
                                Label(L10n.Common.delete, systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                shareFile(file)
                            } label: {
                                Label(L10n.Chat.share, systemImage: "square.and.arrow.up")
                            }
                            Button(role: .destructive) {
                                showDeleteConfirm = file
                            } label: {
                                Label(L10n.Common.delete, systemImage: "trash")
                            }
                        }
                }
            }
        }
        .navigationTitle(L10n.AgentFiles.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showDocumentPicker = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear { refreshFiles() }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerView { urls in
                importFiles(urls)
            }
        }
        .alert(L10n.AgentFiles.deleteConfirmTitle, isPresented: Binding(
            get: { showDeleteConfirm != nil },
            set: { if !$0 { showDeleteConfirm = nil } }
        )) {
            Button(L10n.Common.delete, role: .destructive) {
                if let file = showDeleteConfirm {
                    deleteFile(file)
                }
                showDeleteConfirm = nil
            }
            Button(L10n.Common.cancel, role: .cancel) { showDeleteConfirm = nil }
        } message: {
            if let file = showDeleteConfirm {
                Text(L10n.AgentFiles.deleteConfirmMessage(file.name))
            }
        }
        .overlay {
            if let msg = errorMessage {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.red.opacity(0.8)))
                        .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { errorMessage = nil }
                    }
                }
            }
        }
    }

    private func refreshFiles() {
        files = AgentFileManager.shared.listFiles(agentId: agentId)
    }

    private func deleteFile(_ file: FileInfo) {
        do {
            try AgentFileManager.shared.deleteFile(agentId: agentId, name: file.name)
            refreshFiles()
        } catch {
            withAnimation { errorMessage = error.localizedDescription }
        }
    }

    private func importFiles(_ urls: [URL]) {
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let name = url.lastPathComponent
            do {
                try AgentFileManager.shared.writeFile(agentId: agentId, name: name, data: data)
            } catch {
                withAnimation { errorMessage = error.localizedDescription }
            }
        }
        refreshFiles()
    }

    private func shareFile(_ file: FileInfo) {
        let url = AgentFileManager.shared.fileURL(agentId: agentId, name: file.name)
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController { topVC = presented }
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topVC.view
                popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            topVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - File Row

private struct FileRowView: View {
    let file: FileInfo
    let agentId: UUID

    var body: some View {
        Button {
            if file.isImage, let data = try? AgentFileManager.shared.readFile(agentId: agentId, name: file.name),
               let img = UIImage(data: data) {
                ImagePreviewCoordinator.shared.show(img)
            }
        } label: {
            HStack(spacing: 12) {
                fileIcon
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Text(file.formattedSize)
                        Text(file.modifiedAt, style: .relative)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var fileIcon: some View {
        if file.isImage, let data = try? AgentFileManager.shared.readFile(agentId: agentId, name: file.name),
           let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                Image(systemName: iconForExtension(file.name))
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func iconForExtension(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "txt", "md", "log": return "doc.text"
        case "json", "xml", "csv", "yaml", "yml": return "doc.badge.gearshape"
        case "pdf": return "doc.richtext"
        case "zip", "gz", "tar", "rar": return "archivebox"
        case "js", "py", "swift", "html", "css": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }
}

// MARK: - Document Picker

struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView
        init(_ parent: DocumentPickerView) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls)
            parent.dismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}
