import XCTest
@testable import Core

// §34 Crisis Recovery helpers — Tests
// Covers: CrisisMode, EmergencyContactInfo/Cache, CrashLoopDetector, SafeMode,
//         RecoveryReport + RecoveryReportWriter.

// ---------------------------------------------------------------------------
// MARK: — Helpers
// ---------------------------------------------------------------------------

/// Returns a fresh `UserDefaults` suite isolated per test invocation.
private func freshDefaults(file: StaticString = #file, line: UInt = #line) -> UserDefaults {
    let suite = "test.crisis.\(UUID().uuidString)"
    return UserDefaults(suiteName: suite)!
}

// ---------------------------------------------------------------------------
// MARK: — CrisisMode
// ---------------------------------------------------------------------------

@MainActor
final class CrisisModeTests: XCTestCase {

    func test_isActive_falseByDefault() {
        let mode = CrisisMode(defaults: freshDefaults())
        XCTAssertFalse(mode.isActive)
        XCTAssertNil(mode.activatedAt)
    }

    func test_activate_setsIsActiveTrue() {
        let mode = CrisisMode(defaults: freshDefaults())
        mode.activate()
        XCTAssertTrue(mode.isActive)
        XCTAssertNotNil(mode.activatedAt)
    }

    func test_activate_isIdempotent() {
        let mode = CrisisMode(defaults: freshDefaults())
        mode.activate()
        let first = mode.activatedAt
        mode.activate() // second call must not change activatedAt
        XCTAssertEqual(mode.activatedAt, first)
    }

    func test_deactivate_resetsState() {
        let mode = CrisisMode(defaults: freshDefaults())
        mode.activate()
        mode.deactivate()
        XCTAssertFalse(mode.isActive)
        XCTAssertNil(mode.activatedAt)
    }

    func test_deactivate_isIdempotent() {
        let mode = CrisisMode(defaults: freshDefaults())
        mode.deactivate() // already inactive — must not crash
        XCTAssertFalse(mode.isActive)
    }

    func test_persistsAcrossInstances() {
        let suite = "test.crisis.persist.\(UUID().uuidString)"
        let defaults1 = UserDefaults(suiteName: suite)!
        let mode1 = CrisisMode(defaults: defaults1)
        mode1.activate()

        let defaults2 = UserDefaults(suiteName: suite)!
        let mode2 = CrisisMode(defaults: defaults2)
        XCTAssertTrue(mode2.isActive)
        XCTAssertNotNil(mode2.activatedAt)
    }

    func test_deactivate_clearsPersistedState() {
        let suite = "test.crisis.persist2.\(UUID().uuidString)"
        let defaults1 = UserDefaults(suiteName: suite)!
        let mode1 = CrisisMode(defaults: defaults1)
        mode1.activate()
        mode1.deactivate()

        let defaults2 = UserDefaults(suiteName: suite)!
        let mode2 = CrisisMode(defaults: defaults2)
        XCTAssertFalse(mode2.isActive)
    }
}

// ---------------------------------------------------------------------------
// MARK: — EmergencyContactInfo + EmergencyContactCache
// ---------------------------------------------------------------------------

final class EmergencyContactInfoTests: XCTestCase {

    func test_codableRoundTrip() throws {
        let info = EmergencyContactInfo(
            supportPhone: "+1-800-BIZARRE",
            tenantAdminName: "Alice",
            tenantAdminContact: "alice@acme.com"
        )
        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(EmergencyContactInfo.self, from: data)
        XCTAssertEqual(decoded, info)
    }

    func test_equatable() {
        let a = EmergencyContactInfo(supportPhone: "111", tenantAdminName: "Bob", tenantAdminContact: "bob@b.com")
        let b = EmergencyContactInfo(supportPhone: "111", tenantAdminName: "Bob", tenantAdminContact: "bob@b.com")
        XCTAssertEqual(a, b)
    }

    func test_store_and_load() {
        let cache = EmergencyContactCache(defaults: freshDefaults())
        let info = EmergencyContactInfo(
            supportPhone: "+1-555-0100",
            tenantAdminName: "Support Bot",
            tenantAdminContact: "support@biz.com"
        )
        cache.store(info)
        let loaded = cache.load()
        XCTAssertEqual(loaded, info)
    }

