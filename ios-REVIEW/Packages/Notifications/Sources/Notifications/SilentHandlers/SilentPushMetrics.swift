import Foundation
import Core

// MARK: - SilentPushMetrics

/// Actor-isolated metrics collector for silent push processing.
///
/// Tracks:
/// - **Hit rate** — received vs. processed (i.e., not duplicate, not expired).
/// - **Processing time** — per-kind latency via `startTimer` / `stopTimer`.
/// - **Kind distribution** — count per payload kind.
///
/// If §32 `TelemetryBuffer` is injected at bootstrap, metrics are flushed there
/// as `TelemetryRecord` events when `flush()` is called (e.g., on app background).
/// Without a buffer the metrics are logged via `AppLog.perf` only.
///
/// ## Usage
/// ```swift
/// let token = await SilentPushMetrics.shared.startTimer(kind: "ticket")
/// // ... process push ...
/// await SilentPushMetrics.shared.stopTimer(token, kind: "ticket")
/// await SilentPushMetrics.shared.recordReceived(kind: "ticket")
/// await SilentPushMetrics.shared.recordProcessed(kind: "ticket")
/// // On scene background:
/// await SilentPushMetrics.shared.flush()
/// ```
public actor SilentPushMetrics {

    // MARK: - Shared

    public static let shared = SilentPushMetrics()

    // MARK: - Types

    /// Opaque token returned by `startTimer`; passed back to `stopTimer`.
    public struct TimerToken: Sendable {
        fileprivate let id: UUID
        fileprivate let startedAt: Date
    }

    // MARK: - State

    private var receivedCount:  Int = 0
    private var processedCount: Int = 0
    private var duplicateCount: Int = 0
    private var expiredCount:   Int = 0

    /// Per-kind received count.
    private var receivedByKind: [String: Int] = [:]

    /// Per-kind total processing time (seconds) accumulated over completed timers.
    private var totalDurationByKind: [String: Double] = [:]
    /// Per-kind sample count (denominator for mean latency).
    private var sampleCountByKind:   [String: Int]    = [:]

    /// Active (un-stopped) timers keyed by token UUID.
    private var activeTimers: [UUID: TimerToken] = [:]

    /// Optional §32 telemetry buffer. Injected once at DI bootstrap.
    private var telemetryBuffer: TelemetryBuffer?

    // MARK: - Init

    public init() {}

    // MARK: - DI

    /// Inject a `TelemetryBuffer` so metrics are forwarded on `flush()`.
    /// Call once at app startup.
    public func setTelemetryBuffer(_ buffer: TelemetryBuffer) {
        telemetryBuffer = buffer
    }

    // MARK: - Recording

    /// Record that a silent push was received (before dedup / expiry checks).
    public func recordReceived(kind: String) {
        receivedCount += 1
        receivedByKind[kind, default: 0] += 1
    }

    /// Record that a push was actually processed (passed dedup + expiry).
    public func recordProcessed(kind: String) {
        processedCount += 1
    }

    /// Record that a push was dropped because it was a duplicate.
    public func recordDuplicate(kind: String) {
        duplicateCount += 1
    }

    /// Record that a push was dropped because it was expired.
    public func recordExpired(kind: String) {
        expiredCount += 1
    }

    // MARK: - Timers

    /// Begin timing the processing of a push with the given `kind`.
    /// Returns a token that must be passed to `stopTimer`.
    public func startTimer(kind: String) -> TimerToken {
        let token = TimerToken(id: UUID(), startedAt: Date())
        activeTimers[token.id] = token
        return token
    }

    /// Finish a timer started with `startTimer`. Records elapsed duration.
    public func stopTimer(_ token: TimerToken, kind: String) {
        guard activeTimers.removeValue(forKey: token.id) != nil else { return }
        let elapsed = Date().timeIntervalSince(token.startedAt)
        totalDurationByKind[kind, default: 0] += elapsed
        sampleCountByKind[kind, default: 0]   += 1

        AppLog.perf.debug(
            "SilentPushMetrics: kind=\(kind, privacy: .public) took \(String(format: "%.3f", elapsed))s"
        )
    }

    // MARK: - Accessors (for tests / dashboard)

    /// Total pushes received since last `reset()`.
    public var totalReceived: Int { receivedCount }

    /// Total pushes processed (not duplicate, not expired).
    public var totalProcessed: Int { processedCount }

    /// Total pushes dropped as duplicates.
    public var totalDuplicates: Int { duplicateCount }

    /// Total pushes dropped as expired.
    public var totalExpired: Int { expiredCount }

    /// Hit rate: `processed / received`. Returns 0 when `received == 0`.
    public var hitRate: Double {
        guard receivedCount > 0 else { return 0 }
        return Double(processedCount) / Double(receivedCount)
    }

    /// Mean processing duration (seconds) for a given kind.
    public func meanDuration(for kind: String) -> Double? {
        guard let total = totalDurationByKind[kind],
              let count = sampleCountByKind[kind],
              count > 0
        else { return nil }
        return total / Double(count)
    }

    /// Snapshot of received counts per kind.
    public var receivedByKindSnapshot: [String: Int] { receivedByKind }

    // MARK: - Flush

    /// Emit accumulated metrics as `TelemetryRecord` events, then reset counters.
    ///
    /// Call on `scenePhase == .background` or when the app is about to terminate.
    public func flush() async {
        guard receivedCount > 0 else { return }

        let record = TelemetryRecord(
            category: .sync,
            name: "silent_push.metrics",
            properties: [
                "received":   String(receivedCount),
                "processed":  String(processedCount),
                "duplicates": String(duplicateCount),
                "expired":    String(expiredCount),
                "hit_rate":   String(format: "%.4f", hitRate)
            ]
        )

        AppLog.perf.info(
            "SilentPushMetrics flush: received=\(self.receivedCount) processed=\(self.processedCount) hitRate=\(String(format: "%.2f", self.hitRate * 100))%"
        )

        if let buffer = telemetryBuffer {
            await buffer.enqueue(record)

            // Emit per-kind duration records.
            for (kind, total) in totalDurationByKind {
                let samples = sampleCountByKind[kind] ?? 0
                let mean = samples > 0 ? total / Double(samples) : 0
                let durationRecord = TelemetryRecord(
                    category: .performance,
                    name: "silent_push.duration",
                    properties: [
                        "kind":    kind,
                        "samples": String(samples),
                        "mean_s":  String(format: "%.4f", mean)
                    ]
                )
                await buffer.enqueue(durationRecord)
            }
        }

        reset()
    }

    // MARK: - Reset

    /// Clear all counters (does not flush pending data).
    public func reset() {
        receivedCount       = 0
        processedCount      = 0
        duplicateCount      = 0
        expiredCount        = 0
        receivedByKind      = [:]
        totalDurationByKind = [:]
        sampleCountByKind   = [:]
        activeTimers        = [:]
    }
}
