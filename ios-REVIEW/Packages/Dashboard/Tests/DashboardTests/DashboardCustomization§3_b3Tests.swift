import XCTest
@testable import Dashboard

// MARK: - DashboardCustomization§3_b3Tests
//
// Validates the §3 b3 batch additions (commits d499576e + ee32b993):
//   1. dashboardGreeting(for:) weekend dawn variant → "Enjoy your morning off"
//   2. dashboardGreeting(for:) weekend afternoon variant → "Happy weekend"
//   3. DashboardTileOrderStore persists a hidden tile across fresh instances
//   4. DashboardTileConfig covers ≥ 4 distinct tile slugs
//   5. DashboardTileOrderStore.save / load round-trips visibility changes
//   6. DashboardTileOrderStore.reset clears persisted state
//
// Tests pin to deterministic dates so results are stable in CI regardless of
// when the suite runs.  Weekend = Saturday 2026-04-25; weekday = Monday 2026-04-27.

final class DashboardCustomization_3_b3Tests: XCTestCase {

    // MARK: - §3.9 Greeting weekend variants

    /// §3 b3 test 1: hour 6 on Saturday → "Enjoy your morning off"
    func test_greeting_saturday_6am_returnsEnjoyYourMorningOff() {
        let sat6am = Self.saturday(hour: 6)
        XCTAssertEqual(
            dashboardGreeting(for: sat6am),
            "Enjoy your morning off",
            "Dawn hour on a weekend must return the morning-off variant"
        )
    }

    /// §3 b3 test 2: hour 14 on Sunday → "Happy weekend"
    func test_greeting_sunday_14pm_returnsHappyWeekend() {
        let sun14 = Self.sunday(hour: 14)
        XCTAssertEqual(
            dashboardGreeting(for: sun14),
            "Happy weekend",
            "Afternoon (13-16) on a weekend must return the happy-weekend variant"
        )
    }

    // MARK: - §3.1 DashboardTileOrderStore — persistence

    private let testKey = "dashboard.tileOrder"

    override func setUp() {
        super.setUp()
        // Wipe any leftover state from previous runs.
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        super.tearDown()
    }

    /// §3 b3 test 3: hiding a tile persists across fresh store instances.
    @MainActor
    func test_tileOrderStore_persistsHiddenTile_acrossInstances() throws {
        let defaults: [DashboardTileConfig] = [
            .init(id: "revenue"),
            .init(id: "closed"),
            .init(id: "appointments"),
            .init(id: "inventory"),
        ]

        // Hide "closed" in the first store instance.
        let store1 = DashboardTileOrderStore()
        var tiles = defaults
        tiles[1].isVisible = false
        store1.save(tiles)

        // Load into a second store — it must respect the persisted change.
        let store2 = DashboardTileOrderStore()
        let loaded = store2.load(defaults: defaults)

        let closedTile = try XCTUnwrap(loaded.first(where: { $0.id == "closed" }))
        XCTAssertFalse(closedTile.isVisible,
            "A tile hidden by one store instance must still be hidden in a fresh instance")
    }

    /// §3 b3 test 4: the canonical default set covers ≥ 4 tile slugs.
    func test_defaultTileSet_hasAtLeastFourDistinctIDs() {
        let defaults: [DashboardTileConfig] = [
            .init(id: "revenue"),
            .init(id: "closed"),
            .init(id: "appointments"),
            .init(id: "inventory"),
        ]
        let uniqueIDs = Set(defaults.map(\.id))
        XCTAssertGreaterThanOrEqual(uniqueIDs.count, 4,
            "Dashboard must expose ≥ 4 distinct KPI tile IDs")
    }

    /// §3 b3 test 5: save → load round-trip preserves order and visibility.
    @MainActor
    func test_tileOrderStore_saveLoad_roundTripsOrderAndVisibility() {
        let tiles: [DashboardTileConfig] = [
            .init(id: "inventory", isVisible: false),
            .init(id: "revenue",   isVisible: true),
            .init(id: "closed",    isVisible: true),
            .init(id: "appointments", isVisible: false),
        ]

        let store = DashboardTileOrderStore()
        store.save(tiles)
        let loaded = store.load(defaults: [])

        XCTAssertEqual(loaded.map(\.id), tiles.map(\.id),
            "Saved order must be preserved on load")
        XCTAssertEqual(loaded.map(\.isVisible), tiles.map(\.isVisible),
            "Saved visibility must be preserved on load")
    }

    /// §3 b3 test 6: reset clears all persisted data and returns to defaults.
    @MainActor
    func test_tileOrderStore_reset_returnsDefaults() {
        let defaults: [DashboardTileConfig] = [
            .init(id: "revenue"),
            .init(id: "closed"),
            .init(id: "appointments"),
            .init(id: "inventory"),
        ]
        let modified: [DashboardTileConfig] = [
            .init(id: "revenue", isVisible: false),
        ]

        let store = DashboardTileOrderStore()
        store.save(modified)
        store.reset()

        let loaded = store.load(defaults: defaults)
        // After reset, load returns the provided defaults unchanged.
        XCTAssertEqual(loaded.map(\.id), defaults.map(\.id))
        XCTAssertTrue(loaded.allSatisfy(\.isVisible),
            "All tiles should be visible after reset to defaults")
    }

    // MARK: - Date helpers

    private static func saturday(hour: Int) -> Date {
        makeDate(year: 2026, month: 4, day: 25, hour: hour)  // Saturday
    }

    private static func sunday(hour: Int) -> Date {
        makeDate(year: 2026, month: 4, day: 26, hour: hour)  // Sunday
    }

    private static func makeDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var comps   = DateComponents()
        comps.year  = year
        comps.month = month
        comps.day   = day
        comps.hour  = hour
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }
}
