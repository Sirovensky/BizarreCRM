import Testing
import Foundation
@testable import Marketing
import Networking

// MARK: - CampaignAnalyticsInspectorTests
//
// Tests exercise the CampaignAnalyticsViewModel which powers CampaignAnalyticsInspector.
// Covers initial state, load/error paths, runNow send stats, and stats display values.

@Suite("CampaignAnalyticsInspector — ViewModel")
@MainActor
struct CampaignAnalyticsInspectorTests {

    // MARK: - Initial state

    @Test("initial state is empty")
    func initialState() {
        let vm = CampaignAnalyticsViewModel(api: MockAPIClient(), campaignId: 7)
        #expect(vm.isLoading == false)
        #expect(vm.stats == nil)
        #expect(vm.errorMessage == nil)
        #expect(vm.isRunning == false)
        #expect(vm.runResult == nil)
    }

    @Test("campaignId is stored on init")
    func campaignIdStored() {
        let vm = CampaignAnalyticsViewModel(api: MockAPIClient(), campaignId: 7)
        #expect(vm.campaignId == 7)
    }

    // MARK: - load()

    @Test("load success populates stats")
    func loadPopulatesStats() async {
        let mock = MockAPIClient()
        await mock.setCampaignStatsResult(.success(makeInspectorStats(id: 7, sentCount: 100, delivered: 95, failed: 5)))
        let vm = CampaignAnalyticsViewModel(api: mock, campaignId: 7)

        await vm.load()

        #expect(vm.stats != nil)
        #expect(vm.errorMessage == nil)
        #expect(vm.isLoading == false)
    }

    @Test("load success stores correct sentCount")
    func loadSentCount() async {
        let mock = MockAPIClient()
        await mock.setCampaignStatsResult(.success(makeInspectorStats(id: 7, sentCount: 42, delivered: 40, failed: 2)))
        let vm = CampaignAnalyticsViewModel(api: mock, campaignId: 7)

        await vm.load()

        #expect(vm.stats?.campaign.sentCount == 42)
    }

    @Test("load failure sets errorMessage")
    func loadFailure() async {
        let mock = MockAPIClient()
        await mock.setCampaignStatsResult(.failure(URLError(.notConnectedToInternet)))
        let vm = CampaignAnalyticsViewModel(api: mock, campaignId: 7)

        await vm.load()

        #expect(vm.stats == nil)
        #expect(vm.errorMessage != nil)
    }

    @Test("load clears error on successful retry")
    func loadClearsError() async {
        let mock = MockAPIClient()
        await mock.setCampaignStatsResult(.failure(URLError(.badServerResponse)))
        let vm = CampaignAnalyticsViewModel(api: mock, campaignId: 7)
        await vm.load()
        #expect(vm.errorMessage != nil)

        await mock.setCampaignStatsResult(.success(makeInspectorStats(id: 7)))
        await vm.load()

        #expect(vm.errorMessage == nil)
        #expect(vm.stats != nil)
    }

    @Test("load isLoading is false after completion")
    func loadIsLoadingReset() async {
        let mock = MockAPIClient()
        let vm = CampaignAnalyticsViewModel(api: mock, campaignId: 7)

        await vm.load()

        #expect(vm.isLoading == false)
    }

    // MARK: - runNow()

    @Test("runNow success sets runResult")
    func runNowSuccess() async {
        let mock = MockAPIClient()
        mock.campaignRunNowResult = .success(
            CampaignRunNowResult(attempted: 10, sent: 9, failed: 1, skipped: 0)
        )
        await mock.setCampaignStatsResult(.success(makeInspectorStats(id: 7)))
        let vm = CampaignAnalyticsViewModel(api: mock, campaignId: 7)

        await vm.runNow()

        #expect(vm.runResult != nil)
        #expect(vm.runResult?.attempted == 10)
        #expect(vm.runResult?.sent == 9)
        #expect(vm.runResult?.failed == 1)
        #expect(vm.runError == nil)
        #expect(vm.isRunning == false)
    }

