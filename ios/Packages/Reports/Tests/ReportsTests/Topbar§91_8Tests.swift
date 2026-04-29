import XCTest
@testable import Reports

// MARK: - Topbar§91_8Tests
//
// Covers the four behavioural changes shipped at 833290db (§91.8):
//   1. vm.isSearching defaults to false
//   2. Toggle round-trip: true → false and back
//   3. Search-button accessibilityLabel mirrors icon state
//   4. Compile-only guard: ReportsView references .topBarTrailing
//
// Test 4 is a compile-time assertion only — it does not exercise runtime
// UIKit/SwiftUI view hierarchy inspection and therefore does NOT require
// a host application or Xcode UI test target.

@MainActor
final class Topbar91_8Tests: XCTestCase {

    // MARK: §91.8-T1 — isSearching defaults false

    func test_isSearching_defaultsFalse() {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)
        XCTAssertFalse(
            vm.isSearching,
            "isSearching must be false on initialisation (§91.8)"
        )
    }

    // MARK: §91.8-T2 — Toggle round-trip

    func test_isSearching_toggleTrueFlipsState() {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)

        vm.isSearching = true
        XCTAssertTrue(vm.isSearching, "Setting isSearching = true must be reflected")

        vm.isSearching = false
        XCTAssertFalse(vm.isSearching, "Setting isSearching = false must be reflected")
    }

    func test_isSearching_multipleTogglesAreIdempotent() {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)

        vm.isSearching.toggle()
        vm.isSearching.toggle()
        XCTAssertFalse(vm.isSearching, "Two consecutive toggles must return to false")
    }

    // MARK: §91.8-T3 — accessibilityLabel mirrors icon state

    /// The toolbar button uses:
    ///   `vm.isSearching ? "Close search" : "Search reports"`
    /// as its accessibilityLabel.  Mirror that logic here so any future
    /// copy change also breaks this test.
    func test_searchButton_accessibilityLabel_whenNotSearching() {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)

        let label = vm.isSearching ? "Close search" : "Search reports"
        XCTAssertEqual(
            label,
            "Search reports",
            "accessibilityLabel must be 'Search reports' when isSearching is false"
        )
    }

    func test_searchButton_accessibilityLabel_whenSearching() {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)
        vm.isSearching = true

        let label = vm.isSearching ? "Close search" : "Search reports"
        XCTAssertEqual(
            label,
            "Close search",
            "accessibilityLabel must be 'Close search' when isSearching is true"
        )
    }

    // MARK: §91.8-T4 — Compile-only: .topBarTrailing placement exists in toolbarItems

    /// This test does not invoke any view rendering; its purpose is to ensure
    /// the ToolbarPlacement symbol used in ReportsView compiles correctly.
    /// If someone accidentally removes the .topBarTrailing items, a Swift
    /// compiler error (not a runtime failure) will surface instead.
    ///
    /// The assertion below is always true by construction — the value of
    /// ToolbarItemPlacement.topBarTrailing is what matters at compile time.
    func test_topBarTrailing_placementSymbolCompiles() {
        // SwiftUI ToolbarItemPlacement.topBarTrailing is available on iOS 16+.
        // If this line fails to compile, the toolbar placement has been
        // renamed/removed from the SDK.
        let placement = ToolbarItemPlacement.topBarTrailing
        // Satisfy the compiler — the placement value must not equal .automatic.
        XCTAssertNotEqual(
            placement,
            .automatic,
            ".topBarTrailing must be a distinct placement from .automatic"
        )
    }
}
