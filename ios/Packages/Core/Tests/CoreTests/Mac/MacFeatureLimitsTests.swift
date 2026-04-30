// CoreTests/Mac/MacFeatureLimitsTests.swift
//
// Unit tests for §23.6 MacFeatureLimits catalog.

import XCTest
@testable import Core

final class MacFeatureLimitsTests: XCTestCase {

    func test_all_containsExpectedEntries() {
        let ids = MacFeatureLimits.all.map(\.id)
        XCTAssertTrue(ids.contains("mac.limit.widgets"))
        XCTAssertTrue(ids.contains("mac.limit.liveActivities"))
        XCTAssertTrue(ids.contains("mac.limit.nfc"))
        XCTAssertTrue(ids.contains("mac.limit.bluetoothPrinters"))
        XCTAssertTrue(ids.contains("mac.limit.haptics"))
        XCTAssertTrue(ids.contains("mac.limit.blockChypTerminal"))
    }

    func test_all_idsAreUnique() {
        let ids = MacFeatureLimits.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Duplicate IDs in MacFeatureLimits.all")
    }

    func test_all_titlesAndDetailsNonEmpty() {
        for limit in MacFeatureLimits.all {
            XCTAssertFalse(limit.title.isEmpty, "Empty title for \(limit.id)")
            XCTAssertFalse(limit.detail.isEmpty, "Empty detail for \(limit.id)")
            XCTAssertFalse(limit.symbolName.isEmpty, "Empty symbolName for \(limit.id)")
        }
    }

    func test_liveActivitiesAndNFC_areUnavailable() {
        XCTAssertEqual(MacFeatureLimits.liveActivities.availability, .unavailable)
        XCTAssertEqual(MacFeatureLimits.nfc.availability, .unavailable)
        XCTAssertEqual(MacFeatureLimits.haptics.availability, .unavailable)
        XCTAssertEqual(MacFeatureLimits.bluetoothPrinters.availability, .unavailable)
    }

    func test_widgets_areLimited() {
        XCTAssertEqual(MacFeatureLimits.widgets.availability, .limited)
        XCTAssertEqual(MacFeatureLimits.nativeBarcodeScan.availability, .limited)
    }

    func test_blockChypTerminal_isAvailable() {
        XCTAssertEqual(MacFeatureLimits.blockChypTerminal.availability, .available)
    }

    func test_availabilityLabels() {
        XCTAssertEqual(MacFeatureAvailability.available.label, "Available")
        XCTAssertEqual(MacFeatureAvailability.limited.label, "Limited")
        XCTAssertEqual(MacFeatureAvailability.unavailable.label, "Not on Mac")
    }
}
