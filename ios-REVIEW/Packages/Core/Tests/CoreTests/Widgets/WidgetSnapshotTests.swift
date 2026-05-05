import XCTest
@testable import Core

final class WidgetSnapshotTests: XCTestCase {

    // MARK: - Round-trip encode / decode

    func test_roundTrip_emptySnapshot() throws {
        let snapshot = WidgetSnapshot(
            openTicketCount: 0,
            latestTickets: [],
            revenueTodayCents: 0,
            revenueYesterdayCents: 0,
            nextAppointments: [],
            lastUpdated: Date(timeIntervalSince1970: 0)
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func test_roundTrip_fullSnapshot() throws {
        let ticket = WidgetSnapshot.TicketSummary(
            id: 1,
            displayId: "T-001",
            customerName: "Alice",
            status: "in_progress",
            deviceSummary: "iPhone 15"
        )
        let appt = WidgetSnapshot.AppointmentSummary(
            id: 10,
            customerName: "Bob",
            scheduledAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let snapshot = WidgetSnapshot(
            openTicketCount: 7,
            latestTickets: [ticket],
            revenueTodayCents: 123_456,
            revenueYesterdayCents: 98_000,
            nextAppointments: [appt],
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.openTicketCount, 7)
        XCTAssertEqual(decoded.latestTickets.count, 1)
        XCTAssertEqual(decoded.nextAppointments.count, 1)
    }

    // MARK: - Prefix limits

    func test_latestTickets_cappedAtTen() {
        let tickets = (0..<20).map { i in
            WidgetSnapshot.TicketSummary(
                id: Int64(i),
                displayId: "T-\(i)",
                customerName: "C\(i)",
                status: "intake"
            )
        }
        let snapshot = WidgetSnapshot(
            openTicketCount: 20,
            latestTickets: tickets,
            revenueTodayCents: 0,
            revenueYesterdayCents: 0,
            lastUpdated: .now
        )
        XCTAssertEqual(snapshot.latestTickets.count, 10)
    }

    func test_nextAppointments_cappedAtThree() {
        let appts = (0..<6).map { i in
            WidgetSnapshot.AppointmentSummary(
                id: Int64(i),
                customerName: "C\(i)",
                scheduledAt: Date(timeIntervalSince1970: Double(i) * 3600)
            )
        }
        let snapshot = WidgetSnapshot(
            openTicketCount: 0,
            revenueTodayCents: 0,
            revenueYesterdayCents: 0,
            nextAppointments: appts,
            lastUpdated: .now
        )
        XCTAssertEqual(snapshot.nextAppointments.count, 3)
    }

    // MARK: - Derived values

    func test_revenueDelta_positive() {
        let snapshot = WidgetSnapshot(
            openTicketCount: 0,
            revenueTodayCents: 200_00,
            revenueYesterdayCents: 150_00,
            lastUpdated: .now
        )
        XCTAssertEqual(snapshot.revenueDeltaCents, 50_00)
    }

    func test_revenueDelta_negative() {
        let snapshot = WidgetSnapshot(
            openTicketCount: 0,
            revenueTodayCents: 100_00,
            revenueYesterdayCents: 150_00,
            lastUpdated: .now
        )
        XCTAssertEqual(snapshot.revenueDeltaCents, -50_00)
    }

    func test_formattedRevenue_cents() {
        let snapshot = WidgetSnapshot(
            openTicketCount: 0,
            revenueTodayCents: 123_456,
            revenueYesterdayCents: 0,
            lastUpdated: .now
        )
        let formatted = snapshot.formattedRevenue(cents: 123_456)
        // Should contain "1,234" and "56" (locale-safe check)
        XCTAssertTrue(formatted.contains("1,234") || formatted.contains("1.234"))
    }

    // MARK: - Sendable conformance compile-time checks

    func test_snapshotIsSendable() {
        // If this compiles, Sendable is satisfied.
        func acceptsSendable<T: Sendable>(_ value: T) {}
        let s = WidgetSnapshot(
            openTicketCount: 0,
            revenueTodayCents: 0,
            revenueYesterdayCents: 0,
            lastUpdated: .now
        )
        acceptsSendable(s)
    }
}
