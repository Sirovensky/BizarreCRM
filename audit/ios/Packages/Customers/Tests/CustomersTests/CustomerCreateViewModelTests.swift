import XCTest
@testable import Customers
import Networking

@MainActor
final class CustomerCreateViewModelTests: XCTestCase {

    // Happy path: the API returns a created id; vm.createdId is populated.
    func test_submit_happyPath_populatesCreatedId() async {
        let api = StubAPIClient(createResult: .success(.init(id: 42)))
        let vm = CustomerCreateViewModel(api: api)
        vm.firstName = "Ada"
        vm.lastName = "Lovelace"

        await vm.submit()

        XCTAssertEqual(vm.createdId, 42)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertNil(vm.errorMessage)
    }

    // Validation: without a first name, submit bails early with a message.
    func test_submit_withoutFirstName_setsValidationError() async {
        let api = StubAPIClient(createResult: .success(.init(id: 1)))
        let vm = CustomerCreateViewModel(api: api)
        vm.firstName = ""

        await vm.submit()

        XCTAssertNil(vm.createdId)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertEqual(vm.errorMessage, "First name is required.")
    }

    // Offline: a transport error is redirected into the queue, createdId is
    // set to the pending sentinel and no user-facing error surfaces.
    func test_submit_networkError_queuesOffline() async {
        let urlError = URLError(.notConnectedToInternet)
        let api = StubAPIClient(createResult: .failure(urlError))
        let vm = CustomerCreateViewModel(api: api)
        vm.firstName = "Grace"

        await vm.submit()

        XCTAssertEqual(vm.createdId, PendingSyncCustomerId)
        XCTAssertTrue(vm.queuedOffline)
        XCTAssertNil(vm.errorMessage)
    }

    // Non-network 4xx-style errors surface verbatim — we do NOT queue them,
    // because the server has told us the payload is bad.
    func test_submit_serverError_surfacesMessage() async {
        let apiError = APITransportError.httpStatus(400, message: "Duplicate email")
        let api = StubAPIClient(createResult: .failure(apiError))
        let vm = CustomerCreateViewModel(api: api)
        vm.firstName = "Hedy"

        await vm.submit()

        XCTAssertNil(vm.createdId)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertEqual(vm.errorMessage, "Duplicate email")
    }
}
