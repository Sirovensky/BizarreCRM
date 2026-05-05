import Foundation
import Core

// MARK: - §21.3 Silent push coalescing
//
// When many silent pushes arrive in a short window (e.g. a bulk status-change),
// we debounce them into a single sync call.  This prevents hammering the server
// with N parallel `syncNow()` calls that would all fetch identical data.
//
// Algorithm:
//  - Each incoming silent push sets/resets a debounce timer.
//  - The timer fires after `debounceInterval` (default 2 s).
//  - A single `syncNow()` is issued when the timer fires; intermediate arrivals
//    extend the window.
//  - High-water: if the backlog reaches `maxCoalesceCount`, fire immediately.

/// Actor-isolated coalescer that batches rapid-fire silent pushes into a single
/// sync callback.
public actor SilentPushCoalescer {

    // MARK: - Types

    /// Called when the debounce fires and at least one push is pending.
    /// Receives the count of coalesced pushes since last fire.
    public typealias FireHandler = @Sendable (Int) async -> Void

    // MARK: - Constants

    public static let defaultDebounceInterval: TimeInterval = 2.0
    public static let defaultMaxCoalesceCount: Int = 10

    // MARK: - State

    private let debounceInterval: TimeInterval
    private let maxCoalesceCount: Int
    private let fireHandler: FireHandler

    private var pendingCount: Int = 0
    private var debounceTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        debounceInterval: TimeInterval = defaultDebounceInterval,
        maxCoalesceCount: Int = defaultMaxCoalesceCount,
        fireHandler: @escaping FireHandler
    ) {
        self.debounceInterval = debounceInterval
        self.maxCoalesceCount = maxCoalesceCount
        self.fireHandler = fireHandler
    }

    // MARK: - Public API

    /// Register the arrival of a silent push.
    /// Will either reset the debounce window or fire immediately if the
    /// backlog has reached `maxCoalesceCount`.
    public func arrive() {
        pendingCount += 1
        AppLog.sync.debug("SilentPushCoalescer: pending=\(self.pendingCount)")

        if pendingCount >= maxCoalesceCount {
            // High-water hit — fire immediately.
            AppLog.sync.info("SilentPushCoalescer: high-water hit at \(self.pendingCount), firing now")
            fireDirect()
            return
        }

        // Reset / extend debounce window.
        debounceTask?.cancel()
        let interval = debounceInterval
        let handler = fireHandler
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                // Cancelled — another arrive() or high-water fire supersedes.
                return
            }
            await self?.fireDirect()
        }
    }

    // MARK: - Private

    private func fireDirect() {
        let count = pendingCount
        guard count > 0 else { return }
        pendingCount = 0
        debounceTask?.cancel()
        debounceTask = nil
        AppLog.sync.info("SilentPushCoalescer: firing sync for \(count) coalesced push(es)")
        let handler = fireHandler
        Task { await handler(count) }
    }
}
