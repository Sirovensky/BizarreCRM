import Foundation

// §29.7 Networking — request coalescing (dedupe concurrent same-URL requests).
//
// `SyncCoalescer` prevents the networking layer from firing multiple
// simultaneous requests for the same resource.  When a second call arrives
// while a first is already in-flight, the coalescer returns the same
// `Task<Data, Error>` rather than creating a new URLSession task.
//
// This directly implements the §29.7 open item:
//   "Request coalescing — dedupe concurrent same-URL requests."
//
// The implementation is generic over the `Resource` type so it can coalesce
// any async operation keyed on `String` (typically a URL's `absoluteString`
// or a composite `entity:id` key for repo fetches).
//
// Thread-safety:
//   All mutable state is protected by an `NSLock`.  The closure body is called
//   outside the lock to avoid potential deadlocks.
//
// Usage:
//
//   private let coalescer = SyncCoalescer<Data>()
//
//   func fetchAvatar(url: URL) async throws -> Data {
//       try await coalescer.execute(key: url.absoluteString) {
//           try await apiClient.rawGet(url: url)
//       }
//   }
//
// Multiple concurrent callers for the same key share one in-flight task.
// When it completes all waiters receive the same result (or throw the same
// error).  The key is evicted from the active map as soon as the task ends.

/// Coalesces concurrent async operations sharing the same key.
///
/// Useful for deduplicating network requests fired by rapid UI updates (e.g.
/// multiple cells requesting the same avatar URL within the same scroll event).
public final class SyncCoalescer<Resource: Sendable>: Sendable {

    // MARK: - State

    private let lock = NSLock()

    // The boxed task is stored as `AnyObject` to work around Sendable
    // constraints on `Task<Resource, Error>` in a Sendable class.
    // We re-cast on retrieval.
    private var _inflight: [String: Task<Resource, Error>] = [:]

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Executes `work` if no in-flight task exists for `key`; otherwise waits
    /// for the existing task and returns its result.
    ///
    /// Multiple concurrent callers with the same `key` will all await the same
    /// `Task`.  Separate successive calls (after the first completes) each run
    /// their own `work` closure.
    ///
    /// - Parameters:
    ///   - key: Deduplication key (e.g. URL string, "entity:id").
    ///   - work: The async throwing closure to coalesce.
    /// - Returns: The result of `work`.
    /// - Throws: Any error thrown by `work`, forwarded to all waiters.
    @discardableResult
    public func execute(key: String, work: @escaping @Sendable () async throws -> Resource) async throws -> Resource {
        lock.lock()
        if let existing = _inflight[key] {
            lock.unlock()
            return try await existing.value
        }

        let task = Task<Resource, Error> {
            try await work()
        }
        _inflight[key] = task
        lock.unlock()

        defer {
            lock.lock()
            // Only evict if this is still the same task (concurrent reset
            // might have already replaced it).
            if _inflight[key] === task {
                _inflight.removeValue(forKey: key)
            }
            lock.unlock()
        }

        return try await task.value
    }

    /// Cancels the in-flight task for `key`, if any.
    ///
    /// All awaiters on the cancelled task will receive a `CancellationError`.
    ///
    /// - Parameter key: Deduplication key to cancel.
    public func cancel(key: String) {
        lock.lock()
        let task = _inflight.removeValue(forKey: key)
        lock.unlock()
        task?.cancel()
    }

    /// Cancels all in-flight tasks.
    ///
    /// Call on session logout or scene termination to prevent orphaned tasks.
    public func cancelAll() {
        lock.lock()
        let tasks = _inflight.values
        _inflight.removeAll(keepingCapacity: true)
        lock.unlock()
        tasks.forEach { $0.cancel() }
    }

    /// Returns the number of currently in-flight coalesced operations.
    ///
    /// Useful for diagnostics and unit tests.
    public var inflightCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _inflight.count
    }
}
