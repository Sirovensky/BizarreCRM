import Foundation

// MARK: - HandoffReceiver

/// Handles incoming `NSUserActivity` continuations from Handoff.
///
/// Called from `.onContinueUserActivity(...)` SwiftUI modifiers on the
/// root scene (see `HandoffPublisher` for the wiring snippet).
///
/// Routes by extracting `userInfo["deepLinkURL"]` → `DeepLinkRouter.shared.handle(url)`.
@MainActor
public final class HandoffReceiver {

    // MARK: Singleton

    public static let shared = HandoffReceiver()

    private init() {}

    // MARK: Public API

    /// Handle a continuing `NSUserActivity`.
    ///
    /// Extracts the deep-link URL from `userInfo["deepLinkURL"]` and dispatches
    /// to `DeepLinkRouter.shared`. Returns `true` if the activity was handled.
    @discardableResult
    public func handle(_ activity: NSUserActivity) -> Bool {
        // 1. Try the deep-link URL stored in userInfo by HandoffPublisher.
        if
            let urlString = activity.userInfo?["deepLinkURL"] as? String,
            let url = URL(string: urlString)
        {
            DeepLinkRouter.shared.handle(url)
            return true
        }

        // 2. Fall back to webpageURL (universal link from Safari / other device).
        if let webURL = activity.webpageURL {
            DeepLinkRouter.shared.handle(webURL)
            return true
        }

        return false
    }
}
