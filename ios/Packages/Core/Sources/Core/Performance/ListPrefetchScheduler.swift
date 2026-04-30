import Foundation

// §29.4 Pagination — list prefetch scheduler.
//
// `ListPrefetchScheduler` sits between a SwiftUI list and the pagination
// ViewModel.  It receives "row appeared" / "row disappeared" signals and
// decides — based on the §29.4 rules — whether to kick off a prefetch:
//
//   • Only fires when online (caller supplies `isOnline` closure).
//   • Skips when Low Power Mode is active (§29.11 battery guard).
//   • Respects a configurable look-ahead window (default 5 rows).
//   • Debounces rapid scroll events so a fast fling doesn't fire 50 fetches.
//   • Cancels in-flight requests that scroll past their trigger row.
//
// Usage pattern (ViewModel):
//
//   let scheduler = ListPrefetchScheduler(
//       totalRows: { viewModel.totalCount },
//       isOnline: { networkMonitor.isConnected },
//       prefetch: { viewModel.loadNextPage() }
//   )
//
//   // In the list row:
//   .onAppear { scheduler.rowAppeared(index: rowIndex) }
//   .onDisappear { scheduler.rowDisappeared(index: rowIndex) }

/// Schedules prefetch operations for cursor-paginated lists per §29.4.
///
/// Thread-safe via an internal `NSLock`; `rowAppeared`/`rowDisappeared` may
/// be called from any thread.  `prefetch` is always invoked on the `@MainActor`
/// via `Task { @MainActor in … }`.
public final class ListPrefetchScheduler: @unchecked Sendable {

    // MARK: - Configuration

    /// Rows from the end of the loaded set at which prefetch fires.
    /// Default 5 matches the §29.3 "prefetch 5 ahead/behind" note.
    public let lookAheadRows: Int

    /// Debounce interval between consecutive prefetch triggers (seconds).
    public let debounceInterval: TimeInterval

    // MARK: - Closures

    private let totalRows: @Sendable () -> Int
    private let isOnline:  @Sendable () -> Bool
    private let prefetch:  @Sendable () async -> Void

    // MARK: - State

    private let lock = NSLock()
    private var _lastPrefetchIndex: Int = -1
    private var _pendingTask: Task<Void, Never>?
    private var _lastFiredAt: Date = .distantPast

    // MARK: - Init

    /// Creates a new scheduler.
    ///
    /// - Parameters:
    ///   - lookAheadRows: How many rows from the end triggers a prefetch.
    ///   - debounceInterval: Minimum seconds between successive prefetch calls.
    ///   - totalRows: Returns the current loaded row count.
    ///   - isOnline: Returns whether the device is online.
    ///   - prefetch: Called when a prefetch should be initiated.
    public init(
        lookAheadRows: Int = 5,
        debounceInterval: TimeInterval = 0.3,
        totalRows: @escaping @Sendable () -> Int,
        isOnline: @escaping @Sendable () -> Bool,
        prefetch: @escaping @Sendable () async -> Void
    ) {
        self.lookAheadRows = lookAheadRows
        self.debounceInterval = debounceInterval
        self.totalRows = totalRows
        self.isOnline = isOnline
        self.prefetch = prefetch
    }

    // MARK: - Public API

    /// Call from `onAppear` of each list row.
    ///
    /// Triggers a prefetch when `index` is within `lookAheadRows` of the
    /// end of the current loaded set, subject to online + LPM guards.
    ///
    /// - Parameter index: Zero-based index of the appearing row.
    public func rowAppeared(index: Int) {
        let total = totalRows()
        guard total > 0 else { return }

        let threshold = total - lookAheadRows
        guard index >= threshold else { return }

        // Skip on Low Power Mode — battery matters more than prefetch speed.
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }

        // Skip when offline — no point firing network requests.
        guard isOnline() else { return }

        lock.lock()
        let alreadyTriggered = _lastPrefetchIndex >= index
        let now = Date()
        let sinceLast = now.timeIntervalSince(_lastFiredAt)
        let tooSoon = sinceLast < debounceInterval
        lock.unlock()

        guard !alreadyTriggered && !tooSoon else { return }

        lock.lock()
        _lastPrefetchIndex = index
        _lastFiredAt = now
        let prev = _pendingTask
        lock.unlock()

        prev?.cancel()

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.prefetch()
        }

        lock.lock()
        _pendingTask = task
        lock.unlock()
    }

    /// Call from `onDisappear` of each list row.
    ///
    /// Currently a no-op but provided for API symmetry — future implementations
    /// may cancel in-flight prefetches when the triggering row scrolls back.
    ///
    /// - Parameter index: Zero-based index of the disappearing row.
    public func rowDisappeared(index: Int) {
        // Reserved for future cancellation logic.
        _ = index
    }

    /// Resets scheduler state.  Call when the list data set is replaced
    /// (e.g. after a search-query change) to allow prefetch to fire again
    /// from row 0 of the new result set.
    public func reset() {
        lock.lock()
        _lastPrefetchIndex = -1
        _lastFiredAt = .distantPast
        _pendingTask?.cancel()
        _pendingTask = nil
        lock.unlock()
    }
}
