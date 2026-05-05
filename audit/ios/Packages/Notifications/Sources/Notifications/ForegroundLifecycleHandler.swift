import Foundation
import Core
import Networking
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Nuke)
import Nuke
#endif

// MARK: - §21.6 Foreground lifecycle handler

/// Observes `UIApplication` lifecycle events and coordinates:
/// - `didBecomeActive` — lightweight sync kick + WebSocket re-subscribe.
/// - `willResignActive` — flush pending writes; apply security blur if enabled.
/// - Memory warning — flush Nuke image cache, reduce GRDB page cache.
///
/// Wire from `AppServices.start()` or `BizarreCRMApp.onAppear`:
/// ```swift
/// let handler = ForegroundLifecycleHandler(api: api, wsManager: wsManager)
/// handler.start()
/// ```
@MainActor
public final class ForegroundLifecycleHandler {

    // MARK: - Dependencies

    private let api: APIClient
    private let wsManager: WebSocketManager
    /// If `true`, a blur overlay is presented when the app resigns active.
    public var securityBlurEnabled: Bool = false

    // MARK: - Private state

    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var blurWindow: BlurWindowWrapper?

    // MARK: - Init

    public init(api: APIClient, wsManager: WebSocketManager) {
        self.api = api
        self.wsManager = wsManager
    }

    deinit {
        #if canImport(UIKit)
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        #endif
    }

    // MARK: - Public API

    /// Start monitoring. Call once.
    public func start() {
        #if canImport(UIKit)
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.handleDidBecomeActive() }
        })

        observers.append(center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.handleWillResignActive() }
        })

        observers.append(center.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.handleMemoryWarning() }
        })
        #endif
    }

    // MARK: - Handlers

    private func handleDidBecomeActive() {
        AppLog.app.info("§21.6 didBecomeActive — syncing + re-subscribing WS")
        // Remove blur overlay if present
        blurWindow?.remove()
        blurWindow = nil
        // Re-subscribe WebSocket (no-op if already connected)
        Task { await wsManager.connectAll() }
        // Lightweight sync trigger — full sync is owned by SyncOrchestrator (Agent 10);
        // we only fire a notifications badge refresh here (our domain).
        Task {
            do {
                try await api.refreshBadgeCounts()
            } catch {
                AppLog.app.warning("§21.6 badge refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func handleWillResignActive() {
        AppLog.app.info("§21.6 willResignActive — flushing + security blur")
        // Security blur: overlay opaque window to hide sensitive data in app switcher
        if securityBlurEnabled {
            #if canImport(UIKit)
            blurWindow = BlurWindowWrapper()
            blurWindow?.show()
            #endif
        }
        // Flush pending writes — done by SyncOrchestrator on this notification;
        // we post a custom notification for domain-specific Notifications flush.
        NotificationCenter.default.post(name: .notificationsFlushPendingWrites, object: nil)
    }

    private func handleMemoryWarning() {
        AppLog.app.warning("§21.6 didReceiveMemoryWarning — flushing image cache")
        #if canImport(Nuke)
        ImagePipeline.shared.cache.removeAll()
        #endif
        // Also purge NSCache-backed in-memory stores in Networking.
        URLCache.shared.removeAllCachedResponses()
    }
}

// MARK: - Notification name

public extension Notification.Name {
    /// Posted by `ForegroundLifecycleHandler.handleWillResignActive()`.
    static let notificationsFlushPendingWrites = Notification.Name("com.bizarrecrm.notifications.flushPendingWrites")
}

// MARK: - Blur window (security blur overlay)

/// Minimal opaque window placed above all others when app resigns active,
/// preventing sensitive data from being visible in the iOS app switcher.
#if canImport(UIKit)
@MainActor
private final class BlurWindowWrapper {
    private weak var window: UIWindow?

    func show() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }

        let win = UIWindow(windowScene: scene)
        win.windowLevel = .alert + 1
        win.backgroundColor = UIColor(named: "BizarreSurfaceBase") ?? .systemBackground

        let vc = UIViewController()
        vc.view.backgroundColor = win.backgroundColor

        let imgView = UIImageView(image: UIImage(systemName: "lock.fill"))
        imgView.tintColor = .secondaryLabel
        imgView.contentMode = .scaleAspectFit
        imgView.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(imgView)
        NSLayoutConstraint.activate([
            imgView.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
            imgView.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor),
            imgView.widthAnchor.constraint(equalToConstant: 48),
            imgView.heightAnchor.constraint(equalToConstant: 48),
        ])

        win.rootViewController = vc
        win.isHidden = false
        self.window = win
    }

    func remove() {
        window?.isHidden = true
        window = nil
    }
}
#endif

// MARK: - APIClient convenience

public extension APIClient {
    /// Lightweight badge-count refresh for foreground re-activation.
    /// Just refetches unread notification count; full sync is SyncOrchestrator's job.
    func refreshBadgeCounts() async throws {
        // GET /api/v1/notifications/unread-count — the response is handled by
        // NotificationBadgeCounter (Notifications package), not here. We call
        // through so the HTTP response re-seeds the badge pipeline.
        _ = try await get("notifications/unread-count", as: [String: Int].self)
    }
}
