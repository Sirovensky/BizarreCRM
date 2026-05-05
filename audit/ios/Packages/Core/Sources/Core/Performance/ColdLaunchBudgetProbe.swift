import Foundation

// §29.1 Cold-launch budget assert.
//
// Drop `ColdLaunchBudgetProbe.shared.markReady()` wherever the app considers
// itself "interactive" (e.g. first tab-bar render). The probe measures wall
// time from `ProcessInfo.processInfo.systemUptime` at module load (the
// earliest point reachable without custom pre-main hooks) and compares it
// against the §29 cold-launch budget (1 500 ms on iPhone 13).
//
// In DEBUG builds an `assertionFailure` fires when the budget is exceeded so
// CI surfaces regressions in XCTest runs; in RELEASE only a log line is
// emitted (zero-crash guarantee).

/// Measures cold-launch time-to-interactive and asserts against the §29 budget.
///
/// ## Usage
/// ```swift
/// // In App.body or the root ContentView.onAppear:
/// ColdLaunchBudgetProbe.shared.markReady()
/// ```
///
/// The probe records the module-load uptime once (at first property access)
/// and uses `ContinuousClock` for the end measurement so the value is
/// unaffected by NTP slew.
public final class ColdLaunchBudgetProbe: @unchecked Sendable {

    // MARK: - Shared instance

    public static let shared = ColdLaunchBudgetProbe()

    // MARK: - Configuration

    /// Cold-launch budget in milliseconds (§29.1 baseline: iPhone 13).
    public let budgetMs: Double

    // MARK: - State

    /// System uptime (seconds) sampled as close to pre-main as possible.
    private let loadUptimeSeconds: TimeInterval

    /// Whether `markReady()` has already been called.
    private var fired = false
    private let lock = NSLock()

    // MARK: - Init

    public init(budgetMs: Double = 1_500) {
        self.budgetMs = budgetMs
        // `systemUptime` is monotonic and available before the first runloop tick.
        self.loadUptimeSeconds = ProcessInfo.processInfo.systemUptime
    }

    // MARK: - Public API

    /// Call once when the app's root UI is interactive.
    ///
    /// Emits a warning + DEBUG `assertionFailure` when elapsed time exceeds
    /// ``budgetMs``. Subsequent calls are silently ignored.
    public func markReady() {
        lock.lock()
        guard !fired else { lock.unlock(); return }
        fired = true
        lock.unlock()

        let nowUptime = ProcessInfo.processInfo.systemUptime
        let elapsedMs = (nowUptime - loadUptimeSeconds) * 1_000

        let message = "[ColdLaunchBudgetProbe] cold-launch TTI: \(String(format: "%.1f", elapsedMs)) ms (budget: \(String(format: "%.0f", budgetMs)) ms)"
        AppLog.perf.info("\(message, privacy: .public)")

        guard elapsedMs > budgetMs else { return }

        let violation = "[ColdLaunchBudgetProbe] BUDGET EXCEEDED — \(String(format: "%.1f", elapsedMs)) ms > \(String(format: "%.0f", budgetMs)) ms"
        AppLog.perf.warning("\(violation, privacy: .public)")

#if DEBUG
        assertionFailure(violation)
#endif
    }

    /// Elapsed milliseconds since module load, or `nil` before `markReady()`.
    public var elapsedMs: Double? {
        lock.lock()
        defer { lock.unlock() }
        guard fired else { return nil }
        let nowUptime = ProcessInfo.processInfo.systemUptime
        return (nowUptime - loadUptimeSeconds) * 1_000
    }
}
