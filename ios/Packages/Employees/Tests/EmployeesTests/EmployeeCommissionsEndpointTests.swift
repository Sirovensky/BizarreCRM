import XCTest
@testable import Networking

// MARK: - EmployeeCommissionsEndpointTests
//
// Validates JSON decoding of EmployeeCommission, EmployeeCommissionsResponse,
// TimeOffRequest, and ClockEntryEditRequest against the exact server shapes
// confirmed in employees.routes.ts / timeOff.routes.ts.

final class EmployeeCommissionsEndpointTests: XCTestCase {

    // MARK: - EmployeeCommission decode

    func test_employeeCommission_decodesFullRow() throws {
        let json = """
        {
            "id": 42,
            "user_id": 7,
            "ticket_id": 100,
            "invoice_id": null,
            "amount": 15.75,
            "created_at": "2026-04-21T10:30:00Z",
            "ticket_order_id": "TK-0042",
            "invoice_order_id": null
        }
        """
        let commission = try decode(EmployeeCommission.self, from: json)
        XCTAssertEqual(commission.id, 42)
        XCTAssertEqual(commission.userId, 7)
        XCTAssertEqual(commission.ticketId, 100)
        XCTAssertNil(commission.invoiceId)
        XCTAssertEqual(commission.amount, 15.75, accuracy: 0.001)
        XCTAssertEqual(commission.createdAt, "2026-04-21T10:30:00Z")
        XCTAssertEqual(commission.ticketOrderId, "TK-0042")
        XCTAssertNil(commission.invoiceOrderId)
    }

    func test_employeeCommission_decodesMinimalRow() throws {
        let json = """
        {
            "id": 1,
            "user_id": 2,
            "amount": 5.0,
            "created_at": "2026-01-01T00:00:00Z"
        }
        """
        let commission = try decode(EmployeeCommission.self, from: json)
        XCTAssertEqual(commission.id, 1)
        XCTAssertNil(commission.ticketId)
        XCTAssertNil(commission.invoiceId)
        XCTAssertNil(commission.ticketOrderId)
        XCTAssertNil(commission.invoiceOrderId)
    }

    func test_employeeCommission_decodesWithInvoiceId() throws {
        let json = """
        {
            "id": 10,
            "user_id": 3,
            "ticket_id": null,
            "invoice_id": 200,
            "amount": 30.0,
            "created_at": "2026-04-22T12:00:00Z",
            "ticket_order_id": null,
            "invoice_order_id": "INV-0200"
        }
        """
        let commission = try decode(EmployeeCommission.self, from: json)
        XCTAssertNil(commission.ticketId)
        XCTAssertEqual(commission.invoiceId, 200)
        XCTAssertEqual(commission.invoiceOrderId, "INV-0200")
    }

    // MARK: - EmployeeCommissionsResponse decode

    func test_commissionsResponse_decodesWithMultipleItems() throws {
        let json = """
        {
            "commissions": [
                {
                    "id": 1,
                    "user_id": 5,
                    "amount": 10.0,
                    "created_at": "2026-04-01T00:00:00Z"
                },
                {
                    "id": 2,
                    "user_id": 5,
                    "amount": 20.0,
                    "created_at": "2026-04-05T00:00:00Z"
                }
            ],
            "total_amount": 30.0
        }
        """
        let response = try decode(EmployeeCommissionsResponse.self, from: json)
        XCTAssertEqual(response.commissions.count, 2)
        XCTAssertEqual(response.totalAmount, 30.0, accuracy: 0.001)
    }

    func test_commissionsResponse_decodesEmpty() throws {
        let json = """
        { "commissions": [], "total_amount": 0.0 }
        """
        let response = try decode(EmployeeCommissionsResponse.self, from: json)
        XCTAssertTrue(response.commissions.isEmpty)
        XCTAssertEqual(response.totalAmount, 0.0)
    }

    func test_commissionsResponse_totalAmountSnakeCaseMapped() throws {
        let json = """
        { "commissions": [], "total_amount": 123.45 }
        """
        let response = try decode(EmployeeCommissionsResponse.self, from: json)
        XCTAssertEqual(response.totalAmount, 123.45, accuracy: 0.001)
    }

    // MARK: - TimeOffRequest decode

    func test_timeOffRequest_decodesPendingRequest() throws {
        let json = """
        {
            "id": 5,
            "user_id": 3,
            "start_date": "2026-05-01",
            "end_date": "2026-05-05",
            "kind": "pto",
            "reason": "Family trip",
            "status": "pending",
            "requested_at": "2026-04-21T08:00:00Z",
            "decided_at": null,
            "approver_user_id": null,
            "denial_reason": null,
            "first_name": "Alice",
            "last_name": "Smith"
        }
        """
        let request = try decode(TimeOffRequest.self, from: json)
        XCTAssertEqual(request.id, 5)
        XCTAssertEqual(request.userId, 3)
        XCTAssertEqual(request.kind, .pto)
        XCTAssertEqual(request.status, .pending)
        XCTAssertEqual(request.reason, "Family trip")
        XCTAssertEqual(request.startDate, "2026-05-01")
        XCTAssertEqual(request.endDate, "2026-05-05")
        XCTAssertEqual(request.firstName, "Alice")
        XCTAssertEqual(request.lastName, "Smith")
        XCTAssertNil(request.decidedAt)
        XCTAssertNil(request.approverUserId)
    }

