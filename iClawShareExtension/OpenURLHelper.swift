import UIKit

/// Opens a URL from inside an app extension, which cannot use
/// `UIApplication.shared.open(_:)`. Walks the responder chain looking for an
/// object that responds to `openURL:`, which on iOS 17/18 is the standard
/// workaround for launching the host app from a Share Extension.
enum OpenURLHelper {

    @discardableResult
    static func open(_ url: URL, from responder: UIResponder) -> Bool {
        var current: UIResponder? = responder
        let selector = NSSelectorFromString("openURL:")
        while let r = current {
            if r.responds(to: selector) {
                _ = r.perform(selector, with: url)
                return true
            }
            current = r.next
        }
        return false
    }
}
