import XCTest
@testable import Persistence

// MARK: - BackupManagerTests
//
// Tests for BackupManager, BackupMetadata, BackupError (§1 Backup & restore).
// Coverage target: ≥ 80% of Backup/*.swift

final class BackupManagerTests: XCTestCase {

    // Shared actor under test
    private let manager = BackupManager()

    // MARK: - BackupMetadata

    func testBackupMetadataMagicBytes() {
        let magic = BackupMetadata.magic
        XCTAssertEqual(magic, "BCRMBKUP".data(using: .utf8)!)
        XCTAssertEqual(magic.count, 8)
    }

    func testBackupMetadataCurrentVersion() {
        XCTAssertEqual(BackupMetadata.currentVersion, 1)
    }

    func testBackupMetadataRoundtrip() throws {
        let meta = BackupMetadata(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Test iPhone",
            tenantId: "testshop",
            sizeBytes: 12345,
            schemaVersion: 4
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(meta)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupMetadata.self, from: data)

        XCTAssertEqual(decoded.version, meta.version)
        XCTAssertEqual(decoded.deviceName, meta.deviceName)
        XCTAssertEqual(decoded.tenantId, meta.tenantId)
        XCTAssertEqual(decoded.sizeBytes, meta.sizeBytes)
        XCTAssertEqual(decoded.schemaVersion, meta.schemaVersion)
    }

    // MARK: - BackupError

    func testBackupErrorLocalizedDescriptions() {
        XCTAssertFalse(BackupError.invalidPassphrase.localizedDescription.isEmpty)
        XCTAssertFalse(BackupError.corrupt.localizedDescription.isEmpty)
        XCTAssertFalse(BackupError.schemaMismatch(local: 4, backup: 3).localizedDescription.isEmpty)

        let underlying = NSError(domain: "test", code: 42, userInfo: nil)
        XCTAssertFalse(BackupError.ioError(underlying).localizedDescription.isEmpty)
    }

    func testSchemaMismatchIncludesVersions() {
        let err = BackupError.schemaMismatch(local: 5, backup: 3)
        let desc = err.localizedDescription ?? ""
        XCTAssertTrue(desc.contains("5") && desc.contains("3"),
                      "Expected local (5) and backup (3) version in: \(desc)")
    }

    // MARK: - Export → Verify roundtrip (happy path)

    func testExportAndVerify() async throws {
        let url = try await manager.exportBackup(passphrase: "correct-horse-battery-staple")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "Backup file should exist at \(url.path)")

        let meta = try await manager.verifyBackup(url: url)
        XCTAssertEqual(meta.version, BackupMetadata.currentVersion)
        XCTAssertFalse(meta.deviceName.isEmpty)
    }

    func testExportedFilenameEndsWithBkup() async throws {
        let url = try await manager.exportBackup(passphrase: "passphrase1")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".bkup"),
                      "Expected .bkup extension, got: \(url.lastPathComponent)")
    }

    // MARK: - Export → Restore roundtrip (happy path)

    func testExportRestoreRoundtrip() async throws {
        let url = try await manager.exportBackup(passphrase: "test-passphrase-2026")
        defer { try? FileManager.default.removeItem(at: url) }

        // Restore should succeed without throwing
        try await manager.restoreBackup(url: url, passphrase: "test-passphrase-2026")

        // Confirm pending restore was staged in UserDefaults
        let key = "com.bizarrecrm.backup.pendingRestoreURL"
        let staged = UserDefaults.standard.string(forKey: key)
        XCTAssertNotNil(staged, "Restore should write the staging URL to UserDefaults")

        // Cleanup: consume the pending restore so other tests aren't affected
        _ = BackupManager.consumePendingRestore()
    }

    // MARK: - Wrong passphrase

    func testWrongPassphraseThrowsInvalidPassphrase() async throws {
        let url = try await manager.exportBackup(passphrase: "correct-passphrase")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            try await manager.restoreBackup(url: url, passphrase: "wrong-passphrase")
            XCTFail("Expected BackupError.invalidPassphrase")
        } catch BackupError.invalidPassphrase {
            // Expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Corrupt file

    func testCorruptFileThrows() async throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt_\(UUID().uuidString).bkup")
        let garbage = Data("this is not a valid backup file".utf8)
        try garbage.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        do {
            _ = try await manager.verifyBackup(url: tmpURL)
            XCTFail("Expected BackupError.corrupt")
        } catch BackupError.corrupt {
            // Expected
        }
    }

    func testEmptyFileThrows() async throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty_\(UUID().uuidString).bkup")
        try Data().write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        do {
            _ = try await manager.verifyBackup(url: tmpURL)
            XCTFail("Expected BackupError.corrupt")
        } catch BackupError.corrupt {
            // Expected
        }
    }

    // MARK: - consumePendingRestore

    func testConsumePendingRestoreReturnsNilWhenNothingPending() {
        // Clear any leftover state first
        UserDefaults.standard.removeObject(forKey: "com.bizarrecrm.backup.pendingRestoreURL")
        XCTAssertNil(BackupManager.consumePendingRestore())
    }

    func testConsumePendingRestoreRemovesAfterRead() {
        let key = "com.bizarrecrm.backup.pendingRestoreURL"
        // Point to a file that exists: use this test binary itself
        let fakePath = Bundle.module.bundlePath
        UserDefaults.standard.set(fakePath, forKey: key)

        let first = BackupManager.consumePendingRestore()
        XCTAssertNotNil(first, "Should return a URL on first consume")

        let second = BackupManager.consumePendingRestore()
        XCTAssertNil(second, "Should return nil on second consume (key removed)")
    }
}
