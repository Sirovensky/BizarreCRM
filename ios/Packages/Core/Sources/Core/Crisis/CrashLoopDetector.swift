import Foundation

// §34 Crisis Recovery helpers — CrashLoopDetector
// Detects 3+ unexpected exits in 5 minutes and triggers SafeMode.

/// Detects rapid unexpected-exit loops and triggers `SafeMode` automatically.
///
/// **Algorithm**: on each cold start, record a timestamp in a persisted ring buffer.
/// Count how many of the stored timestamps fall within the last `windowSeconds`
/// seconds. If the count reaches `threshold`, declare a crash loop.
///
/// Call `recordLaunch()` early in app startup — before any heavyweight work —
/// and then call `evaluateAndTriggerIfNeeded(safeMode:)` to flip `SafeMode` when
/// a loop is detected.
///
/// **Design choices**
/// - `windowSeconds` defaults to 300 (5 minutes).
/// - `threshold` defaults to 3 (≥ 3 exits in window → loop).
/// - The buffer stores raw `TimeInterval` values encoded as JSON to avoid
///   any Codable dependency on a custom type.
public final class CrashLoopDetector: Sendable {

    // MARK: — Singleton

    public static let shared = CrashLoopDetector()

    // MARK: — Configuration

    /// Number of seconds in the sliding window. Default: 300 (5 min).
    public let windowSeconds: TimeInterval

    /// Minimum launch count within the window to declare a loop. Default: 3.
    public let threshold: Int

    // MARK: — Storage

    private let defaults: UserDefaults
    private static let bufferKey = "com.bizarrecrm.crisis.launchTimestamps"

    // MARK: — Init

    public init(
        defaults: UserDefaults = .standard,
        windowSeconds: TimeInterval = 300,
        threshold: Int = 3
    ) {
        self.defaults = defaults
        self.windowSeconds = windowSeconds
        self.threshold = threshold
    }

    // MARK: — Public API

    /// Record the current launch timestamp.
    ///
    /// Must be called once per cold start, as early as possible (before any code
    /// that could itself crash). Timestamps older than `windowSeconds` are pruned
    /// to keep storage minimal.
    public func recordLaunch(at now: Date = Date()) {
        var timestamps = storedTimestamps()
        timestamps.append(now.timeIntervalSince1970)
        // Prune stale entries immediately to keep storage small
        let cutoff = now.timeIntervalSince1970 - windowSeconds
        timestamps = timestamps.filter { $0 > cutoff }
        persist(timestamps)
    }

    /// `true` if the launch history within the current window meets or exceeds
    /// `threshold`, indicating a crash loop.
    public func isLooping(at now: Date = Date()) -> Bool {
        let cutoff = now.timeIntervalSince1970 - windowSeconds
        let recent = storedTimestamps().filter { $0 > cutoff }
        return recent.count >= threshold
    }

    /// Evaluate the crash-loop condition and activate `SafeMode` if triggered.
    ///
    /// - Parameters:
    ///   - safeMode: The `SafeMode` instance to activate (injectable for tests).
    ///   - now: Current time (injectable for tests).
    @MainActor
    public func evaluateAndTriggerIfNeeded(
        safeMode: SafeMode = .shared,
        at now: Date = Date()
    ) {
        guard isLooping(at: now) else { return }
        safeMode.activate(reason: .crashLoop)
        AppLog.app.error("CrashLoopDetector: crash loop detected — SafeMode activated")
    }

    /// Clear the stored launch history (e.g. after a clean update install).
    public func reset() {
        defaults.removeObject(forKey: Self.bufferKey)
    }

    /// Number of launches recorded within the current window.
    public func recentLaunchCount(at now: Date = Date()) -> Int {
        let cutoff = now.timeIntervalSince1970 - windowSeconds
        return storedTimestamps().filter { $0 > cutoff }.count
    }

    // MARK: — Private helpers

    private func storedTimestamps() -> [TimeInterval] {
        guard let data = defaults.data(forKey: Self.bufferKey),
              let decoded = try? JSONDecoder().decode([TimeInterval].self, from: data) else {
            return []
        }
        return decoded
    }

    private func persist(_ timestamps: [TimeInterval]) {
        guard let data = try? JSONEncoder().encode(timestamps) else { return }
        defaults.set(data, forKey: Self.bufferKey)
    }
}
