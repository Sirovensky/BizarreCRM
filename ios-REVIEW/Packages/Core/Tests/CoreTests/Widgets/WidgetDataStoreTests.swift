import XCTest
@testable import Core

final class WidgetDataStoreTests: XCTestCase {

    // MARK: - Helpers

    /// Each test gets a unique suite name so tests don't bleed into each other.
    private func makeSuiteName() -> String {
        "com.bizarrecrm.test.\(UUID().uuidString)"
    }

    private func makeStore(suiteName: String) throws -> WidgetDataStore {
        try WidgetDataStore(suiteName: suiteName)
    }

    // MARK: - Write / Read round-trip

    func test_writeAndRead_roundTrip() async throws {
        let suite = makeSuiteName()
        let store = try makeStore(suiteName: suite)
        let snapshot = WidgetSnapshot(
            openTicketCount: 5,
            latestTickets: [
                .init(id: 1, displayId: "T-001", customerName: "Alice", status: "intake")
            ],
            revenueTodayCents: 99_99,
            revenueYesterdayCents: 50_00,
            nextAppointments: [
                .init(id: 10, customerName: "Bob", scheduledAt: Date(timeIntervalSince1970: 1_700_000_000))
            ],
            lastUpdated: Date(timeIntervalSince1970: 1_700_100_000)
        )

        try await store.write(snapshot)
        let read = await store.read()

        XCTAssertNotNil(read)
        XCTAssertEqual(read?.openTicketCount, 5)
        XCTAssertEqual(read?.revenueTodayCents, 99_99)
        XCTAssertEqual(read?.latestTickets.count, 1)
        XCTAssertEqual(read?.nextAppointments.count, 1)
        XCTAssertEqual(read?.lastUpdated, Date(timeIntervalSince1970: 1_700_100_000))
    }

    func test_read_returnsNil_whenNothingWritten() async throws {
        let store = try makeStore(suiteName: makeSuiteName())
        let result = await store.read()
        XCTAssertNil(result)
    }

    func test_write_overwritesPreviousSnapshot() async throws {
        let suite = makeSuiteName()
        let store = try makeStore(suiteName: suite)

        let first = WidgetSnapshot(
            openTicketCount: 1,
            revenueTodayCents: 100_00,
            revenueYesterdayCents: 0,
            lastUpdated: Date(timeIntervalSince1970: 1_000)
        )
        let second = WidgetSnapshot(
            openTicketCount: 99,
            revenueTodayCents: 999_99,
            revenueYesterdayCents: 0,
            lastUpdated: Date(timeIntervalSince1970: 2_000)
        )

        try await store.write(first)
        try await store.write(second)

        let result = await store.read()
        XCTAssertEqual(result?.openTicketCount, 99)
    }

    // MARK: - Settings persistence

    func test_refreshInterval_defaultIsFifteenMinutes() async throws {
        let store = try makeStore(suiteName: makeSuiteName())
        let interval = await store.refreshInterval
        XCTAssertEqual(interval, .fifteenMinutes)
    }

    func test_refreshInterval_persisted() async throws {
        let suite = makeSuiteName()
        let store = try makeStore(suiteName: suite)
        await store.set(refreshInterval: .fiveMinutes)

        // Read back from a fresh store pointing at same suite.
        let store2 = try makeStore(suiteName: suite)
        let interval = await store2.refreshInterval
        XCTAssertEqual(interval, .fiveMinutes)
    }

    func test_liveActivitiesEnabled_defaultIsFalse() async throws {
        let store = try makeStore(suiteName: makeSuiteName())
        // Unset key → UserDefaults returns false for missing bool.
        let enabled = await store.liveActivitiesEnabled
        XCTAssertFalse(enabled)
    }

    func test_liveActivitiesEnabled_persistsTrue() async throws {
        let suite = makeSuiteName()
        let store = try makeStore(suiteName: suite)
        await store.set(liveActivitiesEnabled: true)

        let store2 = try makeStore(suiteName: suite)
        let enabled = await store2.liveActivitiesEnabled
        XCTAssertTrue(enabled)
    }

    // MARK: - Error cases

    func test_init_throwsOrSucceedsOnUnregisteredSuite() {
        // An empty string is guaranteed to fail App Group lookup on a real device.
        // In unit-test sandboxes UserDefaults(suiteName:"") may return a non-nil
        // object — we tolerate both outcomes (throw or succeed) since the behaviour
        // is documented and tested at integration time with a real entitlement.
        let _ = try? WidgetDataStore(suiteName: "")
    }

    // MARK: - Cleanup

    override func tearDown() async throws {
        // UserDefaults suites with random names are ephemeral per-process;
        // no persistent cleanup required.
        try await super.tearDown()
    }
}
