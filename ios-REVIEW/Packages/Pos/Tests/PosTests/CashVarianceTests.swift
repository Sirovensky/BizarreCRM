import XCTest
@testable import Pos

/// §39 — pure-logic tests for CashVariance.
final class CashVarianceTests: XCTestCase {
    func test_band_isGreen_whenVarianceIsZero() {
        XCTAssertEqual(CashVariance.band(cents: 0), .green)
    }
    func test_band_isAmber_within5DollarsEitherDirection() {
        XCTAssertEqual(CashVariance.band(cents: 1), .amber)
        XCTAssertEqual(CashVariance.band(cents: -250), .amber)
        XCTAssertEqual(CashVariance.band(cents: 500), .amber)
        XCTAssertEqual(CashVariance.band(cents: -500), .amber)
    }
    func test_band_isRed_whenVarianceBreaches5Dollars() {
        XCTAssertEqual(CashVariance.band(cents: 501), .red)
        XCTAssertEqual(CashVariance.band(cents: -501), .red)
        XCTAssertEqual(CashVariance.band(cents: 2_000), .red)
    }
    func test_notesRequired_onlyForRedBand() {
        XCTAssertFalse(CashVariance.notesRequired(cents: 0))
        XCTAssertFalse(CashVariance.notesRequired(cents: 500))
        XCTAssertFalse(CashVariance.notesRequired(cents: -500))
        XCTAssertTrue(CashVariance.notesRequired(cents: 501))
        XCTAssertTrue(CashVariance.notesRequired(cents: -501))
    }
    func test_canCommit_greenAndAmberNeedNoNotes() {
        XCTAssertTrue(CashVariance.canCommit(varianceCents: 0, notes: ""))
        XCTAssertTrue(CashVariance.canCommit(varianceCents: 300, notes: ""))
        XCTAssertTrue(CashVariance.canCommit(varianceCents: -500, notes: ""))
    }
    func test_canCommit_redRequiresNonBlankNotes() {
        XCTAssertFalse(CashVariance.canCommit(varianceCents: 600, notes: ""))
        XCTAssertFalse(CashVariance.canCommit(varianceCents: 600, notes: "   "))
        XCTAssertTrue(CashVariance.canCommit(varianceCents: 600, notes: "Till skim"))
    }
}
