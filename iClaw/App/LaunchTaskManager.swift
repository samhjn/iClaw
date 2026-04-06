import Foundation
import SwiftData
import Observation

@Observable
final class LaunchTaskManager {

    enum TaskPhase: Equatable {
        case idle
        case running(description: String, progress: Double?)
        case done
    }

    private(set) var phase: TaskPhase = .idle
    private(set) var completedCount = 0
    private(set) var totalCount = 0

    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Public

    @MainActor
    func runAll() {
        guard phase == .idle else { return }
        totalCount = 2
        completedCount = 0
        phase = .running(description: L10n.Launch.cleaningUp, progress: nil)

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            await self.cleanupOrphanAgentFiles()
            await MainActor.run {
                self.completedCount = 1
                self.phase = .running(
                    description: L10n.Launch.buildingIndex,
                    progress: 0
                )
            }

            await self.backfillSessionEmbeddings()
            await MainActor.run {
                self.completedCount = 2
                self.phase = .done
            }
        }
    }

    // MARK: - Cleanup orphan agent files

    private func cleanupOrphanAgentFiles() async {
        let knownIds: Set<UUID> = await MainActor.run {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Agent>()
            guard let allAgents = try? context.fetch(descriptor) else { return Set() }
            return Set(allAgents.map(\.id))
        }
        guard !knownIds.isEmpty else { return }
        AgentFileManager.shared.cleanupOrphanDirectories(knownAgentIds: knownIds)
    }

    // MARK: - Backfill embeddings (CPU-throttled)

    private func backfillSessionEmbeddings() async {
        let pending: [SessionEmbeddingTask] = await MainActor.run {
            let context = ModelContext(container)
            let store = SessionVectorStore(modelContext: context)
            return store.sessionsNeedingEmbedding().map {
                SessionEmbeddingTask(sessionId: $0.id, text: SessionVectorStore.buildEmbeddingText(for: $0))
            }
        }
        let total = pending.count
        guard total > 0 else { return }

        let localService = LocalEmbeddingService()
        let batchSize = 5

        var computed: [(sessionId: UUID, vector: [Float], text: String)] = []

        for (index, task) in pending.enumerated() {
            if Task.isCancelled { break }

            guard !task.text.isEmpty else { continue }
            guard let vector = localService.embed(text: task.text) else { continue }
            computed.append((task.sessionId, vector, task.text))

            let progress = Double(index + 1) / Double(total)
            await MainActor.run {
                self.phase = .running(
                    description: L10n.Launch.buildingIndex,
                    progress: progress
                )
            }

            if (index + 1) % batchSize == 0 && index + 1 < total {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        guard !computed.isEmpty else { return }
        let results = computed
        await MainActor.run {
            let context = ModelContext(self.container)
            let store = SessionVectorStore(modelContext: context)
            for item in results {
                store.upsertEmbeddingDirect(
                    sessionId: item.sessionId,
                    vector: item.vector,
                    sourceText: item.text
                )
            }
        }
    }
}

private struct SessionEmbeddingTask {
    let sessionId: UUID
    let text: String
}
