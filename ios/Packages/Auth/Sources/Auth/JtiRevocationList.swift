import Foundation
import Persistence

// §28.14 Session & token — JTI revocation list helper
//
// When the server issues a 401 with a body indicating that a specific JWT
// was revoked (rather than simply expired), the client should record the
// JTI locally so that:
//   1. Retried requests holding a stale in-memory token are not re-attempted.
//   2. Offline-cached JTIs remain blocked even if the token hasn't yet expired
//      by wall-clock time.
//
// This is a client-side complement to server-side JTI block-lists. It does NOT
// replace server validation — it merely provides a fast-path rejection that
// avoids unnecessary retries and logs them for audit.
//
// Design notes:
// - `JtiRevocationList` is an actor so concurrent 401-handling code from
//   multiple in-flight requests won't race on the same set.
// - The list is stored in memory only for this session; JTIs are single-use
//   per session so no cross-launch persistence is needed.
// - Maximum 256 entries; oldest are evicted FIFO to avoid unbounded growth.
//   In practice the list should stay at 1-3 entries (one per concurrent 401).

// MARK: - JtiRevocationList

/// In-memory, actor-isolated store of revoked JWT `jti` claim values.
///
/// ## Usage
/// ```swift
/// // On a 401 with body { "code": "token_revoked", "jti": "abc123" }:
/// await JtiRevocationList.shared.revoke("abc123")
///
/// // Before retrying a request, guard:
/// if await JtiRevocationList.shared.isRevoked(jti) {
///     throw APITransportError.unauthorized
/// }
/// ```
public actor JtiRevocationList {

    // MARK: - Shared instance

    public static let shared = JtiRevocationList()

    // MARK: - State

    /// FIFO-ordered list of revoked JTIs.
    /// Bounded at `maxEntries` to prevent unbounded memory growth.
    private var entries: [String] = []
    private let maxEntries: Int

    // MARK: - Init

    /// - Parameter maxEntries: Maximum number of revoked JTIs to hold in memory.
    ///   Defaults to 256 — far more than any realistic session will encounter.
    public init(maxEntries: Int = 256) {
        self.maxEntries = maxEntries
    }

    // MARK: - Public API

    /// Records `jti` as revoked.
    ///
    /// If `jti` is already in the list this is a no-op (idempotent).
    /// When the list is at capacity the oldest entry is evicted before inserting.
    ///
    /// - Parameter jti: The `jti` claim value from the JWT that the server revoked.
    public func revoke(_ jti: String) {
        guard !jti.isEmpty, !entries.contains(jti) else { return }
        if entries.count >= maxEntries {
            entries.removeFirst()
        }
        entries.append(jti)
        AppLog.auth.info("JtiRevocationList: revoked jti (list size=\(self.entries.count))")
    }

    /// Returns `true` when `jti` is in the local revocation list.
    ///
    /// A return value of `false` does **not** mean the token is valid —
    /// server-side validation is always authoritative. This is a fast-path
    /// client-side guard to skip unnecessary retries.
    ///
    /// - Parameter jti: The `jti` claim to check.
    public func isRevoked(_ jti: String) -> Bool {
        entries.contains(jti)
    }

    /// Clears all entries. Called on logout / session teardown.
    public func invalidateAll() {
        let count = entries.count
        entries.removeAll()
        if count > 0 {
            AppLog.auth.debug("JtiRevocationList: cleared \(count) entries on session teardown")
        }
    }

    /// The current number of revoked entries (for diagnostics / tests).
    public var count: Int { entries.count }
}
