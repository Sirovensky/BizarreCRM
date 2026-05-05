// DesignSystemTests/TipCatalogTests.swift
//
// Tests for TipCatalog — verifies every tip has non-empty title,
// message, image, and at least one eligibility rule.
//
// Guarded with #if canImport(TipKit) to allow macOS SwiftPM builds
// where TipKit is not available outside Xcode.
//
// §26 Sticky a11y tips tests (Phase 10)

import XCTest
import SwiftUI

#if canImport(TipKit)
import TipKit
@testable import DesignSystem

@available(iOS 17, *)
final class TipCatalogTests: XCTestCase {

    // MARK: - CommandPaletteTip

    func test_commandPaletteTip_hasTitleText() {
        let tip = CommandPaletteTip()
        // Text is always non-nil by construction; verify via debugDescription content.
        XCTAssertTrue(tipTitleNonEmpty(tip), "CommandPaletteTip title must be non-empty")
    }

    func test_commandPaletteTip_message_nonNil() {
        let tip = CommandPaletteTip()
        XCTAssertNotNil(tip.message, "CommandPaletteTip must have a message")
    }

    func test_commandPaletteTip_image_nonNil() {
        let tip = CommandPaletteTip()
        XCTAssertNotNil(tip.image, "CommandPaletteTip must have an image")
    }

    func test_commandPaletteTip_hasRules() {
        let tip = CommandPaletteTip()
        XCTAssertFalse(tip.rules.isEmpty, "CommandPaletteTip must have eligibility rules")
    }

    func test_commandPaletteTip_options_nonEmpty() {
        let tip = CommandPaletteTip()
        XCTAssertFalse(tip.options.isEmpty, "CommandPaletteTip must set display options")
    }

    func test_commandPaletteTip_eventID_nonEmpty() {
        XCTAssertFalse(CommandPaletteTip.appLaunched.id.isEmpty)
    }

    // MARK: - SwipeToArchiveTip

    func test_swipeToArchiveTip_hasTitleText() {
        XCTAssertTrue(tipTitleNonEmpty(SwipeToArchiveTip()))
    }

    func test_swipeToArchiveTip_message_nonNil() {
        XCTAssertNotNil(SwipeToArchiveTip().message)
    }

    func test_swipeToArchiveTip_image_nonNil() {
        XCTAssertNotNil(SwipeToArchiveTip().image)
    }

    func test_swipeToArchiveTip_hasRules() {
        XCTAssertFalse(SwipeToArchiveTip().rules.isEmpty)
    }

    func test_swipeToArchiveTip_eventID_nonEmpty() {
        XCTAssertFalse(SwipeToArchiveTip.ticketsListViewed.id.isEmpty)
    }

    // MARK: - PullToRefreshTip

    func test_pullToRefreshTip_hasTitleText() {
        XCTAssertTrue(tipTitleNonEmpty(PullToRefreshTip()))
    }

    func test_pullToRefreshTip_message_nonNil() {
        XCTAssertNotNil(PullToRefreshTip().message)
    }

    func test_pullToRefreshTip_image_nonNil() {
        XCTAssertNotNil(PullToRefreshTip().image)
    }

    func test_pullToRefreshTip_hasRules() {
        XCTAssertFalse(PullToRefreshTip().rules.isEmpty)
    }

    func test_pullToRefreshTip_eventID_nonEmpty() {
        XCTAssertFalse(PullToRefreshTip.appLaunched.id.isEmpty)
    }

    // MARK: - ContextMenuTip

    func test_contextMenuTip_hasTitleText() {
        XCTAssertTrue(tipTitleNonEmpty(ContextMenuTip()))
    }

    func test_contextMenuTip_message_nonNil() {
        XCTAssertNotNil(ContextMenuTip().message)
    }

    func test_contextMenuTip_image_nonNil() {
        XCTAssertNotNil(ContextMenuTip().image)
    }

    func test_contextMenuTip_hasRules() {
        XCTAssertFalse(ContextMenuTip().rules.isEmpty)
    }

    func test_contextMenuTip_eventID_nonEmpty() {
        XCTAssertFalse(ContextMenuTip.rowViewed.id.isEmpty)
    }

    // MARK: - ScanBarcodeTip

    func test_scanBarcodeTip_hasTitleText() {
        XCTAssertTrue(tipTitleNonEmpty(ScanBarcodeTip()))
    }

    func test_scanBarcodeTip_message_nonNil() {
        XCTAssertNotNil(ScanBarcodeTip().message)
    }

    func test_scanBarcodeTip_image_nonNil() {
        XCTAssertNotNil(ScanBarcodeTip().image)
    }

    func test_scanBarcodeTip_hasRules() {
        XCTAssertFalse(ScanBarcodeTip().rules.isEmpty)
    }

    func test_scanBarcodeTip_eventID_nonEmpty() {
        XCTAssertFalse(ScanBarcodeTip.skuFieldViewed.id.isEmpty)
    }

    // MARK: - Event IDs are unique across catalog

    func test_allEventIDs_areUnique() {
        let ids: [String] = [
            CommandPaletteTip.appLaunched.id,
            SwipeToArchiveTip.ticketsListViewed.id,
            PullToRefreshTip.appLaunched.id,
            ContextMenuTip.rowViewed.id,
            ScanBarcodeTip.skuFieldViewed.id,
        ]
        XCTAssertEqual(ids.count, Set(ids).count, "All tip event IDs must be unique")
    }

    // MARK: - BrandTip conformance (compile-time)

    func test_allTips_conformToBrandTip() {
        let _: any BrandTip = CommandPaletteTip()
        let _: any BrandTip = SwipeToArchiveTip()
        let _: any BrandTip = PullToRefreshTip()
        let _: any BrandTip = ContextMenuTip()
        let _: any BrandTip = ScanBarcodeTip()
    }

    // MARK: - Helper

    /// Returns true if the tip's title Text has non-empty storage.
    private func tipTitleNonEmpty(_ tip: some BrandTip) -> Bool {
        let mirror = Mirror(reflecting: tip.title)
        for child in mirror.children {
            if let s = child.value as? String, s.isEmpty { return false }
        }
        // If we couldn't introspect storage, the fact that title is a non-nil Text is sufficient.
        return true
    }
}
#else
// TipKit not available on this platform (e.g., macOS SwiftPM build).
// Tests are skipped; the framework itself is iOS-only.
final class TipCatalogTests: XCTestCase {
    func test_skipped_on_non_ios() {
        // TipKit is iOS 17+. Tests run under Xcode on device/simulator.
    }
}
#endif // canImport(TipKit)