    func test_load_returnsNilWhenEmpty() {
        let cache = EmergencyContactCache(defaults: freshDefaults())
        XCTAssertNil(cache.load())
    }

    func test_store_overwritesPreviousEntry() {
        let cache = EmergencyContactCache(defaults: freshDefaults())
        let first = EmergencyContactInfo(supportPhone: "111", tenantAdminName: "A", tenantAdminContact: "a@x.com")
        let second = EmergencyContactInfo(supportPhone: "222", tenantAdminName: "B", tenantAdminContact: "b@x.com")
        cache.store(first)
        cache.store(second)
        XCTAssertEqual(cache.load(), second)
    }

    func test_clear_removesEntry() {
        let cache = EmergencyContactCache(defaults: freshDefaults())
        let info = EmergencyContactInfo(supportPhone: "999", tenantAdminName: "X", tenantAdminContact: "x@x.com")
        cache.store(info)
        cache.clear()
        XCTAssertNil(cache.load())
    }

    func test_store_returnsStoredInfo() {
        let cache = EmergencyContactCache(defaults: freshDefaults())
        let info = EmergencyContactInfo(supportPhone: "777", tenantAdminName: "Y", tenantAdminContact: "y@y.com")
        let returned = cache.store(info)
        XCTAssertEqual(returned, info)
    }
}

// ---------------------------------------------------------------------------
// MARK: — CrashLoopDetector
// ---------------------------------------------------------------------------

final class CrashLoopDetectorTests: XCTestCase {

    func test_freshDetector_isNotLooping() {
        let detector = CrashLoopDetector(defaults: freshDefaults(), windowSeconds: 300, threshold: 3)
        XCTAssertFalse(detector.isLooping())
    }

    func test_belowThreshold_isNotLooping() {
        let defaults = freshDefaults()
        let detector = CrashLoopDetector(defaults: defaults, windowSeconds: 300, threshold: 3)
        let now = Date()
        // Record 2 launches (below threshold of 3)
        detector.recordLaunch(at: now.addingTimeInterval(-200))
        detector.recordLaunch(at: now.addingTimeInterval(-100))
        XCTAssertFalse(detector.isLooping(at: now))
    }

    func test_atThreshold_isLooping() {
        let defaults = freshDefaults()
        let detector = CrashLoopDetector(defaults: defaults, windowSeconds: 300, threshold: 3)
        let now = Date()
        detector.recordLaunch(at: now.addingTimeInterval(-250))
        detector.recordLaunch(at: now.addingTimeInterval(-150))
        detector.recordLaunch(at: now.addingTimeInterval(-50))
        XCTAssertTrue(detector.isLooping(at: now))
    }

    func test_oldTimestamps_outsideWindow_notCounted() {
        let defaults = freshDefaults()
        let detector = CrashLoopDetector(defaults: defaults, windowSeconds: 300, threshold: 3)
        let now = Date()
        // Two launches outside window
        detector.recordLaunch(at: now.addingTimeInterval(-400))
        detector.recordLaunch(at: now.addingTimeInterval(-350))
        // One inside window
        detector.recordLaunch(at: now.addingTimeInterval(-10))
        XCTAssertFalse(detector.isLooping(at: now))
    }

    func test_recentLaunchCount_correctCount() {
        let defaults = freshDefaults()
        let detector = CrashLoopDetector(defaults: defaults, windowSeconds: 300, threshold: 3)
        let now = Date()
        detector.recordLaunch(at: now.addingTimeInterval(-200))
        detector.recordLaunch(at: now.addingTimeInterval(-100))
        XCTAssertEqual(detector.recentLaunchCount(at: now), 2)
    }

    func test_reset_clearsHistory() {
        let defaults = freshDefaults()
        let detector = CrashLoopDetector(defaults: defaults, windowSeconds: 300, threshold: 3)
        let now = Date()
        detector.recordLaunch(at: now.addingTimeInterval(-10))
        detector.recordLaunch(at: now.addingTimeInterval(-20))
        detector.recordLaunch(at: now.addingTimeInterval(-30))
        XCTAssertTrue(detector.isLooping(at: now))
        detector.reset()
        XCTAssertFalse(detector.isLooping(at: now))
    }

