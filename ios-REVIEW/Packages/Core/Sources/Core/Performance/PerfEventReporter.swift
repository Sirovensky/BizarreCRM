import Foundation

// §29 Performance instrumentation — rolling-window aggregator.
//
// `PerfEventReporter` collects raw elapsed-ms samples in a fixed-capacity
// rolling window and exposes aggregate statistics (count, min, max, mean,
// p95) for each operation. The data is intended to be consumed by a future
// Instruments or analytics integration.

/// A thread-safe `actor` that aggregates performance measurements over a
/// configurable rolling window.
///
/// ```swift
/// await PerfEventReporter.shared.record(.launchTTI, elapsedMs: 540)
/// let metrics = await PerfEventReporter.shared.aggregated(for: .launchTTI)
/// ```
public actor PerfEventReporter {

    // MARK: - Types

    /// Aggregate statistics for a single operation over the current window.
    public struct AggregatedMetrics: Sendable, Equatable {
        /// Number of samples in the window.
        public let count: Int
        /// Minimum elapsed time (ms).
        public let min: Double
        /// Maximum elapsed time (ms).
        public let max: Double
        /// Arithmetic mean of elapsed times (ms).
        public let mean: Double
        /// 95th-percentile elapsed time (ms).
        public let p95: Double

        /// A convenient zero-value sentinel meaning "no data".
        public static let empty = AggregatedMetrics(count: 0, min: 0, max: 0, mean: 0, p95: 0)
    }

    // MARK: - Shared instance

    /// Shared application-wide reporter.
    public static let shared = PerfEventReporter()

    // MARK: - Configuration

    /// Maximum number of raw samples retained per operation.
    ///
    /// When the window is full the oldest sample is evicted (FIFO).
    public let windowSize: Int

    // MARK: - Storage

    /// Raw samples, keyed by operation.
    private var samples: [PerformanceOperation: [Double]] = [:]

    // MARK: - Lifecycle

    /// Creates a new reporter.
    ///
    /// - Parameter windowSize: Maximum samples per operation (default: 200).
    public init(windowSize: Int = 200) {
        precondition(windowSize > 0, "windowSize must be positive")
        self.windowSize = windowSize
    }

    // MARK: - Public API

    /// Records a single raw elapsed-time sample for `operation`.
    ///
    /// If the window is full the oldest sample is dropped before the new
    /// one is appended, keeping memory bounded.
    ///
    /// - Parameters:
    ///   - operation: The operation that was measured.
    ///   - elapsedMs: Elapsed time in milliseconds.
    public func record(_ operation: PerformanceOperation, elapsedMs: Double) {
        var window = samples[operation, default: []]
        if window.count >= windowSize {
            window.removeFirst()
        }
        window.append(elapsedMs)
        samples[operation] = window
    }

    /// Returns aggregated statistics for `operation`.
    ///
    /// Returns ``AggregatedMetrics/empty`` if no samples have been recorded.
    ///
    /// - Parameter operation: The operation to query.
    public func aggregated(for operation: PerformanceOperation) -> AggregatedMetrics {
        guard let window = samples[operation], !window.isEmpty else {
            return .empty
        }
        return Self.aggregate(window)
    }

    /// Returns a snapshot dictionary of all aggregated metrics.
    ///
    /// Useful for periodic export to analytics or Instruments.
    public func allAggregated() -> [PerformanceOperation: AggregatedMetrics] {
        var result: [PerformanceOperation: AggregatedMetrics] = [:]
        for (op, window) in samples where !window.isEmpty {
            result[op] = Self.aggregate(window)
        }
        return result
    }

    /// Clears all recorded samples. Useful in tests.
    public func reset() {
        samples.removeAll()
    }

    // MARK: - Private helpers

    private static func aggregate(_ window: [Double]) -> AggregatedMetrics {
        let sorted = window.sorted()
        let count = sorted.count
        let min = sorted.first ?? 0
        let max = sorted.last ?? 0
        let mean = sorted.reduce(0, +) / Double(count)
        let p95Index = Int(ceil(Double(count) * 0.95)) - 1
        let p95 = sorted[Swift.max(0, Swift.min(p95Index, count - 1))]
        return AggregatedMetrics(count: count, min: min, max: max, mean: mean, p95: p95)
    }
}
