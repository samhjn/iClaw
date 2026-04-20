import UIKit
import SwiftUI
import os.log

private let vcLog = OSLog(subsystem: "com.iclaw.share", category: "viewcontroller")

/// Principal class for the Share Extension. Hosts `SharePickerView` and
/// orchestrates the lifecycle: load agent snapshot → user picks agent →
/// stage attachments → open host app via deep link.
final class ShareViewController: UIViewController {

    private var hostingController: UIHostingController<SharePickerView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        let containerAvailable = SharedContainer.containerURL != nil
        let snapshot = AgentSnapshot.load()
        let agents = snapshot?.agents ?? []

        NSLog("[iClawShare] viewDidLoad — containerAvailable=%@ snapshotAgents=%d",
              containerAvailable ? "YES" : "NO",
              agents.count)
        os_log(.default, log: vcLog,
               "viewDidLoad containerAvailable=%{public}@ snapshotAgents=%d",
               containerAvailable ? "YES" : "NO", agents.count)

        let picker = SharePickerView(
            agents: agents,
            containerAvailable: containerAvailable,
            onSelect: { [weak self] agent in
                self?.handleSelection(agent: agent)
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )

        let host = UIHostingController(rootView: picker)
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
        hostingController = host
    }

    // MARK: - Flow

    private func handleSelection(agent: AgentSnapshotEntry) {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        NSLog("[iClawShare] handleSelection agent=%@ inputItems=%d",
              agent.name, items.count)
        Task { [weak self] in
            guard let self else { return }
            let handoffId = await ShareItemStager.stage(items: items, agentId: agent.id)
            await MainActor.run {
                guard let handoffId else {
                    NSLog("[iClawShare] stager returned nil — nothing to share")
                    self.finish(withError: "Nothing to share. Check that iClaw has App Group access.")
                    return
                }
                NSLog("[iClawShare] stager produced handoffId=%@", handoffId.uuidString)
                self.openHostApp(agentId: agent.id, handoffId: handoffId)
            }
        }
    }

    private func openHostApp(agentId: UUID, handoffId: UUID) {
        var components = URLComponents()
        components.scheme = "iclaw"
        components.host = "session"
        components.path = "/new"
        components.queryItems = [
            URLQueryItem(name: "agentId", value: agentId.uuidString),
            URLQueryItem(name: "handoffId", value: handoffId.uuidString),
        ]
        guard let url = components.url else {
            os_log(.error, log: vcLog, "Could not build handoff URL")
            cancel()
            return
        }
        NSLog("[iClawShare] openHostApp url=%@", url.absoluteString)
        os_log(.default, log: vcLog, "Opening host app url=%{public}@", url.absoluteString)

        // iOS 18 fully disabled the legacy responder-chain `openURL:` private
        // selector. `NSExtensionContext.open(_:completionHandler:)` is the
        // supported API; it works from share extensions targeting the host
        // app's registered URL scheme.
        guard let context = extensionContext else {
            NSLog("[iClawShare] No extension context — cannot open host app")
            cancel()
            return
        }

        context.open(url) { [weak context] success in
            NSLog("[iClawShare] context.open returned success=%@", success ? "YES" : "NO")
            DispatchQueue.main.async {
                context?.completeRequest(returningItems: [], completionHandler: nil)
            }
        }
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(
            domain: "com.iclaw.share",
            code: NSUserCancelledError,
            userInfo: nil
        ))
    }

    private func finish(withError message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.cancel()
        })
        present(alert, animated: true)
    }
}
