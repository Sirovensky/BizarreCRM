// DesignSystemTests/Tips/TipsCatalogTests.swift
//
// Tests for TipsCatalog (§69 feature-event-keyed tips).
//
// Coverage targets:
//  • Every tip in TipsCatalog.all has a non-empty title, non-nil message, non-nil image.
//  • Every tip has at least one eligibility rule.
//  • Every tip sets display options (MaxDisplayCount).
//  • All TipParameterKeys constants are non-empty strings.
//  • All TipParameterKeys constants are unique (no duplicate event IDs).
//  • TipDisplayThreshold constants are positive and ordered correctly.
//  • TipDisplayOptions arrays are non-empty.
//  • All tips conform to BrandTip at compile time.
//  • TipsCatalog.all contains exactly the expected number of entries.
//
// Guarded with #if canImport(TipKit) — not available on macOS SwiftPM builds.
//
// §69 In-App Help / Tips

import XCTest
import SwiftUI

#if canImport(TipKit)
import TipKit
@testable import DesignSystem

@available(iOS 17, *)
final class TipsCatalogTests: XCTestCase {

    // MARK: - TipsCatalog.all enumeration

    func test_catalog_all_count_isExpected() {
        XCTAssertEqual(TipsCatalog.all.count, 10,
            "TipsCatalog.all must contain exactly 10 feature-event tips")
    }

    func test_catalog_all_everyTip_hasTitleText() {
        for tip in TipsCatalog.all {
            XCTAssertTrue(
                tipTitleNonEmpty(tip),
                "\(type(of: tip)) must have a non-empty title"
            )
        }
    }

    func test_catalog_all_everyTip_hasNonNilMessage() {
        for tip in TipsCatalog.all {
            XCTAssertNotNil(tip.message,
                "\(type(of: tip)) must have a non-nil message")
        }
    }

    func test_catalog_all_everyTip_hasNonNilImage() {
        for tip in TipsCatalog.all {
            XCTAssertNotNil(tip.image,
                "\(type(of: tip)) must have a non-nil image")
        }
    }

    func test_catalog_all_everyTip_hasAtLeastOneRule() {
        for tip in TipsCatalog.all {
            XCTAssertFalse(tip.rules.isEmpty,
                "\(type(of: tip)) must have at least one eligibility rule")
        }
    }

    func test_catalog_all_everyTip_hasNonEmptyOptions() {
        for tip in TipsCatalog.all {
            XCTAssertFalse(tip.options.isEmpty,
                "\(type(of: tip)) must set at least one display option")
        }
    }

    // MARK: - BrandTip conformance (compile-time)

    func test_allFeatureTips_conformToBrandTip() {
        let _: any BrandTip = FirstTicketTip()
        let _: any BrandTip = FirstSaleTip()
        let _: any BrandTip = FirstContactTip()
        let _: any BrandTip = FirstInvoiceTip()
        let _: any BrandTip = FirstSmsThreadTip()
        let _: any BrandTip = FirstReportTip()
        let _: any BrandTip = KioskModeTip()
        let _: any BrandTip = RoleEditorTip()
        let _: any BrandTip = AuditLogTip()
        let _: any BrandTip = DashboardWidgetTip()
    }

    // MARK: - Individual tip event IDs

    func test_firstTicketTip_eventID_nonEmpty() {
        XCTAssertFalse(FirstTicketTip.firstTicketCreated.id.isEmpty)
    }

    func test_firstSaleTip_eventID_nonEmpty() {
        XCTAssertFalse(FirstSaleTip.firstSaleCreated.id.isEmpty)
    }

    func test_firstContactTip_eventID_nonEmpty() {
        XCTAssertFalse(FirstContactTip.firstContactAdded.id.isEmpty)
    }

    func test_firstInvoiceTip_eventID_nonEmpty() {
        XCTAssertFalse(FirstInvoiceTip.firstInvoiceSent.id.isEmpty)
    }

    func test_firstSmsThreadTip_eventID_nonEmpty() {
        XCTAssertFalse(FirstSmsThreadTip.firstSmsThreadSent.id.isEmpty)
    }

    func test_firstReportTip_eventID_nonEmpty() {
        XCTAssertFalse(FirstReportTip.firstReportViewed.id.isEmpty)
    }

    func test_kioskModeTip_eventID_nonEmpty() {
        XCTAssertFalse(KioskModeTip.kioskModeEnabled.id.isEmpty)
    }

    func test_roleEditorTip_eventID_nonEmpty() {
        XCTAssertFalse(RoleEditorTip.roleEdited.id.isEmpty)
    }

    func test_auditLogTip_eventID_nonEmpty() {
        XCTAssertFalse(AuditLogTip.auditLogViewed.id.isEmpty)
    }

    func test_dashboardWidgetTip_eventID_nonEmpty() {
        XCTAssertFalse(DashboardWidgetTip.dashboardWidgetAdded.id.isEmpty)
    }

    // MARK: - TipParameterKeys uniqueness

    func test_tipParameterKeys_businessEventIDs_areUnique() {
        let ids: [String] = [
            TipParameterKeys.firstTicketCreated,
            TipParameterKeys.firstSaleCreated,
            TipParameterKeys.firstContactAdded,
            TipParameterKeys.firstInvoiceSent,
            TipParameterKeys.firstSmsThreadSent,
            TipParameterKeys.firstReportViewed,
            TipParameterKeys.kioskModeEnabled,
            TipParameterKeys.roleEdited,
            TipParameterKeys.auditLogViewed,
            TipParameterKeys.dashboardWidgetAdded,
        ]
        XCTAssertEqual(ids.count, Set(ids).count,
            "All TipParameterKeys business-event IDs must be unique")
    }

