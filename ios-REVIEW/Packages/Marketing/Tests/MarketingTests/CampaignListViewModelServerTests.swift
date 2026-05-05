import Testing
import Foundation
@testable import Marketing

/// Tests for the server-backed CampaignListViewModel (real endpoint).
@Suite("CampaignListViewModel server-backed")
@MainActor
struct CampaignListViewModelServerTests {

    private func makeRow(id: Int, status: String = "draft") -> CampaignServerRow {
        makeCampaignServerRow(id: id, status: status)
    }

    @Test("load populates allCampaigns from server rows")
    func loadPopulatesAllCampaigns() async {
        let mock = MockAPIClient()
        let rows = [makeRow(id: 1, status: "active"), makeRow(id: 2, status: "draft")]
        await mock.setCampaignServerListResult(.success(rows))
        let vm = CampaignListViewModel(api: mock)
        await vm.load()
        #expect(vm.allCampaigns.count == 2)
        #expect(vm.errorMessage == nil)
    }

    @Test("load sets errorMessage on failure")
    func loadError() async {
        let mock = MockAPIClient()
        await mock.setCampaignServerListResult(.failure(URLError(.timedOut)))
        let vm = CampaignListViewModel(api: mock)
        await vm.load()
        #expect(vm.errorMessage != nil)
        #expect(vm.allCampaigns.isEmpty)
    }

    @Test("filter .active returns only active + sending campaigns")
    func filterActive() async {
        let mock = MockAPIClient()
        let rows = [
            makeRow(id: 1, status: "active"),
            makeRow(id: 2, status: "draft"),
            makeRow(id: 3, status: "archived")
        ]
        await mock.setCampaignServerListResult(.success(rows))
        let vm = CampaignListViewModel(api: mock)
        await vm.load()
        vm.filter = .active
        #expect(vm.campaigns.count == 1)
        #expect(vm.campaigns[0].serverRowId == 1)
    }

    @Test("filter .scheduled returns draft campaigns")
    func filterScheduled() async {
        let mock = MockAPIClient()
        let rows = [
            makeRow(id: 1, status: "draft"),
            makeRow(id: 2, status: "active"),
            makeRow(id: 3, status: "archived")
        ]
        await mock.setCampaignServerListResult(.success(rows))
        let vm = CampaignListViewModel(api: mock)
        await vm.load()
        vm.filter = .scheduled
        #expect(vm.campaigns.count == 1)
        #expect(vm.campaigns[0].serverRowId == 1)
    }

    @Test("filter .past returns archived campaigns")
    func filterPast() async {
        let mock = MockAPIClient()
        let rows = [
            makeRow(id: 1, status: "archived"),
            makeRow(id: 2, status: "active"),
            makeRow(id: 3, status: "paused")
        ]
        await mock.setCampaignServerListResult(.success(rows))
        let vm = CampaignListViewModel(api: mock)
        await vm.load()
        vm.filter = .past
        #expect(vm.campaigns.count == 2)
    }

    @Test("filter .all returns all campaigns")
    func filterAll() async {
        let mock = MockAPIClient()
        let rows = [makeRow(id: 1), makeRow(id: 2), makeRow(id: 3)]
        await mock.setCampaignServerListResult(.success(rows))
        let vm = CampaignListViewModel(api: mock)
        await vm.load()
        vm.filter = .all
        #expect(vm.campaigns.count == 3)
    }

    @Test("delete removes campaign from allCampaigns")
    func deleteRemovesCampaign() async {
        let mock = MockAPIClient()
        let rows = [makeRow(id: 1), makeRow(id: 2)]
        await mock.setCampaignServerListResult(.success(rows))
        let vm = CampaignListViewModel(api: mock)
        await vm.load()
        #expect(vm.allCampaigns.count == 2)
        await vm.delete(id: 1)
        #expect(vm.allCampaigns.count == 1)
        #expect(vm.allCampaigns[0].serverRowId == 2)
    }

    @Test("Campaign.from correctly maps server row")
    func campaignFromServerRow() {
        let row = makeCampaignServerRow(
            id: 7, name: "Flash Sale",
            status: "active", type: "winback", channel: "email",
            sentCount: 100, repliedCount: 5, convertedCount: 3
        )
        let campaign = Campaign.from(row)
        #expect(campaign.serverRowId == 7)
        #expect(campaign.name == "Flash Sale")
        #expect(campaign.status == .active)
        #expect(campaign.type == .winback)
        #expect(campaign.channel == .email)
        #expect(campaign.sentCount == 100)
        #expect(campaign.repliedCount == 5)
        #expect(campaign.convertedCount == 3)
    }
}
