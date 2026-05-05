import XCTest
@testable import Core

final class AnalyticsEventCatalogTests: XCTestCase {

    // MARK: — Every case has a non-empty raw value

    func test_allEvents_haveNonEmptyRawValue() {
        for event in AnalyticsEvent.allCases {
            XCTAssertFalse(event.rawValue.isEmpty, "\(event) has empty rawValue")
        }
    }

    // MARK: — Every case has a category

    func test_allEvents_haveCategory() {
        for event in AnalyticsEvent.allCases {
            let category = event.category
            XCTAssertFalse(category.rawValue.isEmpty, "\(event) returned empty category")
        }
    }

    // MARK: — Minimum 50 events

    func test_eventCatalog_hasAtLeast50Events() {
        XCTAssertGreaterThanOrEqual(AnalyticsEvent.allCases.count, 50,
            "Catalog must contain at least 50 events, found \(AnalyticsEvent.allCases.count)")
    }

    // MARK: — All categories are covered

    func test_allCategories_areUsedByAtLeastOneEvent() {
        let usedCategories = Set(AnalyticsEvent.allCases.map(\.category))
        for category in AnalyticsCategory.allCases {
            XCTAssertTrue(usedCategories.contains(category),
                "Category \(category) has no events assigned")
        }
    }

    // MARK: — Category groupings are correct

    func test_appLifecycleEvents_haveCorrectCategory() {
        let lifecycleEvents: [AnalyticsEvent] = [
            .appLaunched, .appBackgrounded, .appForegrounded,
            .sessionStarted, .sessionEnded
        ]
        for event in lifecycleEvents {
            XCTAssertEqual(event.category, .appLifecycle, "\(event) should be .appLifecycle")
        }
    }

    func test_navigationEvents_haveCorrectCategory() {
        let navEvents: [AnalyticsEvent] = [.screenViewed, .tabSwitched, .deepLinkOpened]
        for event in navEvents {
            XCTAssertEqual(event.category, .navigation, "\(event) should be .navigation")
        }
    }

    func test_authEvents_haveCorrectCategory() {
        let authEvents: [AnalyticsEvent] = [
            .loginAttempted, .loginSucceeded, .loginFailed,
            .signedOut, .pinUnlocked, .pinFailed, .passkeyUsed, .twoFactorChallenged
        ]
        for event in authEvents {
            XCTAssertEqual(event.category, .auth, "\(event) should be .auth")
        }
    }

    func test_hardwareEvents_haveCorrectCategory() {
        let hwEvents: [AnalyticsEvent] = [
            .drawerKicked, .receiptPrinted, .barcodeScanned
        ]
        for event in hwEvents {
            XCTAssertEqual(event.category, .hardware, "\(event) should be .hardware")
        }
    }

    // MARK: — Raw values use dot-notation

    func test_allEvents_rawValueContainsDot() {
        for event in AnalyticsEvent.allCases {
            XCTAssertTrue(event.rawValue.contains("."),
                "\(event) rawValue '\(event.rawValue)' should use dot-notation")
        }
    }

    // MARK: — Raw values are unique

    func test_allEvents_haveUniqueRawValues() {
        let rawValues = AnalyticsEvent.allCases.map(\.rawValue)
        let unique = Set(rawValues)
        XCTAssertEqual(rawValues.count, unique.count, "Duplicate raw values found")
    }

    // MARK: — Specific key events exist

    func test_specificDomainEvents_exist() {
        let expectedRawValues: Set<String> = [
            "app.launched", "session.started", "screen.viewed",
            "auth.login.attempted", "auth.login.succeeded",
            "ticket.created", "pos.sale.finalized", "hardware.drawer.kicked",
            "inventory.adjusted", "crash.detected", "sync.queue.drained"
        ]
        let actualRawValues = Set(AnalyticsEvent.allCases.map(\.rawValue))
        for raw in expectedRawValues {
            XCTAssertTrue(actualRawValues.contains(raw),
                "Expected event '\(raw)' not found in catalog")
        }
    }

    // MARK: — Sendable conformance (compile-time, no runtime check needed)

    func test_analyticsEvent_isSendable() {
        // If this compiles, Sendable conformance works
        let _: any Sendable = AnalyticsEvent.appLaunched
    }

    func test_analyticsCategory_isSendable() {
        let _: any Sendable = AnalyticsCategory.appLifecycle
    }
}
