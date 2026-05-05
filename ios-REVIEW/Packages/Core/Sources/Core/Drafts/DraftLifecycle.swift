import Foundation

// §20 Draft Recovery — DraftLifecycle
// Expiration rules and autosave timing constants.
//
// All values are centralised here so that callers never embed magic numbers.
// Feature owners should reference these constants rather than hard-coding
// durations, making future tuning a one-line change.

/// Centralised lifecycle policy for the Draft Recovery framework.
///
/// ### Expiration
/// Drafts older than `defaultExpirationInterval` are eligible for pruning.
/// Call `UserDefaultsDraftStore.prune(olderThan:)` on app foreground to
/// enforce the policy without impacting cold-start latency.
///
/// ### Autosave
/// The `autosaveInterval` (3 seconds) is intended for a "dirty timer" pattern:
/// start a timer when the user first edits a field; on each tick, if the form
/// is dirty, call `UserDefaultsDraftStore.save(_:forKey:)`.
///
/// ```swift
/// // Typical ViewModel usage:
/// private var autosaveTask: Task<Void, Never>?
///
/// func onFieldChange() {
///     isDirty = true
///     scheduleAutosave()
/// }
///
/// private func scheduleAutosave() {
///     guard autosaveTask == nil else { return }
///     autosaveTask = Task { [weak self] in
///         repeat {
///             try? await Task.sleep(for: .seconds(DraftLifecycle.autosaveInterval))
///             guard let self, self.isDirty else { break }
///             try? await self.store.save(self.buildDraft(), forKey: self.draftKey)
///             self.isDirty = false
///         } while !Task.isCancelled
///     }
/// }
/// ```
public enum DraftLifecycle {

    // MARK: — Expiration

    /// Drafts not updated within this interval (30 days) are considered stale
    /// and will be removed by the next `prune` call.
    public static let defaultExpirationInterval: TimeInterval = 30 * 86_400

    // MARK: — Autosave

    /// Interval between autosave ticks while the form is dirty (3 seconds).
    ///
    /// This is deliberately short so that a force-quit or crash within 3 s of
    /// the last keystroke still recovers the user's work.
    public static let autosaveInterval: TimeInterval = 3

    // MARK: — Pruning schedule

    /// Minimum time between automatic prune sweeps (1 hour).
    ///
    /// Store the last prune timestamp in UserDefaults and skip the sweep if
    /// the last prune was more recent than this value to avoid redundant work.
    public static let minimumPruneInterval: TimeInterval = 3_600
}
