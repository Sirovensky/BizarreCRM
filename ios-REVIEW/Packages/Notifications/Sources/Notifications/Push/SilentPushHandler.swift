import Foundation
import Core
import Sync

// MARK: - SilentPushPayloadKind

/// Typed representation of the `kind` field in the silent push `userInfo`.
/// Server sends: `{ "aps": { "content-available": 1 }, "kind": "<value>", ... }`.
public enum SilentPushKind: String, Sendable {
    /// Full incremental sync across all domains.
    case sync = "sync"
    /// A specific ticket was created or updated.
    case ticket = "ticket"
    /// A specific customer record changed.
    case customer = "customer"
    /// An invoice was created or updated.
    case invoice = "invoice"
    /// An SMS thread has a new message.
    case sms = "sms"
    /// Inventory quantity changed.
    case inventory = "inventory"
    /// A dead-letter sync op was written.
    case deadletter = "deadletter"
    /// Appointment updated.
    case appointment = "appointment"
}

// MARK: - EntityRefreshTrigger

/// Injected strategy for refreshing a specific entity.
/// Implementations live in the feature packages and are set up by
/// the app during DI bootstrap — keeping this package free of feature deps.
public protocol EntityRefreshTrigger: Sendable {
    /// Ask the target feature package to refresh the given entity.
    /// `kind` maps to `SilentPushKind.rawValue`, `entityId` is the server ID.
    func refresh(kind: String, entityId: String?) async
}

// MARK: - SilentPushHandler

/// Handles `content-available: 1` silent pushes from the server.
///
/// Wire into `UIApplicationDelegate`:
/// ```swift
/// func application(
///     _ application: UIApplication,
///     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
///     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
/// ) {
///     Task {
///         await SilentPushHandler.shared.handle(userInfo: userInfo)
///         completionHandler(.newData)
///     }
/// }
/// ```
/// The handler must complete (or at least call the block) within 30 seconds
/// per iOS background execution rules.
public actor SilentPushHandler {

    // MARK: - Shared
    // Note: `shared` is set up by the app host at launch via `SilentPushHandler.configure(syncManager:)`.
    // Declared as a nonisolated var so the app can assign it once from BizarreCRMApp.
    // Using a non-isolated nonisolated(unsafe) because SyncManager is @MainActor.
    nonisolated(unsafe) public static var shared: SilentPushHandler = {
        // Placeholder — must be replaced by the app calling SilentPushHandler.setUp(syncManager:)
        // before any silent push can arrive.  Crash-safe: real SyncManager injected at app init.
        fatalError("SilentPushHandler.shared must be configured via SilentPushHandler.setUp(syncManager:) before use")
    }()

    /// Called once from app bootstrap.  Example:
    /// ```swift
    /// await MainActor.run {
    ///     SilentPushHandler.setUp(syncManager: SyncManager.shared)
    /// }
    /// ```
    @MainActor
    public static func setUp(syncManager: SyncManager) {
        shared = SilentPushHandler(syncManager: syncManager)
    }

    // MARK: - Init / DI

    private let syncManager: SyncManager
    private var entityTrigger: EntityRefreshTrigger?

    public init(syncManager: SyncManager) {
        self.syncManager = syncManager
    }

    /// Register a feature-level entity refresh trigger. Called once from
    /// the app's DI bootstrap so this package doesn't import feature packages.
    public func setEntityRefreshTrigger(_ trigger: EntityRefreshTrigger) {
        entityTrigger = trigger
    }

    // MARK: - Handle

    /// Dispatches the incoming silent push to the appropriate handler.
    /// Safe to call from any async context.
    public func handle(userInfo: [AnyHashable: Any]) async {
        guard let aps = userInfo["aps"] as? [String: Any],
              (aps["content-available"] as? Int) == 1
        else {
            AppLog.sync.debug("SilentPushHandler: ignored non-silent push")
            return
        }

        let kindRaw = userInfo["kind"] as? String ?? "sync"
        let entityId = userInfo["entityId"] as? String ?? userInfo["entity_id"] as? String

        AppLog.sync.info("SilentPushHandler received kind=\(kindRaw, privacy: .public)")

        guard let kind = SilentPushKind(rawValue: kindRaw) else {
            // Unknown kind — fall back to full sync so we don't lose data.
            AppLog.sync.info("SilentPushHandler: unknown kind '\(kindRaw, privacy: .public)', falling back to sync")
            await syncManager.syncNow()
            return
        }

        switch kind {
        case .sync:
            await syncManager.syncNow()

        case .ticket, .customer, .invoice, .sms, .inventory, .appointment:
            if let trigger = entityTrigger {
                await trigger.refresh(kind: kind.rawValue, entityId: entityId)
            } else {
                // No trigger registered yet — fall back to full sync.
                await syncManager.syncNow()
            }

        case .deadletter:
            // Dead-letter alert — trigger a sync which will surface dead-letter
            // entries in the Dead Letter Viewer via the existing observer.
            await syncManager.syncNow()
        }
    }
}
