import Foundation

// §29 Performance — MainActor hop guard.
//
// Unexpected hops to the main actor (e.g. a background task that accidentally
// propagates work to the main thread) inflate frame times and cause hitches.
// Conversely, UI work accidentally running off the main thread causes data
// races.
//
// `MainActorHopGuard` provides lightweight assertion helpers:
//
//   • `assertOnMain()`  — traps in DEBUG if NOT on the main thread.
//   • `assertOffMain()` — traps in DEBUG if ON the main thread.
//   • `hopToMain { }` — runs a closure on the main actor, logging a warning
//                        in DEBUG if a hop was required (i.e. the call site
//                        was already off-main).
//   • `ensureOffMain()` — suspends until off the main actor by dispatching to
//                         a `Task.detached` background continuation if needed.
//
// All checks are no-ops in RELEASE builds to avoid any runtime cost.

/// Guards against unexpected main-actor hops in performance-sensitive paths.
public enum MainActorHopGuard {

    // MARK: - Thread assertions

    /// Asserts that the current execution context is the main thread/actor.
    ///
    /// Fires `assertionFailure` in DEBUG if called from a background thread.
    /// No-op in RELEASE.
    /// - Parameter label: Human-readable label printed with the failure message.
    public static func assertOnMain(label: String = #function) {
        #if DEBUG
        if !Thread.isMainThread {
            assertionFailure("MainActorHopGuard: \(label) must run on the main thread, but is off-main.")
        }
        #endif
    }

    /// Asserts that the current execution context is NOT the main thread/actor.
    ///
    /// Fires `assertionFailure` in DEBUG if called from the main thread.
    /// No-op in RELEASE.
    /// - Parameter label: Human-readable label printed with the failure message.
    public static func assertOffMain(label: String = #function) {
        #if DEBUG
        if Thread.isMainThread {
            assertionFailure("MainActorHopGuard: \(label) must NOT run on the main thread, but is on-main.")
        }
        #endif
    }

    // MARK: - Hop helpers

    /// Runs `work` on the `MainActor`, logging a perf warning if a hop was
    /// necessary (i.e. the caller was not already on the main thread).
    ///
    /// - Parameters:
    ///   - label: Descriptive label for the warning message.
    ///   - work: The closure to execute on the main actor.
    public static func hopToMain(label: String = #function, work: @MainActor @escaping () -> Void) {
        #if DEBUG
        let needsHop = !Thread.isMainThread
        if needsHop {
            // Log once per unique label to avoid flooding the console.
            HopLog.shared.recordIfNew(label: label)
        }
        #endif

        Task { @MainActor in
            work()
        }
    }

    /// Ensures subsequent code runs off the main actor by yielding into a
    /// background task if the current context is main.
    ///
    /// Useful at the top of compute-heavy async functions to avoid accidental
    /// main-thread work:
    ///
    ///     func buildSearchIndex() async {
    ///         await MainActorHopGuard.ensureOffMain(label: "buildSearchIndex")
    ///         // ... heavy work ...
    ///     }
    ///
    /// - Parameter label: Label for the debug log.
    public static func ensureOffMain(label: String = #function) async {
        if await MainActor.run(resultType: Bool.self) { Thread.isMainThread } {
            #if DEBUG
            HopLog.shared.recordIfNew(label: label)
            #endif
            // Yield off main by suspending into a background continuation.
            await Task.detached(priority: .userInitiated) {}.value
        }
    }
}

// MARK: - Internal hop log

#if DEBUG
private final class HopLog: @unchecked Sendable {
    static let shared = HopLog()
    private let lock = NSLock()
    private var seen = Set<String>()

    func recordIfNew(label: String) {
        lock.lock()
        let isNew = seen.insert(label).inserted
        lock.unlock()
        if isNew {
            print("[MainActorHopGuard] ⚠️ unexpected main-actor hop at: \(label)")
        }
    }
}
#endif
