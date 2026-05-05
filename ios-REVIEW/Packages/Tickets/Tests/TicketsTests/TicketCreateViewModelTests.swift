import XCTest
@testable import Tickets
import Networking
import Customers

@MainActor
final class TicketCreateViewModelTests: XCTestCase {

    /// Decode a minimal `CustomerSummary` JSON — the public type has no
    /// public memberwise init, so we lean on Decodable here.
    private func sampleCustomer(id: Int64 = 1) -> CustomerSummary {
        let json = #"""
        {
          "id": \#(id),
          "first_name": "Ada",
          "last_name": "Lovelace",
          "phone": "5555550101",
          "email": "ada@example.com"
        }
        """#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(CustomerSummary.self, from: Data(json.utf8))
    }

    // Happy path: a picked customer + the API returning a created id
    // populates vm.createdId and never touches the offline queue.
    func test_submit_happyPath_populatesCreatedId() async {
        let api = StubAPIClient(createResult: .success(.init(id: 99)))
        let vm = TicketCreateViewModel(api: api)
        vm.selectedCustomer = sampleCustomer(id: 1)
        vm.deviceName = "iPhone 14"
        vm.priceText = "150"

        await vm.submit()

        XCTAssertEqual(vm.createdId, 99)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertNil(vm.errorMessage)
    }

    // Validation: submit without a customer bails early with a message
    // and never hits the API.
    func test_submit_withoutCustomer_setsValidationError() async {
        let api = StubAPIClient(createResult: .success(.init(id: 1)))
        let vm = TicketCreateViewModel(api: api)
        vm.deviceName = "Some device"

        await vm.submit()

        XCTAssertNil(vm.createdId)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertEqual(vm.errorMessage, "Pick a customer first.")
    }

    // Offline: URL error redirected into the queue; createdId is the
    // pending sentinel, no user-facing error surfaces.
    func test_submit_networkError_queuesOffline() async {
        let urlError = URLError(.notConnectedToInternet)
        let api = StubAPIClient(createResult: .failure(urlError))
        let vm = TicketCreateViewModel(api: api)
        vm.selectedCustomer = sampleCustomer()
        vm.deviceName = "iPhone 15"

        await vm.submit()

        XCTAssertEqual(vm.createdId, PendingSyncTicketId)
        XCTAssertTrue(vm.queuedOffline)
        XCTAssertNil(vm.errorMessage)
    }

    // Non-network 4xx-style errors surface verbatim — we do NOT queue
    // those because the server has told us the payload is bad and a
    // retry would 4xx again.
    func test_submit_serverError_surfacesMessage() async {
        let apiError = APITransportError.httpStatus(403, message: "No permission")
        let api = StubAPIClient(createResult: .failure(apiError))
        let vm = TicketCreateViewModel(api: api)
        vm.selectedCustomer = sampleCustomer()

        await vm.submit()

        XCTAssertNil(vm.createdId)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertEqual(vm.errorMessage, "No permission")
    }

    // Price parsing accepts a decimal comma (European UI habit) — matches
    // the replacement logic in TicketCreateViewModel.price.
    func test_price_parsesCommaAsDecimal() {
        let api = StubAPIClient(createResult: .success(.init(id: 1)))
        let vm = TicketCreateViewModel(api: api)
        vm.priceText = "12,50"

        XCTAssertEqual(vm.price, 12.50, accuracy: 0.001)
    }
}
