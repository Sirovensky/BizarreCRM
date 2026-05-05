import Foundation
import Core

// MARK: - Known entity types (allowlist)

/// Exhaustive list of entity types the server is permitted to include in
/// push `userInfo`.  Any unknown string is silently dropped to prevent
/// push-phishing via injected deep-link paths.
private let kEntityTypeAllowlist: Set<String> = [
    "ticket",
    "customer",
    "invoice",
    "estimate",
    "appointment",
    "sms",
    "thread",
    "expense",
    "lead",
    "employee",
    "notification",
]

// MARK: - NotificationDeepLinkCoordinator

/// Converts the `userInfo` dictionary from an APNs payload into a
/// `bizarrecrm://` URL and forwards it to the injected `DeepLinkHandling`
/// router.
///
/// Rules:
/// - `deepLink` key (pre-formed URL string) is used verbatim when present.
/// - Otherwise the coordinator synthesises a URL from `entityType` + `entityId`.
/// - Entity type **must** be in `kEntityTypeAllowlist`; unknown types are
///   dropped and logged — this prevents push-phishing with arbitrary paths.
/// - All inputs are validated; nil / empty inputs are no-ops.
///
/// Usage (typically wired during DI bootstrap):
/// ```swift
/// let coord = NotificationDeepLinkCoordinator(router: DeepLinkRouter.shared)
/// NotificationHandler.shared.configure(deepLinkRouter: coord)
/// ```
public final class NotificationDeepLinkCoordinator: DeepLinkHandling, Sendable {

    // MARK: - Dependencies

    private let router: any DeepLinkHandling

    // MARK: - Init

    public init(router: any DeepLinkHandling) {
        self.router = router
    }

    // MARK: - DeepLinkHandling

    @MainActor
    public func handle(_ url: URL) {
        router.handle(url)
    }

    // MARK: - Payload parsing

    /// Build a URL from an APNs `userInfo` dictionary and forward to router.
    /// Returns the URL that was dispatched, or `nil` when the payload was
    /// invalid / rejected by the allowlist.
    @MainActor
    @discardableResult
    public func handlePushPayload(_ userInfo: [AnyHashable: Any]) -> URL? {
        // 1. Prefer a pre-formed deep link string from the server.
        if let raw = userInfo["deepLink"] as? String,
           let url = URL(string: raw),
           isAllowedURL(url) {
            router.handle(url)
            return url
        }

        // 2. Synthesise from entityType + entityId.
        guard
            let entityType = (userInfo["entityType"] as? String
                              ?? userInfo["entity_type"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
            kEntityTypeAllowlist.contains(entityType)
        else {
            AppLog.ui.debug("NotificationDeepLinkCoordinator: no valid entityType in userInfo")
            return nil
        }

        let entityIdRaw = userInfo["entityId"] as? String
                       ?? userInfo["entity_id"] as? String
                       ?? (userInfo["entityId"] as? Int).map(String.init)
                       ?? (userInfo["entity_id"] as? Int).map(String.init)

        guard let entityId = entityIdRaw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !entityId.isEmpty,
              entityId.allSatisfy({ $0.isNumber || $0 == "-" })
        else {
            AppLog.ui.debug("NotificationDeepLinkCoordinator: missing or non-numeric entityId for '\(entityType)'")
            return nil
        }

        // Build `bizarrecrm://<scheme-host>/<entityType>/<entityId>`
        var comps = URLComponents()
        comps.scheme = "bizarrecrm"
        comps.host = entityType
        comps.path = "/\(entityId)"
        guard let url = comps.url else {
            AppLog.ui.error("NotificationDeepLinkCoordinator: failed to build URL for \(entityType)/\(entityId)")
            return nil
        }

        router.handle(url)
        return url
    }

    // MARK: - Allowlist check

    /// Returns `true` when the URL is a `bizarrecrm://` URL whose host is in
    /// the entity allowlist. Rejects http(s) URLs, unknown schemes, and
    /// unknown entity types to prevent push-phishing.
    private func isAllowedURL(_ url: URL) -> Bool {
        guard url.scheme == "bizarrecrm",
              let host = url.host,
              kEntityTypeAllowlist.contains(host.lowercased())
        else {
            AppLog.ui.error("NotificationDeepLinkCoordinator: rejected URL '\(url.absoluteString, privacy: .public)' — not in allowlist")
            return false
        }
        return true
    }
}
