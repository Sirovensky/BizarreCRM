import XCTest
@testable import Tickets
@testable import Networking

/// §4 — TicketSplitViewModel unit tests.
@MainActor
final class TicketSplitViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeDetail(deviceCount: Int = 3) -> TicketDetail {
        let devicesJSON = (1...deviceCount).map { i in
            """
            {"id": \(i), "name": "Device \(i)"}
            """
        }.joined(separator: ",")
        let json = """
        {
          "id": 10,
          "order_id": "T-010",
          "devices": [\(devicesJSON)]
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(TicketDetail.self, from: json)
    }

    // MARK: - Load

    func test_load_setsLoadedState() async {
        let detail = makeDetail()
        let repo = SplitStubRepo(detail: detail)
        let api = ExtendedStubAPIClient()
        let vm = TicketSplitViewModel(ticketId: 10, repo: repo, api: api)

        await vm.load()

        if case .loaded = vm.state {
            XCTAssertEqual(vm.ticket?.id, 10)
        } else {
            XCTFail("Expected .loaded")
        }
    }

    func test_load_failure_setsFailedState() async {
        let repo = SplitStubRepo(shouldFail: true)
        let api = ExtendedStubAPIClient()
        let vm = TicketSplitViewModel(ticketId: 99, repo: repo, api: api)

        await vm.load()

        if case .failed = vm.state { /* pass */ } else {
            XCTFail("Expected .failed")
        }
    }

    // MARK: - Selection

    func test_toggleDevice_selectsDevice() async {
        let detail = makeDetail()
        let repo = SplitStubRepo(detail: detail)
        let api = ExtendedStubAPIClient()
        let vm = TicketSplitViewModel(ticketId: 10, repo: repo, api: api)
        await vm.load()

        vm.toggleDevice(1)

        XCTAssertTrue(vm.isSelected(1))
    }

    func test_toggleDevice_deselectsDevice() async {
        let detail = makeDetail()
        let repo = SplitStubRepo(detail: detail)
        let api = ExtendedStubAPIClient()
        let vm = TicketSplitViewModel(ticketId: 10, repo: repo, api: api)
        await vm.load()

        vm.toggleDevice(1)
        vm.toggleDevice(1)

        XCTAssertFalse(vm.isSelected(1))
    }

    func test_isSelected_falseByDefault() async {
        let detail = makeDetail()
        let repo = SplitStubRepo(detail: detail)
        let api = ExtendedStubAPIClient()
        let vm = TicketSplitViewModel(ticketId: 10, repo: repo, api: api)
        await vm.load()

        XCTAssertFalse(vm.isSelected(1))
        XCTAssertFalse(vm.isSelected(2))
    }

    // MARK: - canSplit

    func test_canSplit_falseWhenNothingSelected() async {
        let detail = makeDetail()
        let repo = SplitStubRepo(detail: detail)
        let api = ExtendedStubAPIClient()
        let vm = TicketSplitViewModel(ticketId: 10, repo: repo, api: api)
        await vm.load()

        XCTAssertFalse(vm.canSplit)
    }

    func test_canSplit_falseWhenAllSelected() async {
        let detail = makeDetail(deviceCount: 2)
        let repo = SplitStubRepo(detail: detail)
        let api = ExtendedStubAPIClient()
        let vm = TicketSplitViewModel(ticketId: 10, repo: repo, api: api)
        await vm.load()

        vm.toggleDevice(1)
        vm.toggleDevice(2)

        XCTAssertFalse(vm.canSplit)
    }

    func test_canSplit_trueWhenPartialSelection() async {
        let detail = makeDetail(deviceCount: 3)
        let repo = SplitStubRepo(detail: detail)
        let api = ExtendedStubAPIClient()
        let vm = TicketSplitViewModel(ticketId: 10, repo: repo, api: api)
        await vm.load()

        vm.toggleDevice(1)

        XCTAssertTrue(vm.canSplit)
    }

    // MARK: - Split

    func test_split_success_setsSuccessState() async {
        let detail = makeDetail(deviceCount: 3)
        let repo = SplitStubRepo(detail: detail)
        let api = ExtendedStubAPIClient()
        await api.setSplitResult(.success(TicketSplitResponse(originalTicketId: 10, newTicketIds: ["T-011"])))
        let vm = TicketSplitViewModel(ticketId: 10, repo: repo, api: api)
        await vm.load()
        vm.toggleDevice(1)

        await vm.split()

        if case .success(let origId, let newIds) = vm.state {
            XCTAssertEqual(origId, 10)
            XCTAssertEqual(newIds, ["T-011"])
        } else {
            XCTFail("Expected .success")
        }
    }

    func test_split_apiError_setsFailedState() async {
        let detail = makeDetail(deviceCount: 3)
        let repo = SplitStubRepo(detail: detail)
        let api = ExtendedStubAPIClient()
        await api.setSplitResult(.failure(APITransportError.noBaseURL))
        let vm = TicketSplitViewModel(ticketId: 10, repo: repo, api: api)
        await vm.load()
        vm.toggleDevice(1)

        await vm.split()

        if case .failed = vm.state { /* pass */ } else {
            XCTFail("Expected .failed")
        }
    }

    func test_split_whenCannotSplit_doesNothing() async {
        let detail = makeDetail(deviceCount: 2)
        let repo = SplitStubRepo(detail: detail)
        let api = ExtendedStubAPIClient()
        let vm = TicketSplitViewModel(ticketId: 10, repo: repo, api: api)
        await vm.load()
        // Select all — canSplit is false
        vm.toggleDevice(1)
        vm.toggleDevice(2)

        await vm.split()

        // canSplit is false → split is no-op → state stays .loaded
        if case .loaded = vm.state { /* pass */ } else {
            XCTFail("Expected .loaded (no-op)")
        }
    }

    func test_selectedCount_tracksSelection() async {
        let detail = makeDetail(deviceCount: 3)
        let repo = SplitStubRepo(detail: detail)
        let api = ExtendedStubAPIClient()
        let vm = TicketSplitViewModel(ticketId: 10, repo: repo, api: api)
        await vm.load()

        XCTAssertEqual(vm.selectedCount, 0)
        vm.toggleDevice(1)
        XCTAssertEqual(vm.selectedCount, 1)
        vm.toggleDevice(2)
        XCTAssertEqual(vm.selectedCount, 2)
        vm.toggleDevice(1) // deselect
        XCTAssertEqual(vm.selectedCount, 1)
    }
}

// MARK: - Stub repo

private final class SplitStubRepo: TicketRepository {
    let detail: TicketDetail?
    let shouldFail: Bool

    init(detail: TicketDetail? = nil, shouldFail: Bool = false) {
        self.detail = detail
        self.shouldFail = shouldFail
    }

    func list(filter: TicketListFilter, keyword: String?, sort: TicketSortOrder) async throws -> [TicketSummary] { [] }
    func detail(id: Int64) async throws -> TicketDetail {
        if shouldFail { throw SplitRepoError.boom }
        guard let d = detail else { throw SplitRepoError.boom }
        return d
    }
    func delete(id: Int64) async throws { throw SplitRepoError.boom }
    func duplicate(id: Int64) async throws -> DuplicateTicketResponse { throw SplitRepoError.boom }
    func convertToInvoice(id: Int64) async throws -> ConvertToInvoiceResponse { throw SplitRepoError.boom }
    private enum SplitRepoError: Error { case boom }
}

extension ExtendedStubAPIClient {
    func setSplitResult(_ result: Result<TicketSplitResponse, Error>) {
        splitResult = result
    }
}
