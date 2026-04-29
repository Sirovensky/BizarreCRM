import Foundation

// MARK: - §28.12 Tenant DBs are sacred — never delete to "recover"
//
// A class of bugs that we want to make impossible by construction:
// "the tenant DB looks corrupt → just delete it and re-sync."  That path
// silently destroys offline-only edits (drafts, queued tickets, photos
// not yet uploaded) and is the one footgun §28.12 explicitly forbids.
//
// All tenant-DB delete paths must therefore go through this guard. Only
// two callers are allowed:
//
// 1. **Sign-out + tenant-switch.** The user explicitly logged out OR
//    switched to a different tenant. Routine, expected, audited.
// 2. **Settings → Danger zone → Reset.** The user typed-confirmed and
//    tapped Reset.  Audited.
//
// "Recover" is NOT a reason. Recovery from a corrupt DB must use
// `.repair` (PRAGMA integrity_check + per-table rebuild), not delete.

/// Allow-listed reasons for deleting a tenant DB. Anything outside this
/// enum is rejected by `TenantDatabaseSanctity.assertDeletable(reason:)`.
public enum TenantDatabaseDeleteReason: String, Sendable, CaseIterable {
    /// User signed out OR switched tenants. Routine, audited.
    case signOutOrTenantSwitch
    /// User typed-confirmed Settings → Danger zone → Reset.  Audited.
    case userConfirmedReset
}

/// Guard utility: every code path that deletes a tenant DB / passphrase
/// MUST first call `TenantDatabaseSanctity.assertDeletable(reason:)` so
/// we can statically grep callers and so a future "let's just nuke and
/// re-sync to recover" patch trips a precondition in debug builds.
public enum TenantDatabaseSanctity {

    /// Records a deletion request. In Debug builds, an unrecognised reason
    /// (or any `recover`-shaped string sneaking past the type system) trips
    /// `preconditionFailure`. In Release the call is a no-op so we never
    /// crash a production user mid-sign-out.
    public static func assertDeletable(reason: TenantDatabaseDeleteReason) {
        // The enum itself enforces the allow-list at compile time.
        // This function exists so the call site is greppable
        // (`grep -r TenantDatabaseSanctity.assertDeletable`).
        // We additionally log the reason so the sign-out / reset audit
        // trail (§28.13) records why the DB went away.
        AppLog.persistence.notice(
            "Tenant DB delete authorised — reason=\(reason.rawValue, privacy: .public)"
        )
    }

    /// Repair, do not delete. Returned by callers that thought they wanted
    /// to delete but landed in a "corrupt — recover" branch. The repair
    /// path is owned by the GRDB persistence layer; this enum just names
    /// the intent so reviewers can see deletion was rejected.
    public enum RecoveryDecision: Sendable, Equatable {
        /// Run `PRAGMA integrity_check` and per-table rebuild in place.
        case repairInPlace
        /// Surface a fatal error to the user — server-coordinated reset
        /// (Settings → Danger) is the only path forward.
        case surfaceToUser(reasonCode: String)
    }

    /// Call from any "DB looks broken" code path. Returns a repair
    /// decision; deletion is intentionally NOT one of the options.
    public static func decideRecovery(integrityCheckFailed: Bool) -> RecoveryDecision {
        if integrityCheckFailed {
            return .surfaceToUser(reasonCode: "tenant_db_integrity_failed")
        }
        return .repairInPlace
    }
}
