import Foundation

// §29 Performance — Throttled debouncer.
//
// Pure debounce delays every event until a quiet period elapses — costly for
// frequent live-search keystrokes because the user waits even when typing
// slowly.  Pure throttle fires immediately but may fire many times during a
// burst.
//
// `ThrottledDebouncer` combines both strategies:
//   1. The first event in a burst fires immediately (throttle leading edge).
//   2. Subsequent events within the throttle window are suppressed.
//   3. The last event in a burst fires after the debounce window (trailing
//      edge debounce) so no final value is lost.
//
// This is ideal for:
//   • Live search — first keystroke triggers instantly; mid-burst suppressed;
//     final value always sent.
//   • Scroll callbacks driving prefetch — immediate response on scroll start,
//     trailing update when scroll settles.
//   • Save-on-change — immediate write + final reconciliation.
//
// Thread-safety: all mutable state behind `NSLock`; callbacks dispatched on
// the actor/queue provided at init (default: `@MainActor`).
//
// Usage:
//
//   private let debouncer = ThrottledDebouncer(
//       throttle: .milliseconds(300),
//       debounce: .milliseconds(500)
//   )
//
//   func searchTextChanged(_ text: String) {
//       debouncer.send(text) { [weak self] value in
//           await self?.runSearch(query: value)
//       }
//   }

/// Combines leading-edge throttle with trailing-edge debounce.
///
/// The first event fires immediately; subsequent events within `throttleWindow`
/// are suppressed; the last event always fires after `debounceWindow` of quiet.
public final class ThrottledDebouncer<Value: Sendable>: @unchecked Sendable {

    // MARK: - Configuration

    /// Window within which only the leading edge fires.
    public let throttleWindow: Duration

    /// Quiet period after which the trailing value fires.
    public let debounceWindow: Duration

    // MARK: - State

    private let lock = NSLock()
    private var lastFireTime: ContinuousClock.Instant?
    private var pendingValue: Value?
    private var debounceTask: Task<Void, Never>?

    // MARK: - Init

    /// Creates a `ThrottledDebouncer`.
    ///
    /// - Parameters:
    ///   - throttle: Leading-edge throttle window.  Events within this window
    ///     after the last fire are suppressed.
    ///   - debounce: Trailing-edge debounce window.  After the last event,
    ///     waits this long before firing the final value.
    public init(throttle: Duration, debounce: Duration) {
        self.throttleWindow = throttle
        self.debounceWindow = debounce
    }

    // MARK: - Public API

    /// Submits a new value.
    ///
    /// - If the throttle window has expired since the last fire, `handler` is
    ///   called immediately with `value`.
    /// - Otherwise the value is held as pending.  The debounce timer is reset.
    ///   `handler` will be called after `debounceWindow` of inactivity.
    ///
    /// - Parameters:
    ///   - value: The value to deliver.
    ///   - handler: `@Sendable` async closure called on the `@MainActor`.
    public func send(_ value: Value, handler: @escaping @MainActor @Sendable (Value) async -> Void) {
        lock.lock()

        let now = ContinuousClock.now
        let sinceLastFire = lastFireTime.map { now - $0 } ?? throttleWindow

        // Cancel any pending debounce task.
        let oldTask = debounceTask
        debounceTask = nil

        if sinceLastFire >= throttleWindow {
            // Leading edge: fire immediately.
            lastFireTime = now
            pendingValue = nil
            lock.unlock()

            oldTask?.cancel()

            Task { @MainActor in
                await handler(value)
            }
        } else {
            // Within throttle window: hold value, schedule debounce.
            pendingValue = value
            lock.unlock()

            oldTask?.cancel()

            let newTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await Task.sleep(for: self.debounceWindow)
                } catch {
                    return // Cancelled — newer event will handle.
                }

                if let toFire = self.takePendingValueForDebounce() {
                    await handler(toFire)
                }
            }

            lock.lock()
            debounceTask = newTask
            lock.unlock()
        }
    }

    /// Cancels any pending debounce without firing.
    ///
    /// Call when the owning view disappears or the session resets to prevent
    /// stale callbacks.
    public func cancel() {
        lock.lock()
        let task = debounceTask
        debounceTask = nil
        pendingValue = nil
        lock.unlock()
        task?.cancel()
    }

    private func takePendingValueForDebounce() -> Value? {
        lock.lock()
        defer { lock.unlock() }

        let toFire = pendingValue
        pendingValue = nil
        lastFireTime = ContinuousClock.now
        debounceTask = nil
        return toFire
    }
}
