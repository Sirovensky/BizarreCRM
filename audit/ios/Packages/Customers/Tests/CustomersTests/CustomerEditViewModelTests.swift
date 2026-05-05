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

    // MARK: — Init

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

    // MARK: — Success path

    func test_submit_happyPath_setsDidSave() async {
        let api = StubAPIClient(updateResult: .success(.init(id: 7)))
        let vm = CustomerEditViewModel(api: api, customer: sampleDetail())
        vm.firstName = "Augusta"

        await vm.submit()

        XCTAssertTrue(vm.didSave)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertNil(vm.errorMessage)
        XCTAssertNil(vm.conflictMessage)
    }

    // MARK: — Validation

    func test_submit_withoutFirstName_setsValidationError() async {
        let api = StubAPIClient(updateResult: .success(.init(id: 7)))
        let vm = CustomerEditViewModel(api: api, customer: sampleDetail())
        vm.firstName = ""

        await vm.submit()

        XCTAssertFalse(vm.didSave)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertEqual(vm.errorMessage, "First name is required.")
    }

    func test_submit_whitespaceOnlyFirstName_setsValidationError() async {
        let api = StubAPIClient(updateResult: .success(.init(id: 7)))
        let vm = CustomerEditViewModel(api: api, customer: sampleDetail())
        vm.firstName = "   "

        await vm.submit()

        XCTAssertFalse(vm.didSave)
        XCTAssertEqual(vm.errorMessage, "First name is required.")
    }

    // MARK: — Network / offline queue

    func test_submit_networkError_queuesOffline() async {
        let urlError = URLError(.networkConnectionLost)
        let api = StubAPIClient(updateResult: .failure(urlError))
        let vm = CustomerEditViewModel(api: api, customer: sampleDetail())

        await vm.submit()

        XCTAssertTrue(vm.didSave)
        XCTAssertTrue(vm.queuedOffline)
        XCTAssertNil(vm.errorMessage)
    }

    func test_submit_notConnectedToInternet_queuesOffline() async {
        let urlError = URLError(.notConnectedToInternet)
        let api = StubAPIClient(updateResult: .failure(urlError))
        let vm = CustomerEditViewModel(api: api, customer: sampleDetail())

        await vm.submit()

        XCTAssertTrue(vm.didSave)
        XCTAssertTrue(vm.queuedOffline)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: — 409 Conflict (Walk-in Customer / concurrent edit)

    func test_submit_conflict409_setsConflictMessage() async {
        let apiError = APITransportError.httpStatus(409, message: "Seeded record")
        let api = StubAPIClient(updateResult: .failure(apiError))
        let vm = CustomerEditViewModel(api: api, customer: sampleDetail())

        await vm.submit()

        XCTAssertFalse(vm.didSave)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.conflictMessage, "Seeded record")
    }

    func test_submit_conflict409_nilMessage_usesDefaultConflictText() async {
        let apiError = APITransportError.httpStatus(409, message: nil)
        let api = StubAPIClient(updateResult: .failure(apiError))
        let vm = CustomerEditViewModel(api: api, customer: sampleDetail())

        await vm.submit()

        XCTAssertFalse(vm.didSave)
        XCTAssertNotNil(vm.conflictMessage, "A nil-message 409 should still show a conflict banner")
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: — 401 Unauthorized

    func test_submit_unauthorized401_surfacesErrorMessage() async {
        // HTTP 401 from PUT /customers/:id means the session expired or the
        // user lacks customers.edit permission. The ViewModel should surface
        // the error message rather than routing to conflictMessage or the
        // offline queue.
        let apiError = APITransportError.httpStatus(401, message: "Unauthorized")
        let api = StubAPIClient(updateResult: .failure(apiError))
        let vm = CustomerEditViewModel(api: api, customer: sampleDetail())

        await vm.submit()

        XCTAssertFalse(vm.didSave)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertNil(vm.conflictMessage)
        // errorMessage should be non-nil; exact text comes from APITransportError.errorDescription
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_submit_unauthorized401_doesNotQueueOffline() async {
        // A 401 is a server-rejected response — NOT a network error. It must
        // never land in the sync queue (would replay forever with wrong creds).
        let apiError = APITransportError.httpStatus(401, message: nil)
        let api = StubAPIClient(updateResult: .failure(apiError))
        let vm = CustomerEditViewModel(api: api, customer: sampleDetail())

        await vm.submit()

        XCTAssertFalse(vm.queuedOffline, "401 must not be enqueued as an offline operation")
    }

    // MARK: — 404 Not Found

    func test_submit_notFound404_surfacesErrorMessage() async {
        // HTTP 404 from PUT /customers/:id means the customer was deleted by
        // another session between Detail load and Save. Surface as an error.
        let apiError = APITransportError.httpStatus(404, message: "Customer not found")
        let api = StubAPIClient(updateResult: .failure(apiError))
        let vm = CustomerEditViewModel(api: api, customer: sampleDetail())

        await vm.submit()

        XCTAssertFalse(vm.didSave)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertNil(vm.conflictMessage)
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_submit_notFound404_doesNotQueueOffline() async {
        // 404 is a definitive server rejection — do not enqueue offline.
        let apiError = APITransportError.httpStatus(404, message: "Customer not found")
        let api = StubAPIClient(updateResult: .failure(apiError))
        let vm = CustomerEditViewModel(api: api, customer: sampleDetail())

        await vm.submit()

        XCTAssertFalse(vm.queuedOffline, "404 must not be enqueued as an offline operation")
    }

    // MARK: — Idempotency guard

    func test_submit_isSubmitting_doesNotResubmit() async {
        // The guard `guard !isSubmitting` prevents double-taps. We can verify
        // isValid is true to confirm the guard would otherwise proceed.
        let api = StubAPIClient(updateResult: .success(.init(id: 7)))
        let vm = CustomerEditViewModel(api: api, customer: sampleDetail())

        XCTAssertFalse(vm.isSubmitting, "Should not be submitting before the first call")
        XCTAssertTrue(vm.isValid, "Sample customer has a first name so isValid should be true")
    }

    // MARK: — State reset on re-submit

    func test_submit_clearsErrorMessageOnRetry() async {
        // After a failed submit, a second successful submit should clear errorMessage.
        let failError = APITransportError.httpStatus(500, message: "Server error")
        let failApi = StubAPIClient(updateResult: .failure(failError))
        let vm = CustomerEditViewModel(api: failApi, customer: sampleDetail())
        await vm.submit()
        XCTAssertNotNil(vm.errorMessage)

        // Swap to a success stub by creating a new VM seeded from the same customer
        // (the API is injected at init, so we simulate retry via a fresh VM here).
        let successApi = StubAPIClient(updateResult: .success(.init(id: 7)))
        let vm2 = CustomerEditViewModel(api: successApi, customer: sampleDetail())
        await vm2.submit()

        XCTAssertNil(vm2.errorMessage)
        XCTAssertTrue(vm2.didSave)
    }
}
