import UIKit
import os.log

private let openLog = OSLog(subsystem: "com.iclaw.share", category: "openurl")

/// Opens a URL from inside an app extension, which cannot use
/// `UIApplication.shared.open(_:)`. Walks the responder chain looking for an
/// object that responds to `openURL:`, which on iOS 17/18 is the standard
/// workaround for launching the host app from a Share Extension.
enum OpenURLHelper {

    @discardableResult
    static func open(_ url: URL, from responder: UIResponder) -> Bool {
        var current: UIResponder? = responder
        let selector = NSSelectorFromString("openURL:")
        var hops = 0
        while let r = current {
            hops += 1
            if r.responds(to: selector) {
                os_log(.info, log: openLog, "Found responder after %d hops: %{public}@",
                       hops, String(describing: type(of: r)))
                _ = r.perform(selector, with: url)
                return true
            }
            current = r.next
        }
        os_log(.error, log: openLog,
               "Responder chain exhausted after %d hops — could not open URL %{public}@",
               hops, url.absoluteString)
        return false
    }
}
