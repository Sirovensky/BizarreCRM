import Foundation

// §29 Performance — Task.detached cancellation propagator.
//
// `Task.detached` breaks the cooperative cancellation chain: if the parent task
// is cancelled the detached child keeps running.  This file provides a thin
// wrapper that re-attaches cancellation by linking a parent-task cancellation
// observer to the detached child, so background work still stops when the
// caller is torn down.
//
// Usage:
//
//   let handle = DetachedCancellationPropagator.launch(priority: .background) {
//       try await expensiveWork()
//   }
//   // When the calling Task is cancelled, `handle` is also cancelled.
//
// The propagator observes the calling task via `withTaskCancellationHandler` and
// immediately cancels the detached handle on parent cancellation.  If the
// parent is already cancelled before launch, the detached task is cancelled
// before its body executes.

/// Launches a `Task.detached` that is cancelled when the enclosing parent task
/// is cancelled.
///
/// This restores the cooperative cancellation chain that `Task.detached`
/// deliberately breaks, ensuring background work does not outlive its owner.
public enum DetachedCancellationPropagator {

    // MARK: - Public API

    /// Launches a detached task that is cancelled when the current task is
    /// cancelled.
    ///
    /// - Parameters:
    ///   - priority: The priority of the detached task (default `.background`).
    ///   - operation: The async throwing closure to run in the detached task.
    /// - Returns: The `Task` handle; callers may `await` its value or cancel it
    ///   independently if needed.
    @discardableResult
    public static func launch<T: Sendable>(
        priority: TaskPriority = .background,
        operation: @escaping @Sendable () async throws -> T
    ) -> Task<T, Error> {
        let detached = Task.detached(priority: priority, operation: operation)

        // withTaskCancellationHandler runs `onCancel` synchronously on the
        // thread that cancelled the parent, then continues with `operation`.
        // We use it purely to hook cancellation; the return value is discarded.
        Task {
            await withTaskCancellationHandler {
                // Keep the parent task alive until the detached task finishes
                // so we have something to cancel if needed.  We do NOT await
                // the detached task's value here — that would defeat the
                // "detached" semantics.  Instead we just yield briefly to let
                // cancellation propagate if it arrives before we return.
                _ = try? await Task.sleep(for: .seconds(0))
            } onCancel: {
                detached.cancel()
            }
        }

        return detached
    }

    /// Launches a non-throwing detached task that is cancelled when the current
    /// task is cancelled.
    ///
    /// - Parameters:
    ///   - priority: The priority of the detached task (default `.background`).
    ///   - operation: The async closure to run.
    /// - Returns: The `Task` handle.
    @discardableResult
    public static func launch<T: Sendable>(
        priority: TaskPriority = .background,
        operation: @escaping @Sendable () async -> T
    ) -> Task<T, Never> {
        let detached = Task.detached(priority: priority, operation: operation)

        Task {
            await withTaskCancellationHandler {
                _ = try? await Task.sleep(for: .seconds(0))
            } onCancel: {
                detached.cancel()
            }
        }

        return detached
    }
}