    @Test("runNow failure sets runError")
    func runNowFailure() async {
        let mock = MockAPIClient()
        mock.campaignRunNowResult = .failure(URLError(.timedOut))
        let vm = CampaignAnalyticsViewModel(api: mock, campaignId: 7)

        await vm.runNow()

        #expect(vm.runError != nil)
        #expect(vm.runResult == nil)
        #expect(vm.isRunning == false)
    }

    @Test("runNow calls run-now endpoint once")
    func runNowCallsEndpoint() async {
        let mock = MockAPIClient()
        mock.campaignRunNowResult = .success(
            CampaignRunNowResult(attempted: 0, sent: 0, failed: 0, skipped: 0)
        )
        await mock.setCampaignStatsResult(.success(makeInspectorStats(id: 7)))
        let vm = CampaignAnalyticsViewModel(api: mock, campaignId: 7)

        await vm.runNow()

        let called = await mock.runNowCalled
        #expect(called == 1)
    }

    @Test("runNow reloads stats after success")
    func runNowReloadsStats() async {
        let mock = MockAPIClient()
        mock.campaignRunNowResult = .success(
            CampaignRunNowResult(attempted: 5, sent: 5, failed: 0, skipped: 0)
        )
        await mock.setCampaignStatsResult(.success(makeInspectorStats(id: 7, sentCount: 5, delivered: 5, failed: 0)))
        let vm = CampaignAnalyticsViewModel(api: mock, campaignId: 7)

        await vm.runNow()

        #expect(vm.stats?.campaign.sentCount == 5)
    }

    @Test("runNow isRunning is false after completion")
    func runNowIsRunningReset() async {
        let mock = MockAPIClient()
        await mock.setCampaignStatsResult(.success(makeInspectorStats(id: 7)))
        let vm = CampaignAnalyticsViewModel(api: mock, campaignId: 7)

        await vm.runNow()

        #expect(vm.isRunning == false)
    }

    // MARK: - Stats display values

    @Test("delivered count comes from counts.sent")
    func deliveredFromCounts() async {
        let mock = MockAPIClient()
        await mock.setCampaignStatsResult(.success(makeInspectorStats(id: 7, sentCount: 100, delivered: 88, failed: 12)))
        let vm = CampaignAnalyticsViewModel(api: mock, campaignId: 7)

        await vm.load()

        #expect(vm.stats?.counts.sent == 88)
        #expect(vm.stats?.counts.failed == 12)
    }

    @Test("replied count comes from campaign row")
    func repliedFromCampaignRow() async {
        let mock = MockAPIClient()
        let stats = CampaignStats(
            campaign: makeCampaignServerRow(id: 7, repliedCount: 15),
            counts: CampaignStatCounts(sent: 50, failed: 0, replied: 15, converted: 0)
        )
        await mock.setCampaignStatsResult(.success(stats))
        let vm = CampaignAnalyticsViewModel(api: mock, campaignId: 7)

        await vm.load()

        #expect(vm.stats?.campaign.repliedCount == 15)
    }

    @Test("converted count comes from campaign row")
    func convertedFromCampaignRow() async {
        let mock = MockAPIClient()
        let stats = CampaignStats(
            campaign: makeCampaignServerRow(id: 7, convertedCount: 7),
            counts: CampaignStatCounts(sent: 30, failed: 0, replied: 5, converted: 7)
        )
        await mock.setCampaignStatsResult(.success(stats))
        let vm = CampaignAnalyticsViewModel(api: mock, campaignId: 7)

        await vm.load()

        #expect(vm.stats?.campaign.convertedCount == 7)
    }
}

// MARK: - Helpers

private func makeInspectorStats(
    id: Int = 1,
    sentCount: Int = 0,
    delivered: Int = 0,
    failed: Int = 0,
    replied: Int = 0,
    converted: Int = 0
) -> CampaignStats {
    CampaignStats(
        campaign: makeCampaignServerRow(
            id: id,
            sentCount: sentCount,
            repliedCount: replied,
            convertedCount: converted
        ),
        counts: CampaignStatCounts(sent: delivered, failed: failed, replied: replied, converted: converted)
    )
}