    func test_timeOffRequest_decodesApprovedRequest() throws {
        let json = """
        {
            "id": 10,
            "user_id": 4,
            "start_date": "2026-06-01",
            "end_date": "2026-06-03",
            "kind": "sick",
            "status": "approved",
            "decided_at": "2026-04-22T09:00:00Z",
            "approver_user_id": 1
        }
        """
        let request = try decode(TimeOffRequest.self, from: json)
        XCTAssertEqual(request.status, .approved)
        XCTAssertEqual(request.kind, .sick)
        XCTAssertEqual(request.approverUserId, 1)
        XCTAssertNotNil(request.decidedAt)
    }

    func test_timeOffRequest_decodesDeniedWithReason() throws {
        let json = """
        {
            "id": 20,
            "user_id": 5,
            "start_date": "2026-07-01",
            "end_date": "2026-07-02",
            "kind": "unpaid",
            "status": "denied",
            "denial_reason": "Short staffed"
        }
        """
        let request = try decode(TimeOffRequest.self, from: json)
        XCTAssertEqual(request.status, .denied)
        XCTAssertEqual(request.denialReason, "Short staffed")
    }

    func test_timeOffRequest_decodesMinimalRow() throws {
        // Server omits some nullable fields entirely.
        let json = """
        {
            "id": 1,
            "user_id": 2,
            "start_date": "2026-05-01",
            "end_date": "2026-05-01",
            "kind": "pto",
            "status": "pending"
        }
        """
        let request = try decode(TimeOffRequest.self, from: json)
        XCTAssertEqual(request.kind, .pto)
        XCTAssertNil(request.reason)
        XCTAssertNil(request.firstName)
    }

    // MARK: - TimeOffRequest employeeDisplayName

    func test_employeeDisplayName_fromNames() throws {
        let request = TimeOffRequest(
            id: 1, userId: 1, startDate: "2026-05-01", endDate: "2026-05-01",
            kind: .pto, status: .pending, firstName: "Bob", lastName: "Jones"
        )
        XCTAssertEqual(request.employeeDisplayName, "Bob Jones")
    }

    func test_employeeDisplayName_fallsBackToUserId() throws {
        let request = TimeOffRequest(
            id: 1, userId: 42, startDate: "2026-05-01", endDate: "2026-05-01",
            kind: .pto, status: .pending
        )
        XCTAssertEqual(request.employeeDisplayName, "User #42")
    }

    // MARK: - TimeOffKind display names

    func test_timeOffKind_displayNames() {
        XCTAssertEqual(TimeOffKind.pto.displayName,    "PTO")
        XCTAssertEqual(TimeOffKind.sick.displayName,   "Sick Leave")
        XCTAssertEqual(TimeOffKind.unpaid.displayName, "Unpaid")
    }

    // MARK: - ClockEntryEditRequest encode (round-trip)

    func test_clockEntryEditRequest_encodesAllFields() throws {
        let edit = ClockEntryEditRequest(
            clockIn: "2026-04-21T09:00:00Z",
            clockOut: "2026-04-21T17:00:00Z",
            notes: "Corrected",
            reason: "Manager fix"
        )
        let data = try JSONEncoder().encode(edit)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["clock_in"]  as? String, "2026-04-21T09:00:00Z")
        XCTAssertEqual(dict["clock_out"] as? String, "2026-04-21T17:00:00Z")
        XCTAssertEqual(dict["notes"]     as? String, "Corrected")
        XCTAssertEqual(dict["reason"]    as? String, "Manager fix")
    }

    func test_clockEntryEditRequest_encodesNilFieldsAsAbsent() throws {
        let edit = ClockEntryEditRequest(reason: "Reason only")
        let data = try JSONEncoder().encode(edit)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNil(dict["clock_in"])
        XCTAssertNil(dict["clock_out"])
        XCTAssertNil(dict["notes"])
        XCTAssertEqual(dict["reason"] as? String, "Reason only")
    }

    // MARK: - CreateTimeOffRequest encode

    func test_createTimeOffRequest_encodesCorrectly() throws {
        let req = CreateTimeOffRequest(
            startDate: "2026-05-01",
            endDate: "2026-05-03",
            kind: .sick,
            reason: "Doctor appointment"
        )
        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["start_date"] as? String, "2026-05-01")
        XCTAssertEqual(dict["end_date"]   as? String, "2026-05-03")
        XCTAssertEqual(dict["kind"]       as? String, "sick")
        XCTAssertEqual(dict["reason"]     as? String, "Doctor appointment")
    }

    func test_createTimeOffRequest_encodesNilReasonAsAbsent() throws {
        let req = CreateTimeOffRequest(startDate: "2026-05-01", endDate: "2026-05-01", kind: .pto)
        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(dict["reason"])
    }

    // MARK: - Helper

    private func decode<T: Decodable>(_ type: T.Type, from jsonString: String) throws -> T {
        let data = Data(jsonString.utf8)
        return try JSONDecoder().decode(type, from: data)
    }
}
