import XCTest
import SwiftUI
@testable import Core

// §63 — Non-nil view init tests.
//
// These tests verify that all public view types can be instantiated without
// crashing. They do not render views (no UIKit/SnapshotKit dependency) — they
// just ensure the init paths are reachable and the body property compiles.
//
// SwiftUI views are value types so `body` is computed lazily. We verify the
// init contract: all stored properties are non-nil / valid after construction.

@MainActor
final class ViewInitTests: XCTestCase {

    // MARK: — CoreErrorStateView

    func testCoreErrorStateView_init_noRetry() {
        let sut = CoreErrorStateView(state: .network)
        XCTAssertEqual(sut.state, .network)
        XCTAssertNil(sut.onRetry)
    }

    func testCoreErrorStateView_init_withRetry() {
        var called = false
        let sut = CoreErrorStateView(state: .offline) { called = true }
        XCTAssertEqual(sut.state, .offline)
        sut.onRetry?()
        XCTAssertTrue(called)
    }

    func testCoreErrorStateView_allStates_initSucceeds() {
        let states: [CoreErrorState] = [
            .network,
            .server(status: 500, message: nil),
            .server(status: 503, message: "down"),
            .unauthorized,
            .forbidden,
            .notFound,
            .offline,
            .validation([]),
            .validation(["email", "phone"]),
            .rateLimited(retrySeconds: nil),
            .rateLimited(retrySeconds: 30),
            .unknown
        ]
        for state in states {
            let sut = CoreErrorStateView(state: state)
            XCTAssertEqual(sut.state, state, "Init failed for state: \(state)")
        }
    }

    // MARK: — CoreErrorStateScreen

    func testCoreErrorStateScreen_init() {
        let sut = CoreErrorStateScreen(state: .server(status: 500, message: nil))
        XCTAssertEqual(sut.state, .server(status: 500, message: nil))
        XCTAssertNil(sut.onRetry)
    }

    func testCoreErrorStateScreen_init_withRetry() {
        let sut = CoreErrorStateScreen(state: .network) { }
        XCTAssertEqual(sut.state, .network)
        XCTAssertNotNil(sut.onRetry)
    }

    // MARK: — EmptyStateView

    func testEmptyStateView_init_minimalArgs() {
        let sut = EmptyStateView(symbol: "tray", title: "Empty")
        XCTAssertEqual(sut.config.symbol, "tray")
        XCTAssertEqual(sut.config.title, "Empty")
        XCTAssertNil(sut.config.subtitle)
        XCTAssertNil(sut.config.ctaLabel)
        XCTAssertNil(sut.onCTA)
    }

    func testEmptyStateView_init_allArgs() {
        var tapped = false
        let sut = EmptyStateView(
            symbol: "folder",
            title: "No Files",
            subtitle: "Upload to get started",
            ctaLabel: "Upload",
            onCTA: { tapped = true }
        )
        XCTAssertEqual(sut.config.symbol, "folder")
        XCTAssertEqual(sut.config.title, "No Files")
        XCTAssertEqual(sut.config.subtitle, "Upload to get started")
        XCTAssertEqual(sut.config.ctaLabel, "Upload")
        sut.onCTA?()
        XCTAssertTrue(tapped)
    }

    func testEmptyStateView_init_viaConfig() {
        let config = EmptyStateView.Config(
            symbol: "bell.slash",
            title: "No Notifications",
            subtitle: "All caught up!",
            ctaLabel: nil
        )
        let sut = EmptyStateView(config: config)
        XCTAssertEqual(sut.config.symbol, "bell.slash")
        XCTAssertEqual(sut.config.title, "No Notifications")
        XCTAssertNil(sut.onCTA)
    }

    // MARK: — LoadingStateView — SkeletonListView

    func testSkeletonListView_init_default() {
        let sut = SkeletonListView()
        XCTAssertEqual(sut.rowCount, 4)
    }

    func testSkeletonListView_init_customRowCount() {
        let sut = SkeletonListView(rowCount: 7)
        XCTAssertEqual(sut.rowCount, 7)
    }

    func testSkeletonListView_init_clampsZeroToOne() {
        let sut = SkeletonListView(rowCount: 0)
        XCTAssertEqual(sut.rowCount, 1)
    }

    func testSkeletonListView_init_clampsNegativeToOne() {
        let sut = SkeletonListView(rowCount: -5)
        XCTAssertEqual(sut.rowCount, 1)
    }

    // MARK: — LoadingStateView — SkeletonRowView

    func testSkeletonRowView_init_defaults() {
        let sut = SkeletonRowView()
        XCTAssertEqual(sut.titleWidthFraction, 0.6)
        XCTAssertEqual(sut.subtitleWidthFraction, 0.4)
    }

    func testSkeletonRowView_init_customFractions() {
        let sut = SkeletonRowView(titleWidthFraction: 0.8, subtitleWidthFraction: 0.0)
        XCTAssertEqual(sut.titleWidthFraction, 0.8)
        XCTAssertEqual(sut.subtitleWidthFraction, 0.0)
    }

    // MARK: — LoadingStateView — LoadingSpinnerView

    func testLoadingSpinnerView_init_noLabel() {
        let sut = LoadingSpinnerView()
        XCTAssertNil(sut.label)
    }

    func testLoadingSpinnerView_init_withLabel() {
        let sut = LoadingSpinnerView(label: "Fetching…")
        XCTAssertEqual(sut.label, "Fetching…")
    }

    // MARK: — OfflineStateView

    func testOfflineStateView_init_noCacheNoRetry() {
        let sut = OfflineStateView()
        XCTAssertNil(sut.cachedAt)
        XCTAssertNil(sut.onRetry)
    }

    func testOfflineStateView_init_withCache() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let sut = OfflineStateView(cachedAt: date)
        XCTAssertEqual(sut.cachedAt, date)
    }

    func testOfflineStateView_init_withRetry() {
        var tapped = false
        let sut = OfflineStateView(onRetry: { tapped = true })
        sut.onRetry?()
        XCTAssertTrue(tapped)
    }

    func testOfflineStateView_init_withCacheAndRetry() {
        let date = Date()
        var tapped = false
        let sut = OfflineStateView(cachedAt: date) { tapped = true }
        XCTAssertNotNil(sut.cachedAt)
        sut.onRetry?()
        XCTAssertTrue(tapped)
    }
}
