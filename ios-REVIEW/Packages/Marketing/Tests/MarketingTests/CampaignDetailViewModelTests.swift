import Testing
import Foundation
@testable import Marketing

@Suite("CampaignDetailViewModel")
@MainActor
struct CampaignDetailViewModelTests {

    // MARK: - Initial state

    @Test("initial state has no campaign and no error")
    func initialState() {
        let mock = MockAPIClient()
        let vm = CampaignDetailViewModel(api: mock, campaignId: "1")
        #expect(vm.campaign == nil)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.isSending == false)
        #expect(vm.sendError == nil)
    }

    @Test("campaignId stored correctly")
    func campaignIdStored() {
        let mock = MockAPIClient()
        let vm = CampaignDetailViewModel(api: mock, campaignId: "42")
        #expect(vm.campaignId == "42")
    }

    // MARK: - Load (numeric id → server row path)

    @Test("load with numeric id populates campaign from server row")
    func loadNumericId() async {
        let mock = MockAPIClient()
        let row = makeCampaignServerRow(id: 7, name: "Flash Sale", status: "active")
        mock.campaignServerGetResult = .success(row)
        let vm = CampaignDetailViewModel(api: mock, campaignId: "7")
        await vm.load()
        #expect(vm.campaign != nil)
        #expect(vm.campaign?.name == "Flash Sale")
        #expect(vm.campaign?.status == .active)
        #expect(vm.campaign?.serverRowId == 7)
        #expect(vm.errorMessage == nil)
    }

    @Test("load with numeric id maps type and channel correctly")
    func loadMapsTypeAndChannel() async {
        let mock = MockAPIClient()
        let row = makeCampaignServerRow(id: 3, type: "birthday", channel: "email")
        mock.campaignServerGetResult = .success(row)
        let vm = CampaignDetailViewModel(api: mock, campaignId: "3")
        await vm.load()
        #expect(vm.campaign?.type == .birthday)
        #expect(vm.campaign?.channel == .email)
    }

    @Test("load with numeric id sets errorMessage on failure")
    func loadNumericIdError() async {
        let mock = MockAPIClient()
        mock.campaignServerGetResult = .failure(URLError(.timedOut))
        let vm = CampaignDetailViewModel(api: mock, campaignId: "5")
        await vm.load()
        #expect(vm.campaign == nil)
        #expect(vm.errorMessage != nil)
    }

    @Test("isLoading is false after load completes (success)")
    func isLoadingFalseAfterSuccess() async {
        let mock = MockAPIClient()
        let vm = CampaignDetailViewModel(api: mock, campaignId: "1")
        await vm.load()
        #expect(vm.isLoading == false)
    }

    @Test("isLoading is false after load completes (failure)")
    func isLoadingFalseAfterFailure() async {
        let mock = MockAPIClient()
        mock.campaignServerGetResult = .failure(URLError(.badServerResponse))
        let vm = CampaignDetailViewModel(api: mock, campaignId: "1")
        await vm.load()
        #expect(vm.isLoading == false)
    }

    // MARK: - Load (non-numeric id → legacy path)

    @Test("load with non-numeric id uses legacy getCampaign path")
    func loadNonNumericId() async {
        let mock = MockAPIClient()
        let legacyCampaign = Campaign(
            id: "legacy-1",
            name: "Legacy Campaign",
            status: .draft,
            template: "Hello",
            createdAt: Date()
        )
        mock.campaignGetResult = .success(legacyCampaign)
        let vm = CampaignDetailViewModel(api: mock, campaignId: "legacy-1")
        await vm.load()
        #expect(vm.campaign?.id == "legacy-1")
        #expect(vm.campaign?.name == "Legacy Campaign")
    }

    @Test("load with non-numeric id sets errorMessage on failure")
    func loadNonNumericIdError() async {
        let mock = MockAPIClient()
        mock.campaignGetResult = .failure(URLError(.notConnectedToInternet))
        let vm = CampaignDetailViewModel(api: mock, campaignId: "not-a-number")
        await vm.load()
        #expect(vm.campaign == nil)
        #expect(vm.errorMessage != nil)
    }

    // MARK: - Send

    @Test("send updates campaign to sending status")
    func sendUpdatesStatus() async {
        let mock = MockAPIClient()
        let row = makeCampaignServerRow(id: 1, status: "draft")
        mock.campaignServerGetResult = .success(row)
        let sendingCampaign = Campaign(
            id: "1", name: "Test",
            status: .sending, template: "Hello",
            createdAt: Date()
        )
        mock.campaignSendResult = .success(sendingCampaign)
        let vm = CampaignDetailViewModel(api: mock, campaignId: "1")
        await vm.load()
        await vm.send()
        #expect(vm.campaign?.status == .sending)
        #expect(vm.sendError == nil)
        let count = await mock.sendCampaignCalled
        #expect(count == 1)
    }

    @Test("send sets sendError on failure")
    func sendFailure() async {
        let mock = MockAPIClient()
        mock.campaignSendResult = .failure(URLError(.badServerResponse))
        let vm = CampaignDetailViewModel(api: mock, campaignId: "1")
        await vm.send()
        #expect(vm.sendError != nil)
    }

    @Test("isSending is false after send completes")
    func isSendingFalseAfterCompletion() async {
        let mock = MockAPIClient()
        let vm = CampaignDetailViewModel(api: mock, campaignId: "1")
        await vm.send()
        #expect(vm.isSending == false)
    }

    @Test("isSending is false after send failure")
    func isSendingFalseAfterFailure() async {
        let mock = MockAPIClient()
        mock.campaignSendResult = .failure(URLError(.timedOut))
        let vm = CampaignDetailViewModel(api: mock, campaignId: "1")
        await vm.send()
        #expect(vm.isSending == false)
    }

    // MARK: - Load clears previous errors

    @Test("successive loads clear previous errorMessage on success")
    func reloadClearsPreviousError() async {
        let mock = MockAPIClient()
        mock.campaignServerGetResult = .failure(URLError(.timedOut))
        let vm = CampaignDetailViewModel(api: mock, campaignId: "1")
        await vm.load()
        #expect(vm.errorMessage != nil)

        let row = makeCampaignServerRow(id: 1, status: "active")
        mock.campaignServerGetResult = .success(row)
        await vm.load()
        #expect(vm.errorMessage == nil)
        #expect(vm.campaign != nil)
    }
}
