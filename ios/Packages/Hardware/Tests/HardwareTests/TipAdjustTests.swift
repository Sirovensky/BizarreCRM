import XCTest
@testable import Hardware

// §17.3 — Tip adjust + batch management tests

final class TipAdjustTests: XCTestCase {

    // MARK: - TipAdjustResult

    func testTipAdjustResult_equality() {
        let r1 = TipAdjustResult(
            transactionId: "txn-001",
            adjustedTipCents: 300,
            approved: true,
            approvalCode: "AUTH123"
        )
        let r2 = TipAdjustResult(
            transactionId: "txn-001",
            adjustedTipCents: 300,
            approved: true,
            approvalCode: "AUTH123"
        )
        XCTAssertEqual(r1, r2)
    }

    func testTipAdjustResult_unapproved() {
        let r = TipAdjustResult(
            transactionId: "txn-002",
            adjustedTipCents: 0,
            approved: false,
            approvalCode: nil
        )
        XCTAssertFalse(r.approved)
        XCTAssertNil(r.approvalCode)
    }

    // MARK: - BatchCloseResult

    func testBatchCloseResult_equality() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let r1 = BatchCloseResult(batchId: "B-001", transactionCount: 42, totalSalesCents: 1_234_56, closedAt: date)
        let r2 = BatchCloseResult(batchId: "B-001", transactionCount: 42, totalSalesCents: 1_234_56, closedAt: date)
        XCTAssertEqual(r1, r2)
    }

    // MARK: - BlockChypRelayMode

    func testRelayMode_offlineImplication_local() {
        let mode = BlockChypRelayMode.local
        XCTAssertTrue(mode.offlineImplication.contains("Local mode"))
        XCTAssertTrue(mode.offlineImplication.lowercased().contains("internet"))
    }

    func testRelayMode_offlineImplication_cloud() {
        let mode = BlockChypRelayMode.cloudRelay
        XCTAssertTrue(mode.offlineImplication.contains("Cloud relay"))
        XCTAssertTrue(mode.offlineImplication.lowercased().contains("internet"))
    }

    func testRelayMode_rawValues() {
        XCTAssertEqual(BlockChypRelayMode.local.rawValue, "Local")
        XCTAssertEqual(BlockChypRelayMode.cloudRelay.rawValue, "Cloud Relay")
    }

    func testRelayMode_allCases() {
        XCTAssertEqual(BlockChypRelayMode.allCases.count, 2)
    }
}
