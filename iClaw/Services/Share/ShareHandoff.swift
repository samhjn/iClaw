import Foundation
import SwiftData
import os.log

/// Processes `iclaw://session/new?agentId=<uuid>&handoffId=<uuid>` deep links
/// emitted by the Share Extension.
///
/// Responsibilities:
/// 1. Look up the target root agent.
/// 2. Create a new session for that agent.
/// 3. Move staged files from the App Group's `ShareStaging/<handoffId>/`
///    directory into the agent's on-disk file folder.
/// 4. Seed in-memory `ChatViewModel` caches so the compose area shows the
///    shared files as pending attachments without writing `Session.draft*`.
/// 5. Publish the new session via `PendingSessionRouter` so
///    `SessionListView` navigates to it.
/// 6. Delete the staging directory.
enum ShareHandoff {

    private static let log = OSLog(subsystem: "com.iclaw.share", category: "handoff")

    // MARK: - Public entry points

    /// Returns true if the URL is a share-handoff deep link this processor
    /// knows how to handle.
    static func isHandoffURL(_ url: URL) -> Bool {
        guard url.scheme == "iclaw" else { return false }
        guard url.host == "session" else { return false }
        let components = url.pathComponents.filter { $0 != "/" }
        return components.first == "new"
    }

    /// Process the deep link. Must run on the main actor because it touches
    /// SwiftData relationships.
    @MainActor
    static func apply(
        url: URL,
        modelContainer: ModelContainer,
        router: PendingSessionRouter
    ) {
        guard isHandoffURL(url) else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let agentIdStr = components.queryItems?.first(where: { $0.name == "agentId" })?.value,
              let agentId = UUID(uuidString: agentIdStr),
              let handoffIdStr = components.queryItems?.first(where: { $0.name == "handoffId" })?.value,
              let handoffId = UUID(uuidString: handoffIdStr) else {
            os_log(.error, log: log, "Invalid handoff URL: %{public}@", url.absoluteString)
            return
        }

        let context = modelContainer.mainContext
        guard let agent = fetchRootAgent(id: agentId, context: context) else {
            os_log(.error, log: log, "Unknown agent: %{public}@", agentId.uuidString)
            cleanupStaging(handoffId: handoffId)
            return
        }

        guard let stagingDir = SharedContainer.stagingDirectory(handoffId: handoffId),
              FileManager.default.fileExists(atPath: stagingDir.path),
              let manifest = HandoffManifest.load(from: stagingDir) else {
            os_log(.error, log: log, "Missing or invalid staging dir for handoff %{public}@", handoffId.uuidString)
            return
        }

        os_log(.info, log: log, "Applying handoff %{public}@: %d files for agent %{public}@",
               handoffId.uuidString, manifest.files.count, agent.name)

        let resolvedAgentId = AgentFileManager.shared.resolveAgentId(for: agent)

        // First pass: move bytes into the agent folder and classify them.
        var pendingImages: [ImageAttachment] = []
        var pendingFiles: [FileAttachment] = []
        var pendingVideoRefs: [String] = []

        for file in manifest.files {
            let src = stagingDir.appendingPathComponent(file.name)
            guard FileManager.default.fileExists(atPath: src.path),
                  let data = try? Data(contentsOf: src) else {
                continue
            }

            let finalName = uniqueFilename(preferred: file.name, agentId: resolvedAgentId)
            do {
                try AgentFileManager.shared.writeFile(agentId: resolvedAgentId, name: finalName, data: data)
            } catch {
                os_log(.error, log: log, "Failed to copy staged file %{public}@: %{public}@",
                       file.name, String(describing: error))
                continue
            }
            let ref = AgentFileManager.makeFileReference(agentId: resolvedAgentId, filename: finalName)

            switch file.kind {
            case .image:
                if let img = ImageAttachment.from(fileReference: ref) {
                    pendingImages.append(img)
                } else if let fallback = FileAttachment.from(fileReference: ref) {
                    pendingFiles.append(fallback)
                }
            case .video:
                pendingVideoRefs.append(ref)
            case .file, .text:
                if let f = FileAttachment.from(fileReference: ref) {
                    pendingFiles.append(f)
                }
            }
        }

        // Skip if nothing usable arrived.
        guard !(pendingImages.isEmpty && pendingFiles.isEmpty && pendingVideoRefs.isEmpty) else {
            os_log(.error, log: log, "Handoff %{public}@ had no usable files", handoffId.uuidString)
            cleanupStaging(handoffId: handoffId)
            return
        }

        // Create the session on the *main* context so SessionListView's
        // FetchDescriptor-based list picks it up without a cross-context save
        // round trip. Seed caches BEFORE publishing the session so the
        // ChatView's init reads them on first mount.
        let session = Session(title: L10n.Chat.newChat)
        context.insert(session)
        session.agent = agent
        do {
            try context.save()
        } catch {
            os_log(.error, log: log, "Failed to save new session: %{public}@", String(describing: error))
            cleanupStaging(handoffId: handoffId)
            return
        }

        if !pendingImages.isEmpty {
            ChatViewModel.seedPendingImages(for: session.id, append: pendingImages)
        }
        if !pendingFiles.isEmpty {
            ChatViewModel.seedPendingFiles(for: session.id, append: pendingFiles)
        }
        os_log(.info, log: log, "Seeded %d images, %d files, %d video refs pending for session %{public}@",
               pendingImages.count, pendingFiles.count, pendingVideoRefs.count, session.id.uuidString)

        // Video metadata extraction is async; seed as each completes.
        let sessionId = session.id
        for ref in pendingVideoRefs {
            Task { @MainActor in
                if let vid = await VideoAttachment.from(fileReference: ref) {
                    ChatViewModel.seedPendingVideos(for: sessionId, append: [vid])
                }
            }
        }

        router.pendingSession = session
        cleanupStaging(handoffId: handoffId)
    }

    // MARK: - Orphan sweep

    /// On launch, delete any staging directories older than `maxAge` seconds.
    /// Covers the case where the user cancelled out of the Share Extension or
    /// force-quit the host app before the handoff was consumed.
    static func sweepOrphans(maxAge: TimeInterval = 24 * 60 * 60) {
        guard let staging = SharedContainer.stagingDirectory,
              FileManager.default.fileExists(atPath: staging.path) else { return }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: staging,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for url in entries {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if mtime < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Helpers

    private static func fetchRootAgent(id: UUID, context: ModelContext) -> Agent? {
        let descriptor = FetchDescriptor<Agent>(
            predicate: #Predicate { $0.id == id && $0.parentAgent == nil }
        )
        return try? context.fetch(descriptor).first
    }

    private static func uniqueFilename(preferred: String, agentId: UUID) -> String {
        let safe = AgentFileManager.isSafeFilename(preferred) ? preferred : "file_\(UUID().uuidString.prefix(8))"
        guard AgentFileManager.shared.fileExists(agentId: agentId, name: safe) else { return safe }
        let ns = safe as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension
        let suffix = UUID().uuidString.prefix(6)
        if ext.isEmpty {
            return "\(base)_\(suffix)"
        }
        return "\(base)_\(suffix).\(ext)"
    }

    private static func cleanupStaging(handoffId: UUID) {
        guard let dir = SharedContainer.stagingDirectory(handoffId: handoffId) else { return }
        try? FileManager.default.removeItem(at: dir)
    }
}
