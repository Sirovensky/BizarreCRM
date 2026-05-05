import XCTest
@testable import Pos

/// §40.4 — Tests for `GiftCardAuditLog`.
final class GiftCardAuditLogTests: XCTestCase {

    private static let key = "com.bizarrecrm.pos.giftCardAuditLog"

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    func test_record_and_retrieveAll() async throws {
        let log = GiftCardAuditLog.shared
        await log.record(kind: .redeemed, cardCode: "ABCD-1234", amountCents: -500)
        let all = await log.allNewestFirst()
        XCTAssertFalse(all.isEmpty)
        XCTAssertEqual(all.first?.kind, .redeemed)
        XCTAssertEqual(all.first?.amountCents, -500)
    }

    func test_filter_byCardCode() async throws {
        let log = GiftCardAuditLog.shared
        await log.record(kind: .redeemed, cardCode: "XXXX-1111", amountCents: -200)
        await log.record(kind: .reloaded, cardCode: "YYYY-2222", amountCents: 500)
        let filtered = await log.entries(forCard: "1111")
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.kind, .redeemed)
    }

    func test_record_voided_carries_managerRef() async throws {
        let log = GiftCardAuditLog.shared
        let entry = GiftCardAuditLog.Entry(
            kind: .voided,
            cardCode: "CARD-9999",
            amountCents: -3000,
            balanceCents: 0,
            approvedByManagerId: "MGR-42"
        )
        await log.record(entry)
        let all = await log.allNewestFirst()
        XCTAssertEqual(all.first?.approvedByManagerId, "MGR-42")
    }

    func test_entryKind_displayNames_nonEmpty() {
        for kind in GiftCardAuditLog.EntryKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty)
            XCTAssertFalse(kind.systemImage.isEmpty)
        }
    }
}

// MARK: - CaseIterable for EntryKind

extension GiftCardAuditLog.EntryKind: CaseIterable {
    public static var allCases: [GiftCardAuditLog.EntryKind] {
        [.issued, .activated, .reloaded, .redeemed, .voided, .transferred, .refunded]
    }
}
