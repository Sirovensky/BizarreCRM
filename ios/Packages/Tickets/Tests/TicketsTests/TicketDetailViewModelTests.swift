import XCTest
@testable import Tickets
import Networking

// MARK: - Stub repository

private actor StubTicketRepository: TicketRepository {
    var detailResult: Result<TicketDetail, Error>
    var deleteError: Error?
    var duplicateResult: Result<DuplicateTicketResponse, Error>
    var convertResult: Result<ConvertToInvoiceResponse, Error>
    var deletedIds: [Int64] = []

    init(
        detailResult: Result<TicketDetail, Error> = .failure(APITransportError.noBaseURL),
        deleteError: Error? = nil,
        duplicateResult: Result<DuplicateTicketResponse, Error> = .failure(APITransportError.noBaseURL),
        convertResult: Result<ConvertToInvoiceResponse, Error> = .failure(APITransportError.noBaseURL)
    ) {
        self.detailResult = detailResult
        self.deleteError = deleteError
        self.duplicateResult = duplicateResult
        self.convertResult = convertResult
    }

    func list(filter: TicketListFilter, keyword: String?, sort: TicketSortOrder) async throws -> [TicketSummary] {
        return []
    }

    func detail(id: Int64) async throws -> TicketDetail {
        switch detailResult {
        case .success(let d): return d
        case .failure(let e): throw e
        }
    }

    func delete(id: Int64) async throws {
        deletedIds.append(id)
        if let err = deleteError { throw err }
    }

    func duplicate(id: Int64) async throws -> DuplicateTicketResponse {
        switch duplicateResult {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    func convertToInvoice(id: Int64) async throws -> ConvertToInvoiceResponse {
        switch convertResult {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }
}

// MARK: - Helper

private func makeDetail(id: Int64 = 42) -> TicketDetail {
    let json = """
    { "id": \(id), "order_id": "T-42" }
    """
    let decoder = JSONDecoder()
    return try! decoder.decode(TicketDetail.self, from: Data(json.utf8))
}

// MARK: - Tests

@MainActor
final class TicketDetailViewModelTests: XCTestCase {

    // §4.4 — Successful delete sets wasDeleted.
    func test_delete_success_setsWasDeleted() async {
        let repo = StubTicketRepository(deleteError: nil)
        let vm = TicketDetailViewModel(repo: repo, ticketId: 42)
        vm.state = .loaded(makeDetail(id: 42))
        await vm.deleteTicket()
        XCTAssertTrue(vm.wasDeleted, "wasDeleted should be true after successful delete")
        XCTAssertNil(vm.actionErrorMessage, "No error expected on successful delete")
    }

    // §4.4 — Delete failure sets actionErrorMessage, wasDeleted stays false.
    func test_delete_failure_setsError() async {
        let repo = StubTicketRepository(deleteError: APITransportError.noBaseURL)
        let vm = TicketDetailViewModel(repo: repo, ticketId: 42)
        vm.state = .loaded(makeDetail(id: 42))
        await vm.deleteTicket()
        XCTAssertFalse(vm.wasDeleted, "wasDeleted must be false on error")
        XCTAssertNotNil(vm.actionErrorMessage, "Error message should be populated")
    }

    // §4.4 — Delete clears isDeleting after completion.
    func test_delete_clearsIsDeleting() async {
        let repo = StubTicketRepository(deleteError: nil)
        let vm = TicketDetailViewModel(repo: repo, ticketId: 5)
        vm.state = .loaded(makeDetail(id: 5))
        await vm.deleteTicket()
        XCTAssertFalse(vm.isDeleting, "isDeleting must be false after completion")
    }

    // §4.5 — Successful duplicate sets duplicatedTicketId.
    func test_duplicate_success_setsId() async {
        let response = DuplicateTicketResponse(id: 99, ticketId: nil)
        let repo = StubTicketRepository(duplicateResult: .success(response))
        let vm = TicketDetailViewModel(repo: repo, ticketId: 42)
        await vm.duplicateTicket()
        XCTAssertEqual(vm.duplicatedTicketId, 99)
        XCTAssertNil(vm.actionErrorMessage)
    }

    // §4.5 — Duplicate failure sets actionErrorMessage.
    func test_duplicate_failure_setsError() async {
        let repo = StubTicketRepository(duplicateResult: .failure(APITransportError.noBaseURL))
        let vm = TicketDetailViewModel(repo: repo, ticketId: 42)
        await vm.duplicateTicket()
        XCTAssertNil(vm.duplicatedTicketId)
        XCTAssertNotNil(vm.actionErrorMessage)
    }

    // §4.5 — Successful convertToInvoice sets convertedInvoiceId.
    func test_convertToInvoice_success_setsId() async {
        let response = ConvertToInvoiceResponse(invoiceId: 77, id: nil)
        let repo = StubTicketRepository(convertResult: .success(response))
        let vm = TicketDetailViewModel(repo: repo, ticketId: 42)
        await vm.convertToInvoice()
        XCTAssertEqual(vm.convertedInvoiceId, 77)
        XCTAssertNil(vm.actionErrorMessage)
    }

    // §4.5 — Convert failure sets actionErrorMessage.
    func test_convertToInvoice_failure_setsError() async {
        let repo = StubTicketRepository(convertResult: .failure(APITransportError.noBaseURL))
        let vm = TicketDetailViewModel(repo: repo, ticketId: 42)
        await vm.convertToInvoice()
        XCTAssertNil(vm.convertedInvoiceId)
        XCTAssertNotNil(vm.actionErrorMessage)
    }

    // §4.4 — Load with 409 string in error sets concurrentEditBanner.
    func test_load_409error_setsConcurrentEditBanner() async {
        struct FakeError: LocalizedError {
            var errorDescription: String? { "HTTP 409 conflict" }
        }
        let repo = StubTicketRepository(detailResult: .failure(FakeError()))
        let vm = TicketDetailViewModel(repo: repo, ticketId: 1)
        await vm.load()
        XCTAssertTrue(vm.concurrentEditBanner, "409 in error message should set banner")
    }
}
