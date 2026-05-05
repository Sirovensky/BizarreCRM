import Foundation
#if canImport(UIKit)
import UIKit
#endif

// §29.2 CADisplayLink-based scroll frame drop guard.
//
// `ScrollPerfTracer` (actor) records frame elapsed times supplied by the caller.
// `CADisplayLinkScrollGuard` goes one level lower: it installs a `CADisplayLink`
// on the main run loop and measures the *actual* inter-frame interval that the
// display hardware delivers. This catches jank that SwiftUI's preference-change
// / onPreferenceChange callbacks miss (e.g. a dropped frame that does not
// trigger a view update at all).
//
// Lifecycle:
//   `start()` — attach the display link; call when a scrollable list appears.
//   `stop()`  — detach and flush stats; call on disappear or when the list is
//               no longer in focus.
//
// The guard feeds measured frame intervals directly into `ScrollPerfTracer.shared`
// so all budget logic lives in one place.
//
// Usage:
// ```swift
// @State private var scrollGuard = CADisplayLinkScrollGuard()
//
// SomeList()
//     .onAppear  { scrollGuard.start() }
//     .onDisappear { scrollGuard.stop() }
// ```

/// Installs a `CADisplayLink` to measure real display-frame intervals and feeds
/// them into ``ScrollPerfTracer`` for budget enforcement.
///
/// - Note: All public methods are `@MainActor` because `CADisplayLink` callbacks
///   fire on the main run loop.
@MainActor
public final class CADisplayLinkScrollGuard {

    // MARK: - Configuration

    /// Minimum interval reported as a valid frame (filters out artificially long
    /// gaps when the app was backgrounded or the display link was paused).
    public static let maxValidFrameMs: Double = 200

    // MARK: - State

#if canImport(UIKit)
    private var displayLink: CADisplayLink?
    private var previousTimestamp: CFTimeInterval = 0
#endif

    private var isRunning: Bool = false

    // MARK: - Init

    public init() {}

    // MARK: - Lifecycle

    /// Attach the `CADisplayLink` and begin measuring frame intervals.
    ///
    /// Safe to call multiple times — subsequent calls are no-ops if already running.
    public func start() {
#if canImport(UIKit)
        guard !isRunning else { return }
        let link = CADisplayLink(target: self, selector: #selector(handleFrame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        previousTimestamp = 0
        isRunning = true
        AppLog.perf.debug("[CADisplayLinkScrollGuard] started")
#endif
    }

    /// Detach the `CADisplayLink` and stop measuring.
    ///
    /// Idempotent — safe to call even when already stopped.
    public func stop() {
#if canImport(UIKit)
        guard isRunning else { return }
        displayLink?.invalidate()
        displayLink = nil
        isRunning = false
        AppLog.perf.debug("[CADisplayLinkScrollGuard] stopped")
#endif
    }

    // MARK: - Display link callback

#if canImport(UIKit)
    @objc private func handleFrame(_ link: CADisplayLink) {
        let timestamp = link.timestamp
        guard previousTimestamp > 0 else {
            // First callback — just record the timestamp and wait for the next frame.
            previousTimestamp = timestamp
            return
        }

        let elapsedMs = (timestamp - previousTimestamp) * 1_000
        previousTimestamp = timestamp

        // Filter out gaps caused by backgrounding / display-link pause.
        guard elapsedMs > 0 && elapsedMs < Self.maxValidFrameMs else { return }

        Task {
            await ScrollPerfTracer.shared.frameDidRender(elapsedMs: elapsedMs)
        }
    }
#endif
}
