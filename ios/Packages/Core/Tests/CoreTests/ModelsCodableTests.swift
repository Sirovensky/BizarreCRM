import XCTest
@testable import Core

// MARK: - ModelsCodableTests
//
// JSON roundtrip tests for the Core/Models ERD expansion (§78).
// Coverage target: ≥ 80% of lines in each model file.

final class ModelsCodableTests: XCTestCase {

    // MARK: - Helpers

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func roundtrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try encoder.encode(value)
        return try decoder.decode(T.self, from: data)
    }

    private var referenceDate: Date { Date(timeIntervalSince1970: 1_700_000_000) }

    // MARK: - Invoice

    func testInvoiceRoundtrip() throws {
        let lineItem = InvoiceLineItem(
            id: 1,
            invoiceId: 10,
            inventoryItemId: 5,
            itemName: "Screen Replacement",
            description: nil,
            sku: "SCR-15",
            quantity: 1,
            unitPriceCents: 9999,
            discountCents: 0,
            taxCents: 800,
            totalCents: 10799
        )
        let payment = InvoicePayment(
            id: 1,
            amountCents: 10799,
            method: "card",
            methodDetail: "Visa",
            transactionId: "txn_abc",
            notes: nil,
            paymentType: "full",
            recordedBy: "Jane",
            createdAt: referenceDate
        )
        let invoice = Invoice(
            id: 42,
            orderId: "INV-0042",
            customerId: 7,
            ticketId: 3,
            status: .paid,
            subtotalCents: 9999,
            discountCents: 0,
            taxCents: 800,
            totalCents: 10799,
            amountPaidCents: 10799,
            amountDueCents: 0,
            notes: "Rush job",
            dueOn: referenceDate,
            lineItems: [lineItem],
            payments: [payment],
            createdAt: referenceDate,
            updatedAt: referenceDate
        )

        let decoded = try roundtrip(invoice)
        XCTAssertEqual(decoded, invoice)
        XCTAssertEqual(decoded.displayId, "INV-0042")
        XCTAssertFalse(decoded.isOverdue)
    }

    func testInvoiceStatusRawValues() {
        XCTAssertEqual(InvoiceStatus.unpaid.rawValue, "unpaid")
        XCTAssertEqual(InvoiceStatus.partial.rawValue, "partial")
        XCTAssertEqual(InvoiceStatus.paid.rawValue, "paid")
        XCTAssertEqual(InvoiceStatus.void.rawValue, "void")
    }

    func testInvoiceIsOverdue() {
        let pastDate = Date(timeIntervalSinceNow: -86400)
        let invoice = Invoice(
            id: 1,
            status: .unpaid,
            dueOn: pastDate,
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
        XCTAssertTrue(invoice.isOverdue)
    }

    func testInvoiceFallbackDisplayId() {
        let invoice = Invoice(id: 99, createdAt: referenceDate, updatedAt: referenceDate)
        XCTAssertEqual(invoice.displayId, "INV-99")
    }

    func testLineItemDisplayName() {
        let withName = InvoiceLineItem(id: 1, itemName: "Battery", description: "Li-Ion")
        XCTAssertEqual(withName.displayName, "Battery")

        let withDescription = InvoiceLineItem(id: 2, description: "Labour")
        XCTAssertEqual(withDescription.displayName, "Labour")

        let fallback = InvoiceLineItem(id: 3)
        XCTAssertEqual(fallback.displayName, "Item")
    }

    // MARK: - Estimate

    func testEstimateRoundtrip() throws {
        // Use whole-second precision to survive ISO8601 roundtrip (no sub-second).
        let futureDate = Date(timeIntervalSince1970: ceil(Date().timeIntervalSince1970) + 86400 * 30)
        let lineItem = EstimateLineItem(
            id: 1,
            estimateId: 5,
            itemName: "Diagnostic",
            quantity: 1,
            unitPriceCents: 4999,
            totalCents: 4999
        )
        let estimate = Estimate(
            id: 5,
            orderId: "EST-0005",
            customerId: 3,
            status: .sent,
            totalCents: 4999,
            validUntil: futureDate,
            lineItems: [lineItem],
            createdAt: referenceDate,
            updatedAt: referenceDate
        )

        let decoded = try roundtrip(estimate)
        XCTAssertEqual(decoded, estimate)
        XCTAssertEqual(decoded.displayId, "EST-0005")
        XCTAssertFalse(decoded.isExpired, "Estimate with future validUntil should not be expired")
    }

    func testEstimateIsExpiredWhenPastDue() {
        let pastDate = Date(timeIntervalSinceNow: -86400)
        let est = Estimate(id: 10, validUntil: pastDate, createdAt: referenceDate, updatedAt: referenceDate)
        XCTAssertTrue(est.isExpired, "Estimate with past validUntil and draft status should be expired")
    }

    func testEstimateFallbackDisplayId() {
        let est = Estimate(id: 7, createdAt: referenceDate, updatedAt: referenceDate)
        XCTAssertEqual(est.displayId, "EST-7")
    }

    func testEstimateStatusAllCases() {
        XCTAssertEqual(EstimateStatus.allCases.count, 6)
        XCTAssertEqual(EstimateStatus.converted.displayName, "Converted")
    }

    // MARK: - Lead

    func testLeadRoundtrip() throws {
        let lead = Lead(
            id: 11,
            orderId: "LEAD-011",
            firstName: "Alice",
            lastName: "Wonder",
            email: "alice@example.com",
            phone: "+15551234567",
            status: .qualified,
            source: .referral,
            leadScore: 80,
            createdAt: referenceDate,
            updatedAt: referenceDate
        )

        let decoded = try roundtrip(lead)
        XCTAssertEqual(decoded, lead)
        XCTAssertEqual(decoded.displayName, "Alice Wonder")
    }

    func testLeadSourceRawValues() {
        XCTAssertEqual(LeadSource.walkin.rawValue, "walk_in")
        XCTAssertEqual(LeadSource.socialMedia.rawValue, "social_media")
    }

    func testLeadStatusRawValues() {
        XCTAssertEqual(LeadStatus.proposalSent.rawValue, "proposal_sent")
        XCTAssertEqual(LeadStatus.new.displayName, "New")
    }

    func testLeadFallbackDisplayName() {
        let lead = Lead(id: 99, orderId: "LEAD-099", createdAt: referenceDate, updatedAt: referenceDate)
        XCTAssertEqual(lead.displayName, "LEAD-099")
    }

    // MARK: - Appointment

    func testAppointmentRoundtrip() throws {
        let start = referenceDate
        let end = start.addingTimeInterval(3600)
        let appt = Appointment(
            id: 20,
            leadId: 5,
            customerId: nil,
            assignedUserId: 2,
            title: "Phone Consultation",
            status: .confirmed,
            location: "Remote",
            startTime: start,
            endTime: end,
            createdAt: referenceDate,
            updatedAt: referenceDate
        )

        let decoded = try roundtrip(appt)
        XCTAssertEqual(decoded, appt)
        XCTAssertEqual(decoded.durationMinutes, 60)
        XCTAssertEqual(decoded.displayTitle, "Phone Consultation")
    }

    func testAppointmentFallbackTitle() {
        let appt = Appointment(
            id: 5,
            startTime: referenceDate,
            endTime: referenceDate.addingTimeInterval(1800),
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
        XCTAssertEqual(appt.displayTitle, "Appointment #5")
    }

    func testAppointmentStatusRawValues() {
        XCTAssertEqual(AppointmentStatus.checkedIn.rawValue, "checked_in")
        XCTAssertEqual(AppointmentStatus.noShow.rawValue, "no_show")
    }

    // MARK: - Expense

    func testExpenseRoundtrip() throws {
        let expense = Expense(
            id: 30,
            category: .parts,
            amountCents: 2500,
            description: "Replacement screen",
            date: referenceDate,
            receiptPath: "/receipts/30.jpg",
            submittedByUserId: 1,
            createdAt: referenceDate,
            updatedAt: referenceDate
        )

        let decoded = try roundtrip(expense)
        XCTAssertEqual(decoded, expense)
        XCTAssertTrue(decoded.hasReceipt)
    }

    func testExpenseNoReceipt() {
        let expense = Expense(id: 1, date: referenceDate, createdAt: referenceDate, updatedAt: referenceDate)
        XCTAssertFalse(expense.hasReceipt)
    }

    func testExpenseCategoryAllCases() {
        XCTAssertEqual(ExpenseCategory.allCases.count, 12)
        XCTAssertEqual(ExpenseCategory.shipping.displayName, "Shipping")
    }

    // MARK: - Employee

    func testEmployeeRoundtrip() throws {
        let employee = Employee(
            id: 50,
            username: "jsmith",
            email: "john@bizarrecrm.com",
            firstName: "John",
            lastName: "Smith",
            role: .technician,
            avatarURL: "https://cdn.example.com/avatar.jpg",
            isActive: true,
            hasPin: true,
            createdAt: referenceDate,
            updatedAt: referenceDate
        )

        let decoded = try roundtrip(employee)
        XCTAssertEqual(decoded, employee)
        XCTAssertEqual(decoded.displayName, "John Smith")
        XCTAssertEqual(decoded.initials, "JS")
    }

    func testEmployeeFallbackInitials() {
        let emp = Employee(
            id: 2,
            username: "admin",
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
        XCTAssertEqual(emp.initials, "AD")
        XCTAssertEqual(emp.displayName, "admin")
    }

    func testEmployeeRoleServerStringInit() {
        XCTAssertEqual(EmployeeRole(serverString: "front_desk"), .frontDesk)
        XCTAssertEqual(EmployeeRole(serverString: "unknown_role"), .custom)
        XCTAssertEqual(EmployeeRole(serverString: nil), .custom)
    }

    func testEmployeeRoleAllCases() {
        XCTAssertEqual(EmployeeRole.allCases.count, 6)
        XCTAssertEqual(EmployeeRole.frontDesk.displayName, "Front Desk")
    }

    // MARK: - CashSession

    func testCashSessionRoundtrip() throws {
        let session = CashSession(
            id: 1,
            openedByUserId: 3,
            closedByUserId: nil,
            status: .open,
            openingFloatCents: 20000,
            closingCountedCents: nil,
            expectedCents: nil,
            varianceCents: nil,
            notes: "Morning shift",
            openedAt: referenceDate,
            closedAt: nil
        )

        let decoded = try roundtrip(session)
        XCTAssertEqual(decoded, session)
        XCTAssertTrue(decoded.isOpen)
    }

    func testCashSessionVarianceDescription() {
        let over = CashSession(
            id: 2,
            status: .closed,
            openingFloatCents: 10000,
            closingCountedCents: 10500,
            varianceCents: 500,
            openedAt: referenceDate
        )
        XCTAssertEqual(over.varianceDescription, "+$5.00")

        let short = CashSession(
            id: 3,
            status: .closed,
            openingFloatCents: 10000,
            closingCountedCents: 9800,
            varianceCents: -200,
            openedAt: referenceDate
        )
        XCTAssertEqual(short.varianceDescription, "-$2.00")

        let unknown = CashSession(id: 4, openedAt: referenceDate)
        XCTAssertEqual(unknown.varianceDescription, "—")
    }

    func testCashSessionStatusAllCases() {
        XCTAssertEqual(CashSessionStatus.allCases.count, 3)
        XCTAssertEqual(CashSessionStatus.reconciled.displayName, "Reconciled")
    }

    // MARK: - Cents typealias

    func testCentsTypealias() {
        let price: Cents = 9999
        XCTAssertEqual(price, 9999)
        // Confirm it's Int at runtime (Cents is a typealias for Int)
        XCTAssertTrue(price is Int)
    }
}
