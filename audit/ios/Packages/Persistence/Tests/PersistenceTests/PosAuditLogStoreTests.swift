import XCTest
@testable import Persistence

/// §16.11 — unit tests for `PosAuditLogStore`.
///
/// Each test runs against a fresh throwaway SQLite DB opened via
/// `Database.reopen(at:)` so tests never touch the production file.
final class PosAuditLogStoreTests: XCTestCase {

    private var tempURL: URL!

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audit-log-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempURL = dir.appendingPathComponent("test.sqlite")
        try await Database.shared.reopen(at: tempURL)
    }

    override func tearDown() async throws {
        await Database.shared.close()
        if let url = tempURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Insert

    func test_record_returnsPositiveRowId() async throws {
        let id = try await PosAuditLogStore.shared.record(
            event: PosAuditEntry.EventType.voidLine,
            cashierId: 1
        )
        XCTAssertGreaterThan(id, 0)
    }

    func test_record_persistsAllFields() async throws {
        let context: [String: Any] = ["sku": "ABC-123", "lineName": "Widget", "originalPriceCents": 999]
        _ = try await PosAuditLogStore.shared.record(
            event: PosAuditEntry.EventType.priceOverride,
            cashierId: 5,
            managerId: 11,
            amountCents: 250,
            reason: "Price match",
            context: context
        )

        let rows = try await PosAuditLogStore.shared.recent(limit: 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.eventType, PosAuditEntry.EventType.priceOverride)
        XCTAssertEqual(row.cashierId, 5)
        XCTAssertEqual(row.managerId, 11)
        XCTAssertEqual(row.amountCents, 250)
        XCTAssertEqual(row.reason, "Price match")
        XCTAssertNotNil(row.contextJson)
    }

    func test_record_nilManagerId_whenCashierUnderThreshold() async throws {
        _ = try await PosAuditLogStore.shared.record(
            event: PosAuditEntry.EventType.discountOverride,
            cashierId: 2
            // managerId intentionally omitted
        )
        let rows = try await PosAuditLogStore.shared.recent(limit: 1)
        XCTAssertNil(rows.first?.managerId)
    }

    // MARK: - Recent ordering

    func test_recent_returnsNewestFirst() async throws {
        // Insert three events with staggered timestamps so ordering is deterministic.
        let now = Date().timeIntervalSince1970
        // Manually insert with explicit created_at to avoid sub-ms collisions.
        guard let pool = await Database.shared.pool() else {
            XCTFail("No pool"); return
        }
        try await pool.write { db in
            var a = PosAuditEntry(eventType: "void_line",           cashierId: 0, createdAt: now - 200)
            var b = PosAuditEntry(eventType: "no_sale",             cashierId: 0, createdAt: now - 100)
            var c = PosAuditEntry(eventType: "discount_override",   cashierId: 0, createdAt: now)
            try a.insert(db); try b.insert(db); try c.insert(db)
        }

        let rows = try await PosAuditLogStore.shared.recent(limit: 10)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].eventType, "discount_override", "newest must be first")
        XCTAssertEqual(rows[1].eventType, "no_sale")
        XCTAssertEqual(rows[2].eventType, "void_line", "oldest must be last")
    }

    func test_recent_respectsLimit() async throws {
        for i in 0..<7 {
            _ = try await PosAuditLogStore.shared.record(
                event: PosAuditEntry.EventType.deleteLine,
                cashierId: Int64(i)
            )
        }
        let rows = try await PosAuditLogStore.shared.recent(limit: 3)
        XCTAssertEqual(rows.count, 3)
    }

    // MARK: - byEventType filter

    func test_byEventType_filtersCorrectly() async throws {
        _ = try await PosAuditLogStore.shared.record(event: "void_line",   cashierId: 0)
        _ = try await PosAuditLogStore.shared.record(event: "no_sale",     cashierId: 0)
        _ = try await PosAuditLogStore.shared.record(event: "void_line",   cashierId: 0)
        _ = try await PosAuditLogStore.shared.record(event: "no_sale",     cashierId: 0)
        _ = try await PosAuditLogStore.shared.record(event: "price_override", cashierId: 0)

        let voids = try await PosAuditLogStore.shared.byEventType("void_line", limit: 50)
        XCTAssertEqual(voids.count, 2)
        XCTAssertTrue(voids.allSatisfy { $0.eventType == "void_line" })

        let noSales = try await PosAuditLogStore.shared.byEventType("no_sale", limit: 50)
        XCTAssertEqual(noSales.count, 2)
    }

    func test_byEventType_returnsEmptyForUnknownType() async throws {
        _ = try await PosAuditLogStore.shared.record(event: "void_line", cashierId: 0)
        let rows = try await PosAuditLogStore.shared.byEventType("unknown_event", limit: 10)
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: - Context JSON round-trip

    func test_contextJson_roundTrip_stringValues() async throws {
        let ctx: [String: Any] = ["sku": "WIDGET-42", "lineName": "Widget Pro"]
        _ = try await PosAuditLogStore.shared.record(
            event: "void_line",
            cashierId: 0,
            context: ctx
        )
        let rows = try await PosAuditLogStore.shared.recent(limit: 1)
        let row = try XCTUnwrap(rows.first)
        let dict = row.contextDictionary
        XCTAssertEqual(dict["sku"], "WIDGET-42")
        XCTAssertEqual(dict["lineName"], "Widget Pro")
    }

    func test_contextJson_roundTrip_numericValues() async throws {
        let ctx: [String: Any] = ["originalPriceCents": 4999, "newPriceCents": 2999]
        _ = try await PosAuditLogStore.shared.record(
            event: "price_override",
            cashierId: 0,
            context: ctx
        )
        let rows = try await PosAuditLogStore.shared.recent(limit: 1)
        let row = try XCTUnwrap(rows.first)
        let dict = row.contextDictionary
        // Numeric values come back as their string representation via CustomStringConvertible.
        XCTAssertNotNil(dict["originalPriceCents"])
        XCTAssertNotNil(dict["newPriceCents"])
    }

    func test_contextJson_nilWhenContextEmpty() async throws {
        _ = try await PosAuditLogStore.shared.record(
            event: "no_sale",
            cashierId: 0,
            context: [:]
        )
        let rows = try await PosAuditLogStore.shared.recent(limit: 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertNil(row.contextJson)
    }

    // MARK: - count(eventType:from:to:)

    func test_count_returnsCorrectCountForDateRange() async throws {
        let now = Date()
        // Two events in range, one outside.
        guard let pool = await Database.shared.pool() else { XCTFail("No pool"); return }
        try await pool.write { db in
            var inRange1 = PosAuditEntry(eventType: "void_line", cashierId: 0,
                                         createdAt: now.addingTimeInterval(-60).timeIntervalSince1970)
            var inRange2 = PosAuditEntry(eventType: "void_line", cashierId: 0,
                                         createdAt: now.addingTimeInterval(-30).timeIntervalSince1970)
            var outside = PosAuditEntry(eventType: "void_line", cashierId: 0,
                                        createdAt: now.addingTimeInterval(-3_601).timeIntervalSince1970)
            try inRange1.insert(db)
            try inRange2.insert(db)
            try outside.insert(db)
        }

        let count = try await PosAuditLogStore.shared.count(
            eventType: "void_line",
            from: now.addingTimeInterval(-3_600),
            to: now
        )
        XCTAssertEqual(count, 2)
    }

    // MARK: - eventTypeLabel

    func test_eventTypeLabel_knownEvents() {
        XCTAssertEqual(PosAuditEntry(eventType: "void_line",         cashierId: 0).eventTypeLabel, "Void line")
        XCTAssertEqual(PosAuditEntry(eventType: "no_sale",           cashierId: 0).eventTypeLabel, "No sale")
        XCTAssertEqual(PosAuditEntry(eventType: "discount_override", cashierId: 0).eventTypeLabel, "Discount override")
        XCTAssertEqual(PosAuditEntry(eventType: "price_override",    cashierId: 0).eventTypeLabel, "Price override")
        XCTAssertEqual(PosAuditEntry(eventType: "delete_line",       cashierId: 0).eventTypeLabel, "Delete line")
    }

    func test_eventTypeLabel_unknownFallsThrough() {
        let entry = PosAuditEntry(eventType: "mystery_event", cashierId: 0)
        XCTAssertEqual(entry.eventTypeLabel, "mystery_event")
    }
}