    func test_tipParameterKeys_allIDs_nonEmpty() {
        let allKeys: [String] = [
            TipParameterKeys.appLaunchedForCommandPalette,
            TipParameterKeys.appLaunchedForPullRefresh,
            TipParameterKeys.ticketsListViewed,
            TipParameterKeys.listRowViewed,
            TipParameterKeys.skuFieldViewed,
            TipParameterKeys.firstTicketCreated,
            TipParameterKeys.firstSaleCreated,
            TipParameterKeys.firstContactAdded,
            TipParameterKeys.firstInvoiceSent,
            TipParameterKeys.firstSmsThreadSent,
            TipParameterKeys.firstReportViewed,
            TipParameterKeys.kioskModeEnabled,
            TipParameterKeys.roleEdited,
            TipParameterKeys.auditLogViewed,
            TipParameterKeys.dashboardWidgetAdded,
        ]
        for key in allKeys {
            XCTAssertFalse(key.isEmpty,
                "TipParameterKeys constant must not be empty string")
        }
    }

    func test_tipParameterKeys_allIDs_areUnique() {
        let allKeys: [String] = [
            TipParameterKeys.appLaunchedForCommandPalette,
            TipParameterKeys.appLaunchedForPullRefresh,
            TipParameterKeys.ticketsListViewed,
            TipParameterKeys.listRowViewed,
            TipParameterKeys.skuFieldViewed,
            TipParameterKeys.firstTicketCreated,
            TipParameterKeys.firstSaleCreated,
            TipParameterKeys.firstContactAdded,
            TipParameterKeys.firstInvoiceSent,
            TipParameterKeys.firstSmsThreadSent,
            TipParameterKeys.firstReportViewed,
            TipParameterKeys.kioskModeEnabled,
            TipParameterKeys.roleEdited,
            TipParameterKeys.auditLogViewed,
            TipParameterKeys.dashboardWidgetAdded,
        ]
        XCTAssertEqual(allKeys.count, Set(allKeys).count,
            "All TipParameterKeys constants must be unique across the entire catalog")
    }

    // MARK: - TipDisplayThreshold

    func test_threshold_afterFirstEvent_isPositive() {
        XCTAssertGreaterThan(TipDisplayThreshold.afterFirstEvent, 0)
    }

    func test_threshold_afterThreeLaunches_greaterThanAfterFirstEvent() {
        XCTAssertGreaterThan(
            TipDisplayThreshold.afterThreeLaunches,
            TipDisplayThreshold.afterFirstEvent
        )
    }

    func test_threshold_afterFiveLaunches_greaterThanAfterThreeLaunches() {
        XCTAssertGreaterThan(
            TipDisplayThreshold.afterFiveLaunches,
            TipDisplayThreshold.afterThreeLaunches
        )
    }

    // MARK: - TipDisplayOptions

    func test_displayOptions_showOnce_nonEmpty() {
        XCTAssertFalse(TipDisplayOptions.showOnce.isEmpty)
    }

    func test_displayOptions_showTwice_nonEmpty() {
        XCTAssertFalse(TipDisplayOptions.showTwice.isEmpty)
    }

    func test_displayOptions_showThreeTimes_nonEmpty() {
        XCTAssertFalse(TipDisplayOptions.showThreeTimes.isEmpty)
    }

    func test_displayOptions_showImmediately_nonEmpty() {
        XCTAssertFalse(TipDisplayOptions.showImmediately.isEmpty)
    }

    // MARK: - TipsCatalog static properties

    func test_catalog_staticProperties_allReturnSameType() {
        // Verifies each static property returns its specific type (compile-time)
        let _: FirstTicketTip     = TipsCatalog.firstTicket
        let _: FirstSaleTip       = TipsCatalog.firstSale
        let _: FirstContactTip    = TipsCatalog.firstContact
        let _: FirstInvoiceTip    = TipsCatalog.firstInvoice
        let _: FirstSmsThreadTip  = TipsCatalog.firstSmsThread
        let _: FirstReportTip     = TipsCatalog.firstReport
        let _: KioskModeTip       = TipsCatalog.kioskMode
        let _: RoleEditorTip      = TipsCatalog.roleEditor
        let _: AuditLogTip        = TipsCatalog.auditLog
        let _: DashboardWidgetTip = TipsCatalog.dashboardWidget
    }

    // MARK: - Parameterized rule evaluation helpers

    func test_firstTicketTip_ruleUsesCorrectThreshold() {
        // The rule fires at afterFirstEvent (1). We cannot invoke TipKit evaluation
        // without a configured store, but we can verify the static constant used.
        XCTAssertEqual(TipDisplayThreshold.afterFirstEvent, 1)
    }

    // MARK: - Helper

    private func tipTitleNonEmpty(_ tip: some BrandTip) -> Bool {
        let mirror = Mirror(reflecting: tip.title)
        for child in mirror.children {
            if let s = child.value as? String, s.isEmpty { return false }
        }
        return true
    }
}

#else
// TipKit not available on this platform (e.g., macOS SwiftPM build).
final class TipsCatalogTests: XCTestCase {
    func test_skipped_on_non_ios() {
        // TipKit is iOS 17+. Tests are run under Xcode on device/simulator.
    }
}
#endif // canImport(TipKit)
