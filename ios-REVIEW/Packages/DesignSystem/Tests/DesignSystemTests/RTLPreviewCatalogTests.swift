// DesignSystemTests/RTLPreviewCatalogTests.swift
//
// Tests for RTLPreviewCatalog — enforces minimum screen coverage
// and validates catalog entry integrity.
//
// §27 RTL layout checks

import XCTest
@testable import DesignSystem

final class RTLPreviewCatalogTests: XCTestCase {

    // MARK: - Minimum coverage

    func test_catalog_hasAtLeastTenScreens() {
        XCTAssertGreaterThanOrEqual(
            RTLPreviewCatalog.screens.count,
            10,
            "RTLPreviewCatalog must list at least 10 screens; found \(RTLPreviewCatalog.screens.count)"
        )
    }

    // MARK: - Entry integrity

    func test_allEntries_haveNonEmptyID() {
        for entry in RTLPreviewCatalog.screens {
            XCTAssertFalse(
                entry.id.isEmpty,
                "RTLCatalogEntry '\(entry.displayName)' has an empty id"
            )
        }
    }

    func test_allEntries_haveNonEmptyDisplayName() {
        for entry in RTLPreviewCatalog.screens {
            XCTAssertFalse(
                entry.displayName.isEmpty,
                "RTLCatalogEntry id='\(entry.id)' has an empty displayName"
            )
        }
    }

    func test_allEntries_haveNonEmptyPackage() {
        for entry in RTLPreviewCatalog.screens {
            XCTAssertFalse(
                entry.package.isEmpty,
                "RTLCatalogEntry '\(entry.id)' has an empty package"
            )
        }
    }

    func test_allEntries_haveUniqueIDs() {
        let ids = RTLPreviewCatalog.screens.map(\.id)
        let uniqueIDs = Set(ids)
        XCTAssertEqual(
            ids.count,
            uniqueIDs.count,
            "RTLPreviewCatalog has duplicate entry IDs: \(ids.filter { id in ids.filter { $0 == id }.count > 1 })"
        )
    }

    // MARK: - UI-tested screens

    func test_fourKeyScreens_haveUITests() {
        // Verify the four smoke-tested screens exist in the catalog.
        let smokeTestedIDs: Set<String> = [
            "LoginFlowView",
            "DashboardView",
            "TicketListView",
            "PosView"
        ]
        let catalogIDs = Set(RTLPreviewCatalog.screens.map(\.id))
        for id in smokeTestedIDs {
            XCTAssertTrue(
                catalogIDs.contains(id),
                "Expected smoke-tested screen '\(id)' to be listed in RTLPreviewCatalog"
            )
        }
    }

    func test_smokeTestedScreens_flaggedWithHasUITest() {
        let smokeTestedIDs: Set<String> = [
            "LoginFlowView",
            "DashboardView",
            "TicketListView",
            "PosView"
        ]
        for entry in RTLPreviewCatalog.screens where smokeTestedIDs.contains(entry.id) {
            XCTAssertTrue(
                entry.hasUITest,
                "'\(entry.id)' has an XCUITest in RTLSmokeTests.swift but hasUITest is false in the catalog"
            )
        }
    }

    // MARK: - Helpers

    func test_missingUITests_returnsNonSmokeTestedScreens() {
        let missing = RTLPreviewCatalog.missingUITests
        let smokeTestedIDs: Set<String> = [
            "LoginFlowView",
            "DashboardView",
            "TicketListView",
            "PosView"
        ]
        for entry in missing {
            XCTAssertFalse(
                smokeTestedIDs.contains(entry.id),
                "'\(entry.id)' appears in missingUITests but is listed as smoke-tested"
            )
        }
    }
}
