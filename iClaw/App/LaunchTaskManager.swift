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
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Agent>()
        guard let allAgents = try? context.fetch(descriptor) else { return }
        let knownIds = Set(allAgents.map(\.id))
        AgentFileManager.shared.cleanupOrphanDirectories(knownAgentIds: knownIds)
    }

    // MARK: - Backfill embeddings (CPU-throttled)

    private func backfillSessionEmbeddings() async {
        let context = ModelContext(container)
        let store = SessionVectorStore(modelContext: context)

        let pending = store.sessionsNeedingEmbedding()
        let total = pending.count
        guard total > 0 else { return }

        let batchSize = 5
        for (index, session) in pending.enumerated() {
            if Task.isCancelled { break }

            store.updateEmbedding(for: session)

            let progress = Double(index + 1) / Double(total)
            await MainActor.run {
                self.phase = .running(
                    description: L10n.Launch.buildingIndex,
                    progress: progress
                )
            }

            // Yield CPU every batch to keep the system responsive
            if (index + 1) % batchSize == 0 && index + 1 < total {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}
