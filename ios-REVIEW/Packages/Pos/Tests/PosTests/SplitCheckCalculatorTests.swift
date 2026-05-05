import XCTest
@testable import Pos

final class SplitCheckCalculatorTests: XCTestCase {

    // MARK: - even()

    func test_even_twoParties_exactSplit() {
        let result = SplitCheckCalculator.even(totalCents: 1000, parties: 2)
        XCTAssertEqual(result, [500, 500])
    }

    func test_even_threeParties_remainderOnLast() {
        // 10 / 3 = 3 + 3 + 4
        let result = SplitCheckCalculator.even(totalCents: 10, parties: 3)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0], 3)
        XCTAssertEqual(result[1], 3)
        XCTAssertEqual(result[2], 4)
        XCTAssertEqual(result.reduce(0, +), 10)
    }

    func test_even_singleParty_returnsFull() {
        let result = SplitCheckCalculator.even(totalCents: 5000, parties: 1)
        XCTAssertEqual(result, [5000])
    }

    func test_even_zeroParties_returnsFull() {
        let result = SplitCheckCalculator.even(totalCents: 999, parties: 0)
        XCTAssertEqual(result, [999])
    }

    func test_even_sumAlwaysEqualsTotal() {
        for parties in 2...8 {
            for total in [1, 100, 999, 10_001] {
                let result = SplitCheckCalculator.even(totalCents: total, parties: parties)
                XCTAssertEqual(result.reduce(0, +), total, "parties=\(parties) total=\(total)")
            }
        }
    }

    func test_even_largeAmount_noRemainder() {
        let result = SplitCheckCalculator.even(totalCents: 6000, parties: 3)
        XCTAssertEqual(result, [2000, 2000, 2000])
    }

    // MARK: - byLineItem()

    func test_byLineItem_singlePartyAllItems() {
        let partyId = UUID()
        let lines   = makeFakeLines(subtotals: [300, 500, 200])
        let assignments = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, partyId) })
        let result  = SplitCheckCalculator.byLineItem(lines: lines, assignments: assignments)
        XCTAssertEqual(result[partyId], 1000)
    }

    func test_byLineItem_splitBetweenTwoParties() {
        let a = UUID(), b = UUID()
        let lines = makeFakeLines(subtotals: [400, 600])
        let assignments: [CartLineID: PartyID] = [
            lines[0].id: a,
            lines[1].id: b
        ]
        let result = SplitCheckCalculator.byLineItem(lines: lines, assignments: assignments)
        XCTAssertEqual(result[a], 400)
        XCTAssertEqual(result[b], 600)
    }

    func test_byLineItem_unassignedLinesIgnored() {
        let partyId = UUID()
        let lines   = makeFakeLines(subtotals: [200, 300])
        let assignments: [CartLineID: PartyID] = [lines[0].id: partyId]  // line[1] unassigned
        let result  = SplitCheckCalculator.byLineItem(lines: lines, assignments: assignments)
        XCTAssertEqual(result[partyId], 200)
    }

    func test_byLineItem_emptyAssignments_returnsEmpty() {
        let lines  = makeFakeLines(subtotals: [100, 200])
        let result = SplitCheckCalculator.byLineItem(lines: lines, assignments: [:])
        XCTAssertTrue(result.isEmpty)
    }

    func test_byLineItem_multipleItemsSameParty_accumulated() {
        let p = UUID()
        let lines = makeFakeLines(subtotals: [100, 200, 300])
        let assignments = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, p) })
        let result = SplitCheckCalculator.byLineItem(lines: lines, assignments: assignments)
        XCTAssertEqual(result[p], 600)
    }

    // MARK: - validate()

    func test_validate_allAssigned_sumMatches_noErrors() {
        let p     = UUID()
        let lines = makeFakeLines(subtotals: [300, 700])
        let assignments = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, p) })
        let errors = SplitCheckCalculator.validate(lines: lines, assignments: assignments, totalCents: 1000)
        XCTAssertTrue(errors.isEmpty)
    }

    func test_validate_noParties_returnsNoPartiesError() {
        let lines  = makeFakeLines(subtotals: [100])
        let errors = SplitCheckCalculator.validate(lines: lines, assignments: [:], totalCents: 100)
        XCTAssertTrue(errors.contains(.noParties))
    }

    func test_validate_unassignedLine_returnsError() {
        let p     = UUID()
        let lines = makeFakeLines(subtotals: [100, 200])
        let assignments: [CartLineID: PartyID] = [lines[0].id: p]  // line[1] missing
        let errors = SplitCheckCalculator.validate(lines: lines, assignments: assignments, totalCents: 300)
        XCTAssertTrue(errors.contains(.unassignedLines(count: 1)))
    }

    func test_validate_sumMismatch_returnsError() {
        let p     = UUID()
        let lines = makeFakeLines(subtotals: [300])
        let assignments: [CartLineID: PartyID] = [lines[0].id: p]
        // totalCents doesn't match line sum (300 vs 500)
        let errors = SplitCheckCalculator.validate(lines: lines, assignments: assignments, totalCents: 500)
        XCTAssertTrue(errors.contains(.sumMismatch(expected: 500, got: 300)))
    }

    func test_validate_multipleErrors_allReported() {
        let p     = UUID()
        let lines = makeFakeLines(subtotals: [100, 200])
        let assignments: [CartLineID: PartyID] = [lines[0].id: p]  // line[1] unassigned + sum mismatch
        let errors = SplitCheckCalculator.validate(lines: lines, assignments: assignments, totalCents: 999)
        XCTAssertTrue(errors.contains(.unassignedLines(count: 1)))
        XCTAssertTrue(errors.contains(.sumMismatch(expected: 999, got: 100)))
    }

    // MARK: - Helpers

    private func makeFakeLines(subtotals: [Int]) -> [FakeCartLine] {
        subtotals.map { FakeCartLine(subtotalCents: $0) }
    }
}

// MARK: - FakeCartLine

struct FakeCartLine: CartLine {
    let id:            CartLineID = UUID()
    let subtotalCents: Int
}
