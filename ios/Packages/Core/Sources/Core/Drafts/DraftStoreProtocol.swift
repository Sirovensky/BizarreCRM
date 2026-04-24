import Foundation

// §20 Draft Recovery — DraftStoreProtocol
// Abstract interface for all draft storage back-ends.
// Concrete implementations: UserDefaultsDraftStore (Phase 0/1), future GRDB store.

/// Abstract interface for a draft storage back-end.
///
/// All methods are async so that concrete implementations can switch between
/// UserDefaults (in-process) and GRDB (off-main) without changing call sites.
///
/// Thread-safety contract: every conforming type MUST be safe to call from
/// any Swift concurrency context (actor, Task, @MainActor).
public protocol DraftStoreProtocol: Actor {

    // MARK: — Write

    /// Persist `draft` under `key`.
    ///
    /// Calling this with the same key replaces any existing draft.
    func save<T: Codable & Sendable>(_ draft: T, forKey key: DraftKey) async throws

    // MARK: — Read

    /// Load a previously persisted draft, or `nil` if none exists.
    func load<T: Codable & Sendable>(_ type: T.Type, forKey key: DraftKey) async throws -> T?

    // MARK: — Delete

    /// Remove the draft for `key` (e.g. after a successful server save).
    /// No-ops silently if no draft exists for `key`.
    func delete(forKey key: DraftKey) async

    // MARK: — Enumerate

    /// Return metadata for every pending draft, sorted newest-first.
    ///
    /// This is the source of truth for the "recover a draft" list.
    func listPending() async -> [DraftRecord]

    // MARK: — Lifecycle

    /// Purge drafts whose `updatedAt` is older than `olderThan` seconds ago.
    ///
    /// Callers should pass `DraftLifecycle.defaultExpirationInterval` unless
    /// a custom threshold is needed.
    func prune(olderThan interval: TimeInterval) async
}
