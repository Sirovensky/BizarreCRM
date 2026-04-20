import XCTest
@testable import Customers
import Networking

@MainActor
final class CustomerEditViewModelTests: XCTestCase {

    private func sampleDetail(id: Int64 = 7) -> CustomerDetail {
        // Decode from a minimal JSON so we don't need to track the exhaustive
        // memberwise initializer — CustomerDetail's public API is Decodable.
        let json = #"""
        {
          "id": \#(id),
          "first_name": "Ada",
          "last_name": "Lovelace",
          "email": "ada@example.com",
          "phone": null,
          "mobile": "5555550101",
          "address1": "1 Analytical Engine Way",
          "city": "London",
          "state": null,
          "country": "UK",
          "postcode": "NW1",
          "organization": "Analytic Society",
          "contact_person": null,
          "customer_group_name": null,
          "customer_tags": null,
          "comments": "VIP",
          "created_at": "2026-04-20",
          "updated_at": "2026-04-20",
          "phones": [],
          "emails": []
        }
        """#
        let decoder = JSONDecoder()
        return try! decoder.decode(CustomerDetail.self, from: Data(json.utf8))
    }

    func test_init_populatesFieldsFromCustomer() {
        let api = StubAPIClient(updateResult: .success(.init(id: 7)))
        let vm = CustomerEditViewModel(api: api, customer: sampleDetail())

        XCTAssertEqual(vm.firstName, "Ada")
        XCTAssertEqual(vm.lastName, "Lovelace")
        XCTAssertEqual(vm.email, "ada@example.com")
        XCTAssertEqual(vm.mobile, "5555550101")
        XCTAssertEqual(vm.organization, "Analytic Society")
        XCTAssertEqual(vm.notes, "VIP")
        XCTAssertEqual(vm.customerId, 7)
    }

    func test_submit_happyPath_setsDidSave() async {
        let api = StubAPIClient(updateResult: .success(.init(id: 7)))
        let vm = CustomerEditViewModel(api: api, customer: sampleDetail())
        vm.firstName = "Augusta"

        await vm.submit()

        XCTAssertTrue(vm.didSave)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertNil(vm.errorMessage)
    }

    func test_submit_withoutFirstName_setsValidationError() async {
        let api = StubAPIClient(updateResult: .success(.init(id: 7)))
        let vm = CustomerEditViewModel(api: api, customer: sampleDetail())
        vm.firstName = ""

        await vm.submit()

        XCTAssertFalse(vm.didSave)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertEqual(vm.errorMessage, "First name is required.")
    }

    func test_submit_networkError_queuesOffline() async {
        let urlError = URLError(.networkConnectionLost)
        let api = StubAPIClient(updateResult: .failure(urlError))
        let vm = CustomerEditViewModel(api: api, customer: sampleDetail())

        await vm.submit()

        XCTAssertTrue(vm.didSave)
        XCTAssertTrue(vm.queuedOffline)
        XCTAssertNil(vm.errorMessage)
    }

    func test_submit_serverError_surfacesMessage() async {
        let apiError = APITransportError.httpStatus(409, message: "Seeded record")
        let api = StubAPIClient(updateResult: .failure(apiError))
        let vm = CustomerEditViewModel(api: api, customer: sampleDetail())

        await vm.submit()

        XCTAssertFalse(vm.didSave)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertEqual(vm.errorMessage, "Seeded record")
    }
}
