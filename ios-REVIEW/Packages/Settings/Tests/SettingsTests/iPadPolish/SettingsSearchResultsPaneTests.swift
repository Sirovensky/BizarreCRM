import Testing
import Foundation
@testable import Settings

// MARK: - SettingsSearchResultsPane logic tests
//
// UI rendering is not testable in a pure Swift package test target (no UIKit
// host), so these tests cover the SettingsSearchViewModel integration that
// SettingsSearchResultsPane is driven by — query debounce, result population,
// clear, and the SettingsEntry model invariants used by the results rows.

@Suite("SettingsSearchResultsPane (logic)")
struct SettingsSearchResultsPaneTests {

    // MARK: - SettingsSearchViewModel integration

    @Test("Initial state: query empty, results empty, not searching")
    @MainActor
    func initialState() {
        let vm = SettingsSearchViewModel(debounceInterval: 0)
        #expect(vm.query == "")
        #expect(vm.results.isEmpty)
        #expect(!vm.isSearching)
    }

    @Test("Setting empty query keeps results empty")
    @MainActor
    func emptyQueryKeepsResultsEmpty() {
        let vm = SettingsSearchViewModel(debounceInterval: 0)
        vm.query = "   "
        #expect(vm.results.isEmpty)
    }

    @Test("clear() resets query, results, and isSearching")
    @MainActor
    func clearResetsAllState() {
        let vm = SettingsSearchViewModel(debounceInterval: 0)
        vm.query = "something"
        vm.clear()
        #expect(vm.query.isEmpty)
        #expect(vm.results.isEmpty)
        #expect(!vm.isSearching)
    }

    @Test("Non-empty query sets isSearching to true")
    @MainActor
    func nonEmptyQuerySetsIsSearching() {
        let vm = SettingsSearchViewModel(debounceInterval: 60) // long delay so it stays "searching"
        vm.query = "profile"
        #expect(vm.isSearching)
    }

    @Test("Debounce resolves immediately with zero interval")
    @MainActor
    func debounceResolvesWithZeroInterval() async {
        let vm = SettingsSearchViewModel(debounceInterval: 0)
        vm.query = "profile"
        // Allow one run-loop cycle for the task to kick in
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!vm.results.isEmpty)
    }

    @Test("Results contain profile entry when querying 'profile'")
    @MainActor
    func resultsContainProfile() async {
        let vm = SettingsSearchViewModel(debounceInterval: 0)
        vm.query = "profile"
        try? await Task.sleep(for: .milliseconds(50))
        #expect(vm.results.contains { $0.id == "profile" })
    }

    @Test("Nonsense query returns empty results")
    @MainActor
    func nonsenseQueryReturnsEmpty() async {
        let vm = SettingsSearchViewModel(debounceInterval: 0)
        vm.query = "xyzzy_not_a_real_setting"
        try? await Task.sleep(for: .milliseconds(50))
        #expect(vm.results.isEmpty)
    }

    @Test("isSearching becomes false after debounce resolves")
    @MainActor
    func isSearchingFalseAfterResolve() async {
        let vm = SettingsSearchViewModel(debounceInterval: 0)
        vm.query = "tax"
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!vm.isSearching)
    }

    @Test("Replacing query before debounce cancels previous search")
    @MainActor
    func replacingQueryCancelsPrevious() async {
        let vm = SettingsSearchViewModel(debounceInterval: 0.05)
        vm.query = "pro"
        vm.query = "tax"     // replaces the first
        try? await Task.sleep(for: .milliseconds(200))
        // Should reflect "tax" results, not "pro" results
        #expect(vm.results.contains { $0.id == "company.tax" })
    }

    // MARK: - SettingsEntry model invariants for row rendering

    @Test("Each SettingsEntry breadcrumbDisplay joins with ›")
    func breadcrumbDisplayFormat() {
        let entry = SettingsEntry(
            id: "test",
            title: "Test",
            path: "settings.test",
            keywords: [],
            iconSystemName: "gear",
            breadcrumb: ["Foo", "Bar"]
        )
        #expect(entry.breadcrumbDisplay == "Foo › Bar")
    }

    @Test("Single-segment breadcrumb has no separator")
    func singleSegmentBreadcrumb() {
        let entry = SettingsEntry(
            id: "test",
            title: "Test",
            path: "settings.test",
            keywords: [],
            iconSystemName: "gear",
            breadcrumb: ["Profile"]
        )
        #expect(entry.breadcrumbDisplay == "Profile")
    }

    @Test("Empty breadcrumb returns empty string")
    func emptyBreadcrumb() {
        let entry = SettingsEntry(
            id: "test",
            title: "Test",
            path: "settings.test",
            keywords: [],
            iconSystemName: "gear",
            breadcrumb: []
        )
        #expect(entry.breadcrumbDisplay.isEmpty)
    }

    @Test("All entries in search index have a non-empty iconSystemName")
    func allIndexEntriesHaveIcon() {
        for entry in SettingsSearchIndex.entries {
            #expect(!entry.iconSystemName.isEmpty,
                    "Entry '\(entry.id)' has empty iconSystemName")
        }
    }

    @Test("All entries in search index have a non-empty path")
    func allIndexEntriesHavePath() {
        for entry in SettingsSearchIndex.entries {
            #expect(!entry.path.isEmpty,
                    "Entry '\(entry.id)' has empty path")
        }
    }

    // MARK: - SettingsSearchIndex.filter used by pane

    @Test("filter with 'appearance' finds appearance entry")
    func filterAppearance() {
        let results = SettingsSearchIndex.filter(query: "appearance")
        #expect(results.contains { $0.id == "appearance" })
    }

    @Test("filter with 'audit' finds auditLogs entry")
    func filterAuditLogs() {
        let results = SettingsSearchIndex.filter(query: "audit")
        #expect(results.contains { $0.id == "auditLogs" })
    }

    @Test("filter with 'kiosk' finds kioskMode entry")
    func filterKiosk() {
        let results = SettingsSearchIndex.filter(query: "kiosk")
        #expect(results.contains { $0.id == "kioskMode" })
    }

    @Test("filter with 'printer' finds hardware.printers entry")
    func filterPrinters() {
        let results = SettingsSearchIndex.filter(query: "printer")
        #expect(results.contains { $0.id == "hardware.printers" })
    }
}
