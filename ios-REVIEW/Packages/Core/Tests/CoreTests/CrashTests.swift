import XCTest
@testable import Core

// §32 Crash recovery pipeline — TDD tests (written before implementation)
// Tests: BreadcrumbStore ring buffer, LogRedactor integration,
//        SessionFingerprint encode round-trip, CrashRecovery flag logic.

final class BreadcrumbStoreTests: XCTestCase {

    // MARK: — Ring buffer cap

    func test_push_respectsRingBufferCapOf100() async {
        let store = BreadcrumbStore()
        await store.clear()

        for i in 0..<120 {
            await store.push(Breadcrumb(
                timestamp: Date(),
                level: .info,
                category: "test",
                message: "msg-\(i)",
                metadata: nil
            ))
        }

        let crumbs = await store.recent()
        XCTAssertEqual(crumbs.count, 100, "Ring buffer must cap at 100 entries")
        // Newest entries are kept
        XCTAssertEqual(crumbs.last?.message, "msg-119")
    }

    func test_recent_withSmallCount_returnsOnlyRequested() async {
        let store = BreadcrumbStore()
        await store.clear()

        for i in 0..<10 {
            await store.push(Breadcrumb(
                timestamp: Date(),
                level: .debug,
                category: "cat",
                message: "m\(i)",
                metadata: nil
            ))
        }

        let crumbs = await store.recent(3)
        XCTAssertEqual(crumbs.count, 3)
    }

    func test_clear_removesAll() async {
        let store = BreadcrumbStore()
        await store.push(Breadcrumb(timestamp: Date(), level: .info, category: "c", message: "x", metadata: nil))
        await store.clear()

        let crumbs = await store.recent()
        XCTAssertTrue(crumbs.isEmpty)
    }

    func test_push_redactsPII() async {
        let store = BreadcrumbStore()
        await store.clear()

        await store.push(Breadcrumb(
            timestamp: Date(),
            level: .warning,
            category: "auth",
            message: "User logged in with user@example.com",
            metadata: nil
        ))

        let crumbs = await store.recent(1)
        XCTAssertFalse(crumbs.first?.message.contains("user@example.com") ?? false,
                       "PII email must be redacted in stored breadcrumb")
        XCTAssertTrue(crumbs.first?.message.contains("<email>") ?? false)
    }

    func test_breadcrumb_isSendableAndCodable() throws {
        let original = Breadcrumb(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            level: .error,
            category: "crash",
            message: "something went wrong",
            metadata: ["key": "value"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Breadcrumb.self, from: data)
        XCTAssertEqual(decoded.message, original.message)
        XCTAssertEqual(decoded.category, original.category)
        XCTAssertEqual(decoded.level, original.level)
        XCTAssertEqual(decoded.metadata?["key"], "value")
    }
}

// MARK: — SessionFingerprint

final class SessionFingerprintTests: XCTestCase {

    func test_encodeDecodeRoundTrip() throws {
        let fp = SessionFingerprint(
            device: "iPhone16,2",
            iOSVersion: "17.4",
            appVersion: "1.0.0",
            appBuild: "42",
            tenantSlug: "acme",
            userRole: "admin"
        )
        let data = try JSONEncoder().encode(fp)
        let decoded = try JSONDecoder().decode(SessionFingerprint.self, from: data)

        XCTAssertEqual(decoded.device, fp.device)
        XCTAssertEqual(decoded.iOSVersion, fp.iOSVersion)
        XCTAssertEqual(decoded.appVersion, fp.appVersion)
        XCTAssertEqual(decoded.appBuild, fp.appBuild)
        XCTAssertEqual(decoded.tenantSlug, fp.tenantSlug)
        XCTAssertEqual(decoded.userRole, fp.userRole)
    }

    func test_fingerprintHasNoEmail() throws {
        // Ensure no PII fields exist in the type by encoding and checking JSON
        let fp = SessionFingerprint(
            device: "iPhone14,3",
            iOSVersion: "17.0",
            appVersion: "1.0",
            appBuild: "1",
            tenantSlug: "store",
            userRole: "cashier"
        )
        let data = try JSONEncoder().encode(fp)
        let json = String(data: data, encoding: .utf8) ?? ""
        // Should not contain email/phone/ssn fields
        XCTAssertFalse(json.contains("email"))
        XCTAssertFalse(json.contains("phone"))
    }
}

// MARK: — CrashRecovery

final class CrashRecoveryTests: XCTestCase {

    func test_willRestartAfterCrash_falseByDefault() {
        let defaults = UserDefaults(suiteName: "test.crash.\(UUID().uuidString)")!
        let recovery = CrashRecovery(defaults: defaults)
        XCTAssertFalse(recovery.willRestartAfterCrash)
    }

    func test_markCrashed_setsFlag() {
        let defaults = UserDefaults(suiteName: "test.crash.\(UUID().uuidString)")!
        let recovery = CrashRecovery(defaults: defaults)
        recovery.markCrashed()
        XCTAssertTrue(recovery.willRestartAfterCrash)
    }

    func test_clearCrashFlag_resetsFlag() {
        let defaults = UserDefaults(suiteName: "test.crash.\(UUID().uuidString)")!
        let recovery = CrashRecovery(defaults: defaults)
        recovery.markCrashed()
        recovery.clearCrashFlag()
        XCTAssertFalse(recovery.willRestartAfterCrash)
    }

    func test_willRestartAfterCrash_persistsAcrossInstances() {
        let suiteName = "test.crash.\(UUID().uuidString)"
        let defaults1 = UserDefaults(suiteName: suiteName)!
        let recovery1 = CrashRecovery(defaults: defaults1)
        recovery1.markCrashed()

        let defaults2 = UserDefaults(suiteName: suiteName)!
        let recovery2 = CrashRecovery(defaults: defaults2)
        XCTAssertTrue(recovery2.willRestartAfterCrash)
    }
}

// MARK: — LogRedactor integration (crash context)

final class CrashLogRedactorTests: XCTestCase {

    func test_redactEmail_inCrashContext() {
        let raw = "Crash occurred for user test@bizarrecrm.com during checkout"
        let redacted = LogRedactor.redact(raw)
        XCTAssertFalse(redacted.contains("test@bizarrecrm.com"))
        XCTAssertTrue(redacted.contains("<email>"))
    }

    func test_redactBearerToken_inCrashContext() {
        let raw = "Request failed: Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abc"
        let redacted = LogRedactor.redact(raw)
        XCTAssertFalse(redacted.contains("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"))
    }

    func test_redactPhone_inCrashContext() {
        let raw = "Customer 555-123-4567 raised a support ticket"
        let redacted = LogRedactor.redact(raw)
        XCTAssertFalse(redacted.contains("555-123-4567"))
        XCTAssertTrue(redacted.contains("<phone>"))
    }
}