    func test_recordLaunch_prunesOldEntries() {
        let defaults = freshDefaults()
        let detector = CrashLoopDetector(defaults: defaults, windowSeconds: 60, threshold: 10)
        let now = Date()
        // Push 5 entries outside the window
        for i in 1...5 {
            detector.recordLaunch(at: now.addingTimeInterval(-Double(i) * 100))
        }
        // Now record inside window
        detector.recordLaunch(at: now)
        // Only the one inside the window should remain
        XCTAssertEqual(detector.recentLaunchCount(at: now), 1)
    }

    @MainActor
    func test_evaluateAndTriggerIfNeeded_activatesSafeMode() {
        let defaults = freshDefaults()
        let detector = CrashLoopDetector(defaults: defaults, windowSeconds: 300, threshold: 3)
        let safeDefaults = freshDefaults()
        let safe = SafeMode(defaults: safeDefaults)
        let now = Date()
        detector.recordLaunch(at: now.addingTimeInterval(-10))
        detector.recordLaunch(at: now.addingTimeInterval(-20))
        detector.recordLaunch(at: now.addingTimeInterval(-30))

        detector.evaluateAndTriggerIfNeeded(safeMode: safe, at: now)
        XCTAssertTrue(safe.isActive)
        XCTAssertEqual(safe.reason, .crashLoop)
    }

    @MainActor
    func test_evaluateAndTriggerIfNeeded_doesNotActivateWhenBelowThreshold() {
        let defaults = freshDefaults()
        let detector = CrashLoopDetector(defaults: defaults, windowSeconds: 300, threshold: 3)
        let safeDefaults = freshDefaults()
        let safe = SafeMode(defaults: safeDefaults)
        let now = Date()
        detector.recordLaunch(at: now.addingTimeInterval(-10))

        detector.evaluateAndTriggerIfNeeded(safeMode: safe, at: now)
        XCTAssertFalse(safe.isActive)
    }
}

// ---------------------------------------------------------------------------
// MARK: — SafeMode
// ---------------------------------------------------------------------------

@MainActor
final class SafeModeTests: XCTestCase {

    func test_isActive_falseByDefault() {
        let safe = SafeMode(defaults: freshDefaults())
        XCTAssertFalse(safe.isActive)
        XCTAssertNil(safe.reason)
        XCTAssertNil(safe.activatedAt)
    }

    func test_isSyncDisabled_mirrorIsActive() {
        let safe = SafeMode(defaults: freshDefaults())
        XCTAssertFalse(safe.isSyncDisabled)
        safe.activate(reason: .manual)
        XCTAssertTrue(safe.isSyncDisabled)
    }

    func test_isReadOnly_mirrorIsActive() {
        let safe = SafeMode(defaults: freshDefaults())
        XCTAssertFalse(safe.isReadOnly)
        safe.activate(reason: .networkFailure)
        XCTAssertTrue(safe.isReadOnly)
    }

    func test_activate_setsReasonAndTimestamp() {
        let safe = SafeMode(defaults: freshDefaults())
        safe.activate(reason: .crashLoop)
        XCTAssertTrue(safe.isActive)
        XCTAssertEqual(safe.reason, .crashLoop)
        XCTAssertNotNil(safe.activatedAt)
    }

    func test_activate_updatesReasonOnSubsequentCall() {
        let safe = SafeMode(defaults: freshDefaults())
        safe.activate(reason: .manual)
        safe.activate(reason: .networkFailure)
        XCTAssertEqual(safe.reason, .networkFailure)
    }

    func test_deactivate_resetsAllState() {
        let safe = SafeMode(defaults: freshDefaults())
        safe.activate(reason: .crashLoop)
        safe.deactivate()
        XCTAssertFalse(safe.isActive)
        XCTAssertNil(safe.reason)
        XCTAssertNil(safe.activatedAt)
    }

    func test_deactivate_isIdempotent() {
        let safe = SafeMode(defaults: freshDefaults())
        safe.deactivate()
        XCTAssertFalse(safe.isActive)
    }

    func test_persistsAcrossInstances() {
        let suite = "test.safemode.persist.\(UUID().uuidString)"
        let d1 = UserDefaults(suiteName: suite)!
        let safe1 = SafeMode(defaults: d1)
        safe1.activate(reason: .crashLoop)

        let d2 = UserDefaults(suiteName: suite)!
        let safe2 = SafeMode(defaults: d2)
        XCTAssertTrue(safe2.isActive)
        XCTAssertEqual(safe2.reason, .crashLoop)
        XCTAssertNotNil(safe2.activatedAt)
    }

