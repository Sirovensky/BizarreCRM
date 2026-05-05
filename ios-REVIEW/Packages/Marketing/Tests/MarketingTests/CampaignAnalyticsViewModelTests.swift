import Testing
import Foundation
@testable import Marketing

@Suite("CampaignAnalyticsViewModel")
@MainActor
struct CampaignAnalyticsViewModelTests {

    @Test("initial state is empty")
    func initialState() {
        let mock = MockAPIClient()
        let vm = CampaignAnalyticsViewModel(api: mock, campaignId: 1)
        #expect(vm.stats == nil)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.isRunning == false)
    }

    @Test("load populates stats")
    func loadPopulatesStats() async {
        let mock = MockAPIClient()
        let vm = CampaignAnalyticsViewModel(api: mock, campaignId: 1)
        await vm.load()
        #expect(vm.stats != nil)
        #expect(vm.errorMessage == nil)
        #expect(vm.stats?.counts.sent == 10)
        #expect(vm.stats?.counts.replied == 2)
    }

    @Test("load sets errorMessage on failure")
    func loadError() async {
        let mock = MockAPIClient()
        await mock.setCampaignStatsResult(.failure(URLError(.timedOut)))
        let vm = CampaignAnalyticsViewModel(api: mock, campaignId: 1)
        await vm.load()
        #expect(vm.errorMessage != nil)
        #expect(vm.stats == nil)
    }

    @Test("runNow populates runResult on success")
    func runNowSuccess() async {
        let mock = MockAPIClient()
        let vm = CampaignAnalyticsViewModel(api: mock, campaignId: 1)
        await vm.runNow()
        #expect(vm.runResult != nil)
        #expect(vm.runError == nil)
        #expect(vm.runResult?.sent == 5)
        #expect(vm.runResult?.attempted == 5)
        let count = await mock.runNowCalled
        #expect(count == 1)
    }

    @Test("runNow sets runError on failure")
    func runNowFailure() async {
        let mock = MockAPIClient()
        mock.campaignRunNowResult = .failure(URLError(.badServerResponse))
        let vm = CampaignAnalyticsViewModel(api: mock, campaignId: 1)
        await vm.runNow()
        #expect(vm.runError != nil)
        #expect(vm.runResult == nil)
    }

    @Test("runNow reloads stats after success")
    func runNowReloadsStats() async {
        let mock = MockAPIClient()
        let vm = CampaignAnalyticsViewModel(api: mock, campaignId: 1)
        await vm.runNow()
        // Stats should be loaded after run
        #expect(vm.stats != nil)
    }
}
