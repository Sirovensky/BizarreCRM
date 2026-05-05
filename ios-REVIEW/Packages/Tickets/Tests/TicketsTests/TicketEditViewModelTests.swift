import XCTest
@testable import Tickets
import Networking

@MainActor
final class TicketEditViewModelTests: XCTestCase {

    /// Minimal `TicketDetail` — uses the custom Decodable init to default
    /// the array fields, so the JSON need only carry the scalar fields we
    /// actually assert on.
    private func sampleTicket(
        id: Int64 = 7,
        discount: Double? = nil,
        discountReason: String? = nil,
        howDidUFindUs: String? = nil
    ) -> TicketDetail {
        let discountJSON = discount.map { "\($0)" } ?? "null"
        let reasonJSON = discountReason.map { "\"\($0)\"" } ?? "null"
        let howJSON = howDidUFindUs.map { "\"\($0)\"" } ?? "null"
        let json = #"""
        {
          "id": \#(id),
          "order_id": "T-1007",
          "discount": \#(discountJSON),
          "discount_reason": \#(reasonJSON),
          "how_did_u_find_us": \#(howJSON)
        }
        """#
        let decoder = JSONDecoder()
        return try! decoder.decode(TicketDetail.self, from: Data(json.utf8))
    }

    // Init pulls the current ticket metadata into the form fields so the
    // UI opens pre-populated. Discount renders without a trailing "0.00".
    func test_init_populatesFieldsFromTicket() {
        let api = StubAPIClient(updateResult: .success(.init(id: 7)))
        let vm = TicketEditViewModel(
            api: api,
            ticket: sampleTicket(
                discount: 15,
                discountReason: "Loyalty",
                howDidUFindUs: "Google"
            )
        )

        XCTAssertEqual(vm.ticketId, 7)
        XCTAssertEqual(vm.discountText, "15")
        XCTAssertEqual(vm.discountReason, "Loyalty")
        XCTAssertEqual(vm.referralSource, "Google")
    }

    // Nil discount on the server becomes an empty field on the form (no
    // "0" ghost value distracting the user).
    func test_init_nilDiscountLeavesFieldEmpty() {
        let api = StubAPIClient(updateResult: .success(.init(id: 7)))
        let vm = TicketEditViewModel(api: api, ticket: sampleTicket(discount: nil))

        XCTAssertEqual(vm.discountText, "")
    }

    // Happy path: submit fires the PUT and flips didSave.
    func test_submit_happyPath_setsDidSave() async {
        let api = StubAPIClient(updateResult: .success(.init(id: 7)))
        let vm = TicketEditViewModel(api: api, ticket: sampleTicket())
        vm.discountText = "25"
        vm.discountReason = "VIP"

        await vm.submit()

        XCTAssertTrue(vm.didSave)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertNil(vm.errorMessage)
    }

    // A non-numeric discount is a client-side validation error — we don't
    // even hit the API, and didSave stays false.
    func test_submit_nonNumericDiscount_setsValidationError() async {
        let api = StubAPIClient(updateResult: .success(.init(id: 7)))
        let vm = TicketEditViewModel(api: api, ticket: sampleTicket())
        vm.discountText = "abc"

        await vm.submit()

        XCTAssertFalse(vm.didSave)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertEqual(vm.errorMessage, "Discount must be a number.")
    }

    // Offline: URL error is redirected into the queue; didSave flips
    // because the user's intent is captured, queuedOffline signals the
    // UI to show the "will sync" banner.
    func test_submit_networkError_queuesOffline() async {
        let urlError = URLError(.networkConnectionLost)
        let api = StubAPIClient(updateResult: .failure(urlError))
        let vm = TicketEditViewModel(api: api, ticket: sampleTicket())
        vm.discountText = "5"

        await vm.submit()

        XCTAssertTrue(vm.didSave)
        XCTAssertTrue(vm.queuedOffline)
        XCTAssertNil(vm.errorMessage)
    }

    // A 409 from the server (optimistic-lock conflict from the PUT route)
    // surfaces verbatim. We do NOT queue, because a retry would just 409
    // again until the client refreshes.
    func test_submit_serverError_surfacesMessage() async {
        let apiError = APITransportError.httpStatus(
            409,
            message: "Ticket was modified by another user."
        )
        let api = StubAPIClient(updateResult: .failure(apiError))
        let vm = TicketEditViewModel(api: api, ticket: sampleTicket())

        await vm.submit()

        XCTAssertFalse(vm.didSave)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertEqual(vm.errorMessage, "Ticket was modified by another user.")
    }

    // An empty discount field is a valid no-op — we still call the API
    // (other fields may be set) but send `nil` for the discount.
    func test_isValid_whenDiscountFieldIsEmpty() {
        let api = StubAPIClient(updateResult: .success(.init(id: 7)))
        let vm = TicketEditViewModel(api: api, ticket: sampleTicket())
        vm.discountText = ""

        XCTAssertTrue(vm.isValid)
        XCTAssertNil(vm.parsedDiscount)
    }
}
