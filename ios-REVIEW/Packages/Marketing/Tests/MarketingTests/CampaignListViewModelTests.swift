import Testing
import Foundation
@testable import Marketing

/// Legacy CampaignListViewModel tests, updated to use server-row path.
@Suite("CampaignListViewModel")
@MainActor
struct CampaignListViewModelTests {

    private func makeRow(id: Int = 1, status: String = "draft") -> CampaignServerRow {
        makeCampaignServerRow(id: id, status: status)
    }

    @Test("initial state is empty")
    func initialState() {
        let mock = MockAPIClient()
        let vm = CampaignListViewModel(api: mock)
        #expect(vm.campaigns.isEmpty)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.hasMore == false)
    }

    @Test("load populates campaigns from server rows")
    func loadPopulates() async {
        let mock = MockAPIClient()
        let rows = [makeRow(id: 1), makeRow(id: 2, status: "active")]
        await mock.setCampaignServerListResult(.success(rows))
        let vm = CampaignListViewModel(api: mock)
        await vm.load()
        #expect(vm.campaigns.count == 2)
        #expect(vm.errorMessage == nil)
        #expect(vm.hasMore == false)
    }

    @Test("load with filter .all returns all")
    func loadAllFilter() async {
        let mock = MockAPIClient()
        let rows = [makeRow(id: 1, status: "active"), makeRow(id: 2, status: "archived")]
        await mock.setCampaignServerListResult(.success(rows))
        let vm = CampaignListViewModel(api: mock)
        await vm.load()
        vm.filter = .all
        #expect(vm.campaigns.count == 2)
    }

    @Test("load sets errorMessage on failure")
    func loadError() async {
        let mock = MockAPIClient()
        await mock.setCampaignServerListResult(.failure(URLError(.timedOut)))
        let vm = CampaignListViewModel(api: mock)
        await vm.load()
        #expect(vm.errorMessage != nil)
        #expect(vm.campaigns.isEmpty)
    }

    @Test("loadNextPage is a no-op (server returns all in one call)")
    func loadNextPageNoOp() async {
        let mock = MockAPIClient()
        let rows = [makeRow(id: 1)]
        await mock.setCampaignServerListResult(.success(rows))
        let vm = CampaignListViewModel(api: mock)
        await vm.load()
        // nextPage is a no-op — campaign count unchanged
        await vm.loadNextPage()
        #expect(vm.campaigns.count == 1)
    }
}

extension MockAPIClient {
    /// Compat helper for old test shape.
    func setListResult(_ result: Result<CampaignListResponse, Error>) async {
        campaignListResult = result
    }
}