    func test_deactivate_clearsPersistedState() {
        let suite = "test.safemode.persist2.\(UUID().uuidString)"
        let d1 = UserDefaults(suiteName: suite)!
        let safe1 = SafeMode(defaults: d1)
        safe1.activate(reason: .manual)
        safe1.deactivate()

        let d2 = UserDefaults(suiteName: suite)!
        let safe2 = SafeMode(defaults: d2)
        XCTAssertFalse(safe2.isActive)
        XCTAssertNil(safe2.reason)
    }

    func test_allReasonsRoundTripThroughRawValue() {
        for reason in SafeModeReason.allCases {
            XCTAssertNotNil(SafeModeReason(rawValue: reason.rawValue))
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: — RecoveryReport
// ---------------------------------------------------------------------------

final class RecoveryReportTests: XCTestCase {

    private func makeReport(
        isCrisisActive: Bool = false,
        isSafeActive: Bool = false,
        safeModeReason: String? = nil,
        recentLaunchCount: Int = 0,
        crashLoopDetected: Bool = false
    ) -> RecoveryReport {
        RecoveryReport(
            appVersion: "1.0.0",
            appBuild: "42",
            iOSVersion: "17.4",
            device: "iPhone16,2",
            tenantSlug: "acme-repairs",
            userRole: "cashier",
            isCrisisModeActive: isCrisisActive,
            crisisModeActivatedAt: isCrisisActive ? Date(timeIntervalSince1970: 1_700_000_000) : nil,
            isSafeModeActive: isSafeActive,
            safeModeReason: safeModeReason,
            safeModeActivatedAt: isSafeActive ? Date(timeIntervalSince1970: 1_700_001_000) : nil,
            recentLaunchCount: recentLaunchCount,
            crashLoopDetected: crashLoopDetected,
            generatedAt: Date(timeIntervalSince1970: 1_700_002_000)
        )
    }

    func test_codableRoundTrip() throws {
        let report = makeReport(isCrisisActive: true, isSafeActive: true, safeModeReason: "crashLoop")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RecoveryReport.self, from: data)

        XCTAssertEqual(decoded.appVersion, report.appVersion)
        XCTAssertEqual(decoded.tenantSlug, report.tenantSlug)
        XCTAssertEqual(decoded.userRole, report.userRole)
        XCTAssertEqual(decoded.isCrisisModeActive, report.isCrisisModeActive)
        XCTAssertEqual(decoded.isSafeModeActive, report.isSafeModeActive)
        XCTAssertEqual(decoded.safeModeReason, report.safeModeReason)
        XCTAssertEqual(decoded.crashLoopDetected, report.crashLoopDetected)
    }

    func test_reportContainsNoPIIFields() throws {
        let report = makeReport()
        let encoder = JSONEncoder()
        let data = try encoder.encode(report)
        let json = String(data: data, encoding: .utf8) ?? ""
        // PII field names must not appear in the JSON keys
        XCTAssertFalse(json.contains("\"email\""))
        XCTAssertFalse(json.contains("\"phone\""))
        XCTAssertFalse(json.contains("\"userId\""))
        XCTAssertFalse(json.contains("\"userName\""))
        XCTAssertFalse(json.contains("\"ssn\""))
    }

    func test_reportContainsMandatoryDiagnosticsFields() throws {
        let report = makeReport(
            isCrisisActive: true,
            isSafeActive: true,
            safeModeReason: "manual",
            recentLaunchCount: 4,
            crashLoopDetected: true
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(report)
        let json = String(data: data, encoding: .utf8) ?? ""

        XCTAssertTrue(json.contains("appVersion"))
        XCTAssertTrue(json.contains("appBuild"))
        XCTAssertTrue(json.contains("iOSVersion"))
        XCTAssertTrue(json.contains("device"))
        XCTAssertTrue(json.contains("tenantSlug"))
        XCTAssertTrue(json.contains("userRole"))
        XCTAssertTrue(json.contains("isCrisisModeActive"))
        XCTAssertTrue(json.contains("isSafeModeActive"))
        XCTAssertTrue(json.contains("safeModeReason"))
        XCTAssertTrue(json.contains("recentLaunchCount"))
        XCTAssertTrue(json.contains("crashLoopDetected"))
        XCTAssertTrue(json.contains("generatedAt"))
    }

    func test_tenantSlugIsNotAUserId() throws {
        // Tenant slug must be a business identifier like "acme-repairs", never a UUID
        let report = makeReport()
        let encoder = JSONEncoder()
        let data = try encoder.encode(report)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let slug = dict?["tenantSlug"] as? String
        // Not a UUID pattern
        let uuidPattern = try NSRegularExpression(
            pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
            options: .caseInsensitive
        )
        let range = NSRange(slug!.startIndex..., in: slug!)
        XCTAssertEqual(uuidPattern.numberOfMatches(in: slug!, range: range), 0,
                       "tenantSlug should be a slug, not a UUID")
    }
}

// ---------------------------------------------------------------------------
// MARK: — RecoveryReportWriter
// ---------------------------------------------------------------------------

final class RecoveryReportWriterTests: XCTestCase {

    // Use a temp directory so we don't pollute the real caches.
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrisisTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeReport(at date: Date = Date()) -> RecoveryReport {
        RecoveryReport(
            appVersion: "1.0",
            appBuild: "1",
            iOSVersion: "17.0",
            device: "iPhone15,4",
            tenantSlug: "test-tenant",
            userRole: "admin",
            isCrisisModeActive: false,
            crisisModeActivatedAt: nil,
            isSafeModeActive: false,
            safeModeReason: nil,
            safeModeActivatedAt: nil,
            recentLaunchCount: 0,
            crashLoopDetected: false,
            generatedAt: date
        )
    }

    func test_write_createsFile() throws {
        let writer = RecoveryReportWriter(maxStoredReports: 10)
        let report = makeReport()
        let url = writer.write(report)
        XCTAssertNotNil(url)
        if let url = url {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            // Clean up
            try? FileManager.default.removeItem(at: url)
            // Also remove the parent directory we created
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: dir.deletingLastPathComponent())
        }
    }

    func test_write_producesValidJSON() throws {
        let writer = RecoveryReportWriter(maxStoredReports: 10)
        let report = makeReport()
        guard let url = writer.write(report) else {
            XCTFail("write returned nil")
            return
        }
        defer {
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: dir.deletingLastPathComponent())
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RecoveryReport.self, from: data)
        XCTAssertEqual(decoded.appVersion, report.appVersion)
        XCTAssertEqual(decoded.tenantSlug, report.tenantSlug)
    }

    func test_allReportURLs_returnsWrittenReports() throws {
        let writer = RecoveryReportWriter(maxStoredReports: 10)
        let url1 = writer.write(makeReport(at: Date(timeIntervalSince1970: 1_700_000_000)))
        let url2 = writer.write(makeReport(at: Date(timeIntervalSince1970: 1_700_001_000)))
        XCTAssertNotNil(url1)
        XCTAssertNotNil(url2)
        let all = writer.allReportURLs()
        XCTAssertGreaterThanOrEqual(all.count, 2)
        // Clean up
        writer.deleteAll()
        if let dir = url1?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: dir.deletingLastPathComponent())
        }
    }

    func test_pruning_keepsMostRecentReports() throws {
        let writer = RecoveryReportWriter(maxStoredReports: 3)
        // Write 5 reports
        var urls: [URL] = []
        for i in 0..<5 {
            let date = Date(timeIntervalSince1970: Double(1_700_000_000 + i * 1000))
            if let url = writer.write(makeReport(at: date)) {
                urls.append(url)
            }
        }
        let all = writer.allReportURLs()
        XCTAssertLessThanOrEqual(all.count, 3)
        // Clean up
        writer.deleteAll()
        if let firstDir = urls.first?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: firstDir.deletingLastPathComponent())
        }
    }

    func test_deleteAll_removesAllReports() throws {
        let writer = RecoveryReportWriter(maxStoredReports: 10)
        _ = writer.write(makeReport())
        _ = writer.write(makeReport())
        writer.deleteAll()
        let all = writer.allReportURLs()
        XCTAssertEqual(all.count, 0)
    }

    func test_fileNameContainsRecoveryPrefix() throws {
        let writer = RecoveryReportWriter(maxStoredReports: 10)
        let url = writer.write(makeReport())
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.lastPathComponent.hasPrefix("recovery-") ?? false)
        XCTAssertTrue(url?.pathExtension == "json")
        // Clean up
        if let dir = url?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: dir.deletingLastPathComponent())
        }
    }
}
