import Foundation
import SwiftUI

// §30.13 — ToastQueue
// Implements "ToastQueue singleton: FIFO with dedup — don't show same toast
// twice within 3s" from ActionPlan §30 line 4620.
//
// This is a presentation-layer helper: it owns the queue, dedup window, and
// publishes the currently-visible toast. Callers (typically a root overlay
// view) observe `currentToast` and render a `BrandToast` when non-nil.
//
// APPEND-ONLY — do not rename or remove this file's public surface.

// MARK: - ToastRequest

/// A toast to be presented. Equality is keyed on `kind` + `message` so the
/// dedup window can suppress identical re-fires (e.g. retry-storm).
public struct ToastRequest: Sendable, Equatable {

    public let kind: BrandToast.Kind
    public let message: String
    /// How long the toast stays visible before auto-dismissing. Defaults to
    /// the §30.13 transient toast duration of 2 seconds.
    public let duration: TimeInterval

    public init(
        kind: BrandToast.Kind = .info,
        message: String,
        duration: TimeInterval = 2.0
    ) {
        self.kind = kind
        self.message = message
        self.duration = duration
    }

    public static func == (lhs: ToastRequest, rhs: ToastRequest) -> Bool {
        lhs.kind == rhs.kind && lhs.message == rhs.message
    }
}

extension BrandToast.Kind: Equatable {}

// MARK: - ToastQueue

/// Singleton queue that drives toast presentation app-wide.
///
/// Behaviour:
/// - FIFO ordering — toasts surface in the order they were enqueued.
/// - Dedup window — identical (`kind`, `message`) requests within
///   `dedupWindow` (default 3s) are silently dropped.
/// - At most one toast visible at a time. The next dequeues automatically.
///
/// Usage:
/// ```swift
/// ToastQueue.shared.enqueue(.init(kind: .success, message: "Saved"))
///
/// // In root view:
/// .overlay(alignment: .top) {
///     if let t = ToastQueue.shared.currentToast {
///         BrandToast(kind: t.kind, message: t.message)
///             .transition(.move(edge: .top).combined(with: .opacity))
///     }
/// }
/// ```
@MainActor
public final class ToastQueue: ObservableObject {

    // MARK: Public

    public static let shared = ToastQueue()

    /// Window during which an identical request is suppressed.
    public let dedupWindow: TimeInterval = 3.0

    /// The toast currently being presented, or `nil` when the queue is idle.
    @Published public private(set) var currentToast: ToastRequest?

    // MARK: Private

    private var pending: [ToastRequest] = []
    private var recentlyShown: [(request: ToastRequest, at: Date)] = []
    private var dismissTask: Task<Void, Never>?

    // MARK: Init

    private init() {}

    // MARK: API

    /// Enqueues a toast. Returns `true` if accepted, `false` if it was
    /// suppressed by the dedup window.
    @discardableResult
    public func enqueue(_ request: ToastRequest) -> Bool {
        prune()
        if recentlyShown.contains(where: { $0.request == request }) {
            return false
        }
        if pending.contains(where: { $0 == request }) {
            return false
        }
        pending.append(request)
        recentlyShown.append((request, Date()))
        promoteIfIdle()
        return true
    }

    /// Dismisses the current toast immediately (e.g. user tapped to close).
    /// The next pending toast (if any) will surface on the following tick.
    public func dismissCurrent() {
        dismissTask?.cancel()
        dismissTask = nil
        currentToast = nil
        promoteIfIdle()
    }

    /// Drops all pending toasts. The current toast is left visible until
    /// its natural timeout. Use only on screen tear-down.
    public func clearPending() {
        pending.removeAll()
    }

    // MARK: Internals

    private func promoteIfIdle() {
        guard currentToast == nil, !pending.isEmpty else { return }
        let next = pending.removeFirst()
        currentToast = next
        let duration = next.duration
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.currentToast = nil
                self?.promoteIfIdle()
            }
        }
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-dedupWindow)
        recentlyShown.removeAll { $0.at < cutoff }
    }
}
