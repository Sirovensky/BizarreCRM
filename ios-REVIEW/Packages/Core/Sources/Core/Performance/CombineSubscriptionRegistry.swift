import Combine
import Foundation

// §29 Performance — Combine subscription registry.
//
// Storing `AnyCancellable` objects correctly is easy to get wrong:
//   • Storing in a `var bag = Set<AnyCancellable>()` inside a class works,
//     but leaks if the class is retained past its useful life.
//   • Storing on a view model that outlives its view causes phantom updates.
//
// `CombineSubscriptionRegistry` is an `@Observable`-compatible reference type
// that owns a set of `AnyCancellable` tokens and cancels them all when
// deallocated or when `cancelAll()` is called explicitly (e.g. on logout).
//
// It also exposes a thread-safe `store(in:)` target so subscriptions can be
// added from any queue.
//
// Usage:
//
//   @Observable
//   final class TicketListViewModel {
//       private let subs = CombineSubscriptionRegistry()
//
//       func bind() {
//           networkMonitor.isConnectedPublisher
//               .sink { [weak self] isOn in self?.handleConnectivity(isOn) }
//               .store(in: subs)
//       }
//
//       deinit { /* subs cancelled automatically */ }
//   }

/// Thread-safe container for `AnyCancellable` Combine subscriptions.
///
/// All stored subscriptions are cancelled when the registry is deallocated or
/// when `cancelAll()` is called explicitly.
public final class CombineSubscriptionRegistry: @unchecked Sendable {

    // MARK: - State

    private let lock = NSLock()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    public init() {}

    deinit {
        _cancelAll()
    }

    // MARK: - Public API

    /// Stores `cancellable` in the registry.
    ///
    /// The subscription lives until the registry is deallocated, `cancelAll()`
    /// is called, or the upstream publisher completes.
    /// - Parameter cancellable: The token returned by `.sink` / `.assign`.
    public func store(_ cancellable: AnyCancellable) {
        lock.lock()
        cancellables.insert(cancellable)
        lock.unlock()
    }

    /// Cancels and removes all stored subscriptions.
    ///
    /// Safe to call from any thread or queue.  After this returns the registry
    /// is empty and ready to accept new subscriptions.
    public func cancelAll() {
        lock.lock()
        _cancelAll()
        lock.unlock()
    }

    /// Returns the number of active subscriptions.
    ///
    /// Useful for unit tests and diagnostics.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return cancellables.count
    }

    // MARK: - Private helpers

    private func _cancelAll() {
        let toCancel = cancellables
        cancellables.removeAll(keepingCapacity: true)
        // Cancellation happens outside the lock to avoid reentrant deadlocks
        // if a cancellable's deinit fires another subscription.
        lock.unlock()
        toCancel.forEach { $0.cancel() }
        lock.lock()
    }
}

// MARK: - AnyCancellable convenience

public extension AnyCancellable {
    /// Stores this cancellable in a `CombineSubscriptionRegistry`.
    ///
    ///     publisher.sink { … }.store(in: registry)
    func store(in registry: CombineSubscriptionRegistry) {
        registry.store(self)
    }
}
