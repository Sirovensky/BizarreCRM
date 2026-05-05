import Foundation
import Core

#if canImport(UIKit)
import UIKit
#endif

// MARK: - ForegroundLifecycleObserver (§21.6)
//
// Observes UIApplication foreground/background lifecycle events and
// broadcasts them so the app shell can trigger sync + WS reconnects.
//
// Wire once from AppServices:
// ```swift
// let observer = ForegroundLifecycleObserver.shared
// observer.onDidBecomeActive  = { await syncOrchestrator.lightweightSync() }
// observer.onWillResignActive = { await syncOrchestrator.flushPendingWrites() }
// observer.onMemoryWarning    = { ImageCache.shared.removeAll() }
// ```

@MainActor
public final class ForegroundLifecycleObserver {

    // MARK: - Shared

    public static let shared = ForegroundLifecycleObserver()

    // MARK: - Callbacks

    /// §21.6 didBecomeActive — lightweight sync + WS re-subscribe.
    public var onDidBecomeActive: (@Sendable () async -> Void)? = nil

    /// §21.6 willResignActive — flush pending writes; apply privacy snapshot if security toggle on.
    public var onWillResignActive: (@Sendable () async -> Void)? = nil

    /// §21.6 memory warning — flush image cache, reduce GRDB page cache.
    public var onMemoryWarning: (@Sendable () async -> Void)? = nil

    // MARK: - Init

    private init() {
        registerObservers()
    }

    // MARK: - Registration

    private func registerObservers() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        #endif
    }

    // MARK: - Handlers

    @objc private func handleDidBecomeActive() {
        AppLog.app.info("ForegroundLifecycleObserver: didBecomeActive — triggering sync + WS reconnect")
        Task { @MainActor in
            await onDidBecomeActive?()
        }
    }

    @objc private func handleWillResignActive() {
        AppLog.app.info("ForegroundLifecycleObserver: willResignActive — flushing pending writes")
        Task { @MainActor in
            await onWillResignActive?()
        }
    }

    @objc private func handleMemoryWarning() {
        AppLog.app.warning("ForegroundLifecycleObserver: memory warning — purging caches")
        Task { @MainActor in
            await onMemoryWarning?()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
