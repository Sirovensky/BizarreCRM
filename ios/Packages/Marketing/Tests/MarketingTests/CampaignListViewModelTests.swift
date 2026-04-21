import Testing
import Foundation
@testable import Marketing

@Suite("CampaignListViewModel")
@MainActor
struct CampaignListViewModelTests {

    private func makeCampaign(id: String, status: CampaignStatus = .draft) -> Campaign {
        Campaign(id: id, name: "Campaign \(id)", status: status, template: "Hello", createdAt: Date())
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

    @Test("load populates campaigns from API")
    func loadPopulates() async {
        let mock = MockAPIClient()
        let campaigns = [makeCampaign(id: "1"), makeCampaign(id: "2", status: .sent)]
        await mock.setListResult(.success(CampaignListResponse(campaigns: campaigns, nextCursor: nil)))
        let vm = CampaignListViewModel(api: mock)
        await vm.load()
        #expect(vm.campaigns.count == 2)
        #expect(vm.errorMessage == nil)
        #expect(vm.hasMore == false)
    }

    @Test("load sets hasMore when cursor returned")
    func loadHasMore() async {
        let mock = MockAPIClient()
        await mock.setListResult(.success(CampaignListResponse(campaigns: [makeCampaign(id: "1")], nextCursor: "abc")))
        let vm = CampaignListViewModel(api: mock)
        await vm.load()
        #expect(vm.hasMore == true)
        #expect(vm.nextCursor == "abc")
    }

    @Test("load sets errorMessage on failure")
    func loadError() async {
        let mock = MockAPIClient()
        await mock.setListResult(.failure(URLError(.timedOut)))
        let vm = CampaignListViewModel(api: mock)
        await vm.load()
        #expect(vm.errorMessage != nil)
        #expect(vm.campaigns.isEmpty)
    }

    @Test("loadNextPage appends campaigns")
    func loadNextPage() async {
        let mock = MockAPIClient()
        // First page
        await mock.setListResult(.success(CampaignListResponse(
            campaigns: [makeCampaign(id: "1")],
            nextCursor: "cur2"
        )))
        let vm = CampaignListViewModel(api: mock)
        await vm.load()
        #expect(vm.campaigns.count == 1)

        // Second page
        await mock.setListResult(.success(CampaignListResponse(
            campaigns: [makeCampaign(id: "2"), makeCampaign(id: "3")],
            nextCursor: nil
        )))
        await vm.loadNextPage()
        #expect(vm.campaigns.count == 3)
        #expect(vm.hasMore == false)
    }

    @Test("loadNextPage skips when no cursor")
    func loadNextPageSkipsWithoutCursor() async {
        let mock = MockAPIClient()
        await mock.setListResult(.success(CampaignListResponse(campaigns: [makeCampaign(id: "1")], nextCursor: nil)))
        let vm = CampaignListViewModel(api: mock)
        await vm.load()
        // nextCursor is nil, so should no-op
        await vm.loadNextPage()
        #expect(vm.campaigns.count == 1)
    }
}

extension MockAPIClient {
    func setListResult(_ result: Result<CampaignListResponse, Error>) async {
        campaignListResult = result
    }
}
