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
        var config = Configuration()
        config.label = "bizarrecrm"
        config.prepareDatabase { db in
            // When migrating to GRDB/SQLCipher, wire the passphrase here:
            //   let passphrase = try KeychainStore.shared.dbPassphrase()
            //   try db.usePassphrase(passphrase)
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
