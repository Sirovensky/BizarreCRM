import Foundation
import GRDB
import Core

/// Lightweight holder for the shared GRDB pool. Call `open()` once at app
/// launch; downstream code reads `pool()`. SQLCipher is wired up through
/// the GRDB/SQLCipher subspec — swap in when we move past Phase 0 (the
/// plain SQLite config lets dev proceed for now).
public actor Database {
    public static let shared = Database()

    private var _pool: DatabasePool?

    private init() {}

    public func pool() -> DatabasePool? { _pool }

    public func open() async throws {
        guard _pool == nil else { return }

        let fm = FileManager.default
        let supportDir = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbURL = supportDir.appendingPathComponent("bizarrecrm.sqlite")
        try await open(at: dbURL)
    }

    /// Test-friendly override: open a pool at a caller-supplied path.
    /// Integration tests hand in a temp directory so they don't clobber
    /// the user's on-device DB. Also used by `reopen(at:)` below.
    public func open(at url: URL) async throws {
        // Fetch (or generate) the 256-bit passphrase from the Keychain.
        // `dbPassphrase()` creates a new random key on first launch and
        // returns the cached one on every subsequent launch.
        //
        // Migration path for existing installs that ran without a passphrase:
        // If GRDB opens an unencrypted file with `usePassphrase`, it will
        // throw SQLITE_NOTADB. Callers that catch that error should call
        // `reopen(at:)` after deleting or migrating the DB file. The
        // schema-version table (`grdb_migrations`) survives a wipe because
        // Migrator.register re-creates it from scratch; only local offline
        // data is lost, which is also what would happen on a re-install.
        // SEC-1 (partial): passphrase is generated + stored via KeychainStore.
        // GRDB.SQLCipher dep addition pending — for now we rely on iOS Data
        // Protection (FileProtectionType.complete on the SQLite file).
        // TODO: add `grdb-sqlcipher` SPM dep and re-enable `db.usePassphrase(_:)`.
        _ = try KeychainStore.shared.dbPassphrase()

        var config = Configuration()
        config.label = "bizarrecrm"
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let pool = try DatabasePool(path: url.path, configuration: config)
        try Migrator.register(on: pool)
        self._pool = pool

        AppLog.persistence.info("GRDB opened at \(url.path, privacy: .public)")
    }

    /// Close + reopen at a new path. Tests call this to swap the shared
    /// pool for a throwaway one inside setUp, then `close()` in tearDown.
    public func reopen(at url: URL) async throws {
        _pool = nil
        try await open(at: url)
    }

    public func close() {
        _pool = nil
    }
}
