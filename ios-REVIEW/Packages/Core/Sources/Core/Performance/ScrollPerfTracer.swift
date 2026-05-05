import Foundation
import OSLog

// §29.2 Scroll-performance tracer.
//
// `ScrollPerfTracer` instruments individual frame intervals during list
// scrolling. Call `frameDidRender(elapsedMs:)` from the view's
// `onPreferenceChange` / `GeometryReader` update site (or a CADisplayLink
// callback). The tracer accumulates a rolling window of frame durations,
// emits per-frame signposts, and fires a `BudgetGuard` check so that CI
// notices sustained jank.
//
// Design notes:
// • Actor-isolated so concurrent frame callbacks from animation runloops are safe.
// • Rolling window is bounded (default 120 samples ≈ 2 s at 60 fps) to keep
//   memory flat.
// • `p95FrameMs` exposes the 95th-percentile frame time; consumers can compare
//   it to `PerformanceBudget.threshold(for: .listScroll60fps)`.

/// Actor-isolated scroll-frame performance tracer.
///
/// ```swift
/// // In a CADisplayLink callback or SwiftUI onPreferenceChange:
/// await ScrollPerfTracer.shared.frameDidRender(elapsedMs: frameElapsed)
///
/// // Poll p95 for a metric upload:
/// let p95 = await ScrollPerfTracer.shared.p95FrameMs
/// ```
public actor ScrollPerfTracer {

    // MARK: - Shared instance

    public static let shared = ScrollPerfTracer()

    // MARK: - Configuration

    /// Maximum frame samples retained in the rolling window.
    public let windowSize: Int

    // MARK: - State

    private var frames: [Double] = []
    private var totalFrames: Int = 0
    private var droppedFrames: Int = 0    // frames that exceeded the 60-fps budget

    private let budget: Double

    // MARK: - Init

    public init(windowSize: Int = 120) {
        precondition(windowSize > 0)
        self.windowSize = windowSize
        self.budget = PerformanceBudget.threshold(for: .listScroll60fps)
    }

    // MARK: - Public API

    /// Record a single rendered frame.
    ///
    /// - Parameter elapsedMs: Time taken to produce this frame (milliseconds).
    public func frameDidRender(elapsedMs: Double) {
        totalFrames += 1
        if elapsedMs > budget {
            droppedFrames += 1
        }

        if frames.count >= windowSize {
            frames.removeFirst()
        }
        frames.append(elapsedMs)

        AppLog.perf.debug("[ScrollPerfTracer] frame \(String(format: "%.2f", elapsedMs), privacy: .public) ms")

        // Only fire the budget guard for severe outliers (> 2× budget) to avoid
        // noisy assertions on single-frame blips caused by OS scheduling.
        if elapsedMs > budget * 2 {
            BudgetGuard.check(.listScroll60fps, elapsedMs: elapsedMs)
        }
    }

    /// 95th-percentile frame time over the current window, or `nil` if no frames recorded.
    public var p95FrameMs: Double? {
        guard !frames.isEmpty else { return nil }
        let sorted = frames.sorted()
        let idx = Int(ceil(Double(sorted.count) * 0.95)) - 1
        return sorted[max(0, min(idx, sorted.count - 1))]
    }

    /// Mean frame time over the current window, or `nil` if no frames recorded.
    public var meanFrameMs: Double? {
        guard !frames.isEmpty else { return nil }
        return frames.reduce(0, +) / Double(frames.count)
    }

    /// Total frames recorded since last reset.
    public var totalFrameCount: Int { totalFrames }

    /// Frames that exceeded the 60-fps budget since last reset.
    public var droppedFrameCount: Int { droppedFrames }

    /// Ratio of dropped frames to total, in [0, 1]. `nil` when no frames recorded.
    public var dropRate: Double? {
        guard totalFrames > 0 else { return nil }
        return Double(droppedFrames) / Double(totalFrames)
    }

    /// Reset all counters and the rolling window.
    public func reset() {
        frames.removeAll()
        totalFrames = 0
        droppedFrames = 0
    }
}
