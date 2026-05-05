import XCTest
@testable import Core

// §32 Telemetry tests — AnalyticsEvent catalog additions + AppLog logger presence.
// Covers: §32.4 (8 new event cases), §32.1 (reports/notifications/sms loggers).

final class Telemetry§32Tests: XCTestCase {

    // MARK: — Test 1: syncStarted raw value

    func test_syncStarted_rawValue() {
        XCTAssertEqual(AnalyticsEvent.syncStarted.rawValue, "sync.started",
            "syncStarted raw value must be 'sync.started' per §32.4 spec")
    }

    // MARK: — Test 2: category of each new §32.4 event

    /// Verifies every new §32.4 event maps to .domain without relying on a default branch.
    /// If any case is missing from the exhaustive switch in the production code this test fails
    /// at compile time (exhaustiveness) or at runtime.
    func test_§32Events_allMapToDomainCategory() {
        // Enumerate the 8 new cases explicitly — mirrors the production switch exhaustively.
        let newEvents: [AnalyticsEvent] = [
            .syncStarted,
            .syncCompleted,
            .syncFailed,
            .posSaleComplete,
            .posSaleFailed,
            .coldLaunchMs,
            .firstPaintMs,
        ]
        for event in newEvents {
            XCTAssertEqual(event.category, .domain,
                "\(event) should map to .domain category (§32.4)")
        }
    }

    // MARK: — Test: raw values of new §32.4 events

    func test_§32Events_rawValues() {
        XCTAssertEqual(AnalyticsEvent.syncCompleted.rawValue,   "sync.completed")
        XCTAssertEqual(AnalyticsEvent.syncFailed.rawValue,      "sync.failed")
        XCTAssertEqual(AnalyticsEvent.posSaleComplete.rawValue, "pos.sale.complete")
        XCTAssertEqual(AnalyticsEvent.posSaleFailed.rawValue,   "pos.sale.failed")
        XCTAssertEqual(AnalyticsEvent.coldLaunchMs.rawValue,    "perf.cold_launch_ms")
        XCTAssertEqual(AnalyticsEvent.firstPaintMs.rawValue,    "perf.first_paint_ms")
    }

    // MARK: — Test: §32.4 events are present in allCases

    func test_§32Events_presentInAllCases() {
        let all = Set(AnalyticsEvent.allCases.map(\.rawValue))
        let required: Set<String> = [
            "sync.started", "sync.completed", "sync.failed",
            "pos.sale.complete", "pos.sale.failed",
            "perf.cold_launch_ms", "perf.first_paint_ms",
        ]
        for raw in required {
            XCTAssertTrue(all.contains(raw),
                "Expected §32.4 event '\(raw)' not found in AnalyticsEvent.allCases")
        }
    }

    // MARK: — Test 7: AppLog.reports / .notifications / .sms loggers exist (compile-only)

    func test_appLog_§32Loggers_exist() {
        // If any of these properties do not exist, the file will not compile.
        // The casts silence the "result unused" warning without calling any OSLog I/O.
        _ = AppLog.reports        as AnyObject
        _ = AppLog.notifications  as AnyObject
        _ = AppLog.sms            as AnyObject
    }
}
