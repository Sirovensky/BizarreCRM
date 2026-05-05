#if canImport(UIKit)
import UIKit
import SwiftUI
import Combine

// MARK: - §2.13 Session activity signals

/// Watches UIKit touch events and forwards them to `SessionTimer` as
/// activity signals.
///
/// **Activity signals (reset idle timer):** user touches, scrolls, text entry.
/// **Activity exclusions (do NOT reset timer):** silent push, background sync.
///
/// Usage — install once at the root window level:
/// ```swift
/// SessionActivityBridge.shared.attach(to: sessionTimer)
/// ```
///
/// The bridge observes `UIApplication.sendEvent(_:)` via method swizzling is
/// deliberately avoided; instead we use a dedicated `UIControl` sentinel that
/// SwiftUI roots can apply via `.touchInterceptor()`.
@MainActor
public final class SessionActivityBridge: ObservableObject {

    // MARK: - Shared instance

    public static let shared = SessionActivityBridge()

    // MARK: - State

    private weak var timer: SessionTimer?

    // MARK: - Init

    public init() {}

    // MARK: - Attach

    /// Attach a `SessionTimer` to receive touch-driven `touch()` calls.
    /// Call from your root authenticated view on appear.
    public func attach(to timer: SessionTimer) {
        self.timer = timer
    }

    /// Detach — call on sign-out.
    public func detach() {
        timer = nil
    }

    // MARK: - Signal sources (call these from SwiftUI gesture hooks)

    /// Record a real user interaction (touch, scroll, text entry).
    /// Excluded: silent push receipt, background sync callbacks.
    public func recordUserActivity() {
        guard let timer else { return }
        Task { await timer.touch() }
    }

    /// Called by `SessionActivityBridge.SwipeGestureProxy` for scroll events.
    public func recordScrollActivity() {
        recordUserActivity()
    }

    /// Called on `.onChange(of: text)` for text fields.
    public func recordTextActivity() {
        recordUserActivity()
    }

    // MARK: - Exclusions

    /// Call from APNs silent-push handler. This does NOT reset the session timer.
    public func notifySilentPushReceived() {
        // intentionally no timer.touch() — silent push is excluded per spec
    }

    /// Call from background sync completion. This does NOT reset the session timer.
    public func notifyBackgroundSyncCompleted() {
        // intentionally no timer.touch() — background sync is excluded per spec
    }
}

// MARK: - SwiftUI modifier

/// Apply to any root view to forward tap gestures to `SessionActivityBridge`.
///
/// ```swift
/// ContentView()
///     .sessionActivityTracking()
/// ```
public struct SessionActivityTrackingModifier: ViewModifier {
    @ObservedObject private var bridge: SessionActivityBridge

    public init(bridge: SessionActivityBridge = .shared) {
        self.bridge = bridge
    }

    public func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        bridge.recordUserActivity()
                    }
            )
    }
}

public extension View {
    /// Forwards user interactions to `SessionActivityBridge.shared` so the
    /// session idle timer is reset on each real touch or scroll.
    ///
    /// Excludes silent push and background-sync signals (those do not call this modifier).
    func sessionActivityTracking(bridge: SessionActivityBridge = .shared) -> some View {
        modifier(SessionActivityTrackingModifier(bridge: bridge))
    }
}

#endif
