import XCTest
@testable import Core

// §31 Extended edge-case tests
//
// Covers gaps in the initial §31 filler batch (3afa3e3a):
//   1. LogCaptureSink thread safety — 1 000 concurrent writes, no loss
//   2. LogCaptureSink.reset() leaves sink empty
//   3. LogCaptureSink category filter returns exact subset (multi-category)
//   4. contrastRatio() black-on-white ≥ 21:1
//   5. contrastRatio() identical colours == 1.0
//   6. ticket_default.json fixture loads without error and matches domain rules

// MARK: - Inline WCAG contrast-ratio helpers (pure math, no DesignSystem import)

/// WCAG 2.2 relative luminance for a hex RGB colour.
/// Duplicated from DesignSystemTests so the Core test target stays self-contained.
private func _relativeLuminance(hex: UInt32) -> Double {
    let r = Double((hex >> 16) & 0xFF) / 255.0
    let g = Double((hex >>  8) & 0xFF) / 255.0
    let b = Double( hex        & 0xFF) / 255.0
    func lin(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

/// WCAG contrast ratio in [1, 21].
private func _contrastRatio(foreground fg: UInt32, background bg: UInt32) -> Double {
    let l1 = _relativeLuminance(hex: fg)
    let l2 = _relativeLuminance(hex: bg)
    let lighter = max(l1, l2)
    let darker  = min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)
}

// MARK: - §31 Extended: LogCaptureSink thread safety (1 000 writes)

final class LogCaptureSinkThreadSafetyExtendedTests: XCTestCase {

    // MARK: §31.ext.1 — 1 000 concurrent writes: count must not be lost

    func test_concurrentWrites_1000_preservesCount() {
        let writeCount = 1_000
        let sink = LogCaptureSink()

        let expectation = expectation(description: "1 000 concurrent log writes complete")
        expectation.expectedFulfillmentCount = writeCount

        let queue = DispatchQueue(
            label: "com.bizarrecrm.tests.§31ext.concurrent",
            attributes: .concurrent
        )

        for i in 0..<writeCount {
            queue.async {
                sink.log(level: .debug, message: "write-\(i)", category: "stress")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10)

        XCTAssertEqual(
            sink.captured.count,
            writeCount,
            "All \(writeCount) concurrent writes must be captured — no entry must be lost under lock contention"
        )
    }

    // MARK: §31.ext.1b — Every message string written is present in captured

    func test_concurrentWrites_everyMessageIsPresent() {
        let writeCount = 200  // Smaller count for exhaustive membership check
        let sink = LogCaptureSink()

        let group = DispatchGroup()
        let queue = DispatchQueue(
            label: "com.bizarrecrm.tests.§31ext.membership",
            attributes: .concurrent
        )

        for i in 0..<writeCount {
            group.enter()
            queue.async {
                sink.log(level: .info, message: "token-\(i)", category: "membership")
                group.leave()
            }
        }

        group.wait()

        let messages = Set(sink.captured.map(\.message))
        for i in 0..<writeCount {
            XCTAssertTrue(
                messages.contains("token-\(i)"),
                "message 'token-\(i)' must appear in captured after concurrent write"
            )
        }
    }
}

// MARK: - §31 Extended: LogCaptureSink.reset()

final class LogCaptureSinkResetExtendedTests: XCTestCase {

    private var sink: LogCaptureSink!

    override func setUp() {
        super.setUp()
        sink = LogCaptureSink()
    }

    override func tearDown() {
        sink = nil
        super.tearDown()
    }

    // MARK: §31.ext.2 — reset() leaves captured empty

    func test_reset_afterMultipleWrites_capturedIsEmpty() {
        for i in 0..<50 {
            sink.log(level: .notice, message: "entry \(i)", category: "app")
        }
        XCTAssertEqual(sink.captured.count, 50, "pre-condition: 50 entries must be captured")

        sink.reset()

        XCTAssertTrue(sink.captured.isEmpty, "reset() must leave captured completely empty")
        XCTAssertEqual(sink.captured.count, 0)
    }

    // MARK: §31.ext.2b — successive reset() calls are idempotent

    func test_reset_calledTwice_remainsEmpty() {
        sink.log(level: .error, message: "boom", category: "sync")
        sink.reset()
        sink.reset()  // second call on already-empty sink must not crash or corrupt

        XCTAssertTrue(sink.captured.isEmpty, "A second reset() on an empty sink must leave it empty")
    }

    // MARK: §31.ext.2c — reset() between write batches separates counts correctly

    func test_reset_separatesBatches() {
        sink.log(level: .debug, message: "batch-1-a", category: "app")
        sink.log(level: .debug, message: "batch-1-b", category: "app")
        sink.reset()

        sink.log(level: .info, message: "batch-2-a", category: "app")
        XCTAssertEqual(sink.captured.count, 1, "Only post-reset entries must appear in captured")
        XCTAssertEqual(sink.captured[0].message, "batch-2-a")
    }
}

// MARK: - §31 Extended: LogCaptureSink category filtering

final class LogCaptureSinkCategoryFilterExtendedTests: XCTestCase {

    private var sink: LogCaptureSink!

    override func setUp() {
        super.setUp()
        sink = LogCaptureSink()
    }

    override func tearDown() {
        sink.reset()
        sink = nil
        super.tearDown()
    }

    // MARK: §31.ext.3 — entries(category:) returns strict subset when multiple categories logged

    func test_categoryFilter_returnsOnlyMatchingCategory() {
        sink.log(level: .debug,  message: "net-1", category: "networking")
        sink.log(level: .info,   message: "auth-1", category: "auth")
        sink.log(level: .notice, message: "net-2", category: "networking")
        sink.log(level: .error,  message: "db-1",  category: "db")
        sink.log(level: .fault,  message: "net-3", category: "networking")

        let netEntries = sink.entries(category: "networking")

        XCTAssertEqual(netEntries.count, 3, "Exactly 3 networking entries must be returned")
        XCTAssertTrue(
            netEntries.allSatisfy { $0.category == "networking" },
            "All returned entries must belong to 'networking'"
        )
    }

    // MARK: §31.ext.3b — entries(category:) for category with no writes returns empty array

    func test_categoryFilter_unwrittenCategory_returnsEmpty() {
        sink.log(level: .info, message: "x", category: "auth")
        let result = sink.entries(category: "payments")
        XCTAssertTrue(result.isEmpty, "Category 'payments' was never written — result must be empty")
    }

    // MARK: §31.ext.3c — entries(category:) is case-sensitive

    func test_categoryFilter_isCaseSensitive() {
        sink.log(level: .debug, message: "a", category: "Auth")
        sink.log(level: .debug, message: "b", category: "auth")

        let upper = sink.entries(category: "Auth")
        let lower = sink.entries(category: "auth")

        XCTAssertEqual(upper.count, 1, "Exact case match 'Auth' must return exactly 1 entry")
        XCTAssertEqual(lower.count, 1, "Exact case match 'auth' must return exactly 1 entry")
        XCTAssertEqual(upper[0].message, "a")
        XCTAssertEqual(lower[0].message, "b")
    }
}

// MARK: - §31 Extended: contrastRatio() edge cases

final class ContrastRatioEdgeCaseTests: XCTestCase {

    // MARK: §31.ext.4 — white on black and black on white return ≥ 21:1

    func test_contrastRatio_blackOnWhite_isAtLeast21() {
        let ratio = _contrastRatio(foreground: 0x000000, background: 0xFFFFFF)
        XCTAssertGreaterThanOrEqual(
            ratio, 21.0,
            "Black (#000000) on white (#FFFFFF) must achieve the maximum WCAG contrast of 21:1, got \(ratio)"
        )
    }

    func test_contrastRatio_whiteOnBlack_isAtLeast21() {
        // Symmetric: swapping fg/bg must yield the same ratio
        let ratio = _contrastRatio(foreground: 0xFFFFFF, background: 0x000000)
        XCTAssertGreaterThanOrEqual(
            ratio, 21.0,
            "White (#FFFFFF) on black (#000000) must achieve ≥ 21:1, got \(ratio)"
        )
    }

    // MARK: §31.ext.5 — identical colours return exactly 1.0

    func test_contrastRatio_identicalColors_isExactly1() {
        let identical: UInt32 = 0xABCDEF
        let ratio = _contrastRatio(foreground: identical, background: identical)
        XCTAssertEqual(
            ratio, 1.0, accuracy: 0.0001,
            "Contrast ratio of a colour against itself must be exactly 1.0"
        )
    }

    func test_contrastRatio_midGrayOnItself_is1() {
        let ratio = _contrastRatio(foreground: 0x808080, background: 0x808080)
        XCTAssertEqual(ratio, 1.0, accuracy: 0.0001)
    }

    // MARK: §31.ext bonus — ratio is always ≥ 1.0 (no negative or sub-unity results)

    func test_contrastRatio_neverBelowOne() {
        let pairs: [(UInt32, UInt32)] = [
            (0x000000, 0x000001),  // nearly-identical darks
            (0xFFFFFE, 0xFFFFFF),  // nearly-identical lights
            (0xFF0000, 0x0000FF),  // saturated hue pair
            (0x7F7F7F, 0x808080),  // adjacent grays
        ]
        for (fg, bg) in pairs {
            let ratio = _contrastRatio(foreground: fg, background: bg)
            XCTAssertGreaterThanOrEqual(
                ratio, 1.0,
                "contrastRatio must never be < 1.0; got \(ratio) for #\(String(format: "%06X", fg)) on #\(String(format: "%06X", bg))"
            )
        }
    }
}

// MARK: - §31 Extended: ticket_default.json fixture

final class TicketDefaultFixtureExtendedTests: XCTestCase {

    // Minimal Decodable ticket struct (mirrors ParameterizedFixtureTests local struct)
    private struct FixtureTicket: Decodable {
        let id: Int
        let number: String
        let title: String
        let status: String
        let priority: String
        let customerId: Int
        let laborCents: Int
        let createdAt: Date
        let updatedAt: Date
    }

    private func loader() -> FixtureLoader { FixtureLoader(bundle: .module) }

    // MARK: §31.ext.6 — ticket_default.json loads without error

    func test_ticketDefaultFixture_loadsWithoutError() throws {
        // The primary requirement: fixture file must exist and be decodable.
        XCTAssertNoThrow(
            try loader().load("ticket_default") as FixtureTicket,
            "ticket_default.json must exist in the test bundle and decode without error"
        )
    }

    // MARK: §31.ext.6b — fixture fields satisfy domain invariants

    func test_ticketDefaultFixture_idIsPositive() throws {
        let ticket: FixtureTicket = try loader().load("ticket_default")
        XCTAssertGreaterThan(ticket.id, 0, "Ticket id must be positive")
    }

    func test_ticketDefaultFixture_numberHasTKPrefix() throws {
        let ticket: FixtureTicket = try loader().load("ticket_default")
        XCTAssertTrue(
            ticket.number.hasPrefix("TK-"),
            "Ticket number must have 'TK-' prefix, got '\(ticket.number)'"
        )
    }

    func test_ticketDefaultFixture_titleIsNonEmpty() throws {
        let ticket: FixtureTicket = try loader().load("ticket_default")
        XCTAssertFalse(ticket.title.isEmpty, "Ticket title must not be empty")
    }

    func test_ticketDefaultFixture_statusIsNonEmpty() throws {
        let ticket: FixtureTicket = try loader().load("ticket_default")
        XCTAssertFalse(ticket.status.isEmpty, "Ticket status must not be empty")
    }

    func test_ticketDefaultFixture_laborCentsIsNonNegative() throws {
        let ticket: FixtureTicket = try loader().load("ticket_default")
        XCTAssertGreaterThanOrEqual(ticket.laborCents, 0, "laborCents must be ≥ 0")
    }

    func test_ticketDefaultFixture_updatedAtIsNotBeforeCreatedAt() throws {
        let ticket: FixtureTicket = try loader().load("ticket_default")
        XCTAssertGreaterThanOrEqual(
            ticket.updatedAt, ticket.createdAt,
            "updatedAt must not precede createdAt"
        )
    }

    // MARK: §31.ext.6c — raw loadData confirms file is non-empty JSON

    func test_ticketDefaultFixture_rawDataIsNonEmpty() throws {
        let data = try loader().loadData("ticket_default")
        XCTAssertFalse(data.isEmpty, "ticket_default.json must produce non-empty raw data")
    }
}
