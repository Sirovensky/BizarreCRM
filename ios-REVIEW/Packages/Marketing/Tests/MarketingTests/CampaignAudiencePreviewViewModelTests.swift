import Testing
import Foundation
@testable import Marketing

@Suite("CampaignAudiencePreviewViewModel")
@MainActor
struct CampaignAudiencePreviewViewModelTests {

    @Test("initial state is empty")
    func initialState() {
        let mock = MockAPIClient()
        let vm = CampaignAudiencePreviewViewModel(api: mock, campaignId: 1)
        #expect(vm.preview == nil)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }

    @Test("load populates preview")
    func loadPopulatesPreview() async {
        let mock = MockAPIClient()
        let expected = CampaignAudiencePreview(
            campaignId: 1,
            totalRecipients: 88,
            preview: [
                PreviewRecipient(customerId: 10, firstName: "Alice", renderedBody: "Hi Alice!")
            ]
        )
        await mock.setAudiencePreviewResult(.success(expected))
        let vm = CampaignAudiencePreviewViewModel(api: mock, campaignId: 1)
        await vm.load()
        #expect(vm.preview?.totalRecipients == 88)
        #expect(vm.preview?.preview.count == 1)
        #expect(vm.preview?.preview[0].firstName == "Alice")
        #expect(vm.errorMessage == nil)
    }

    @Test("load sets errorMessage on failure")
    func loadError() async {
        let mock = MockAPIClient()
        await mock.setAudiencePreviewResult(.failure(URLError(.timedOut)))
        let vm = CampaignAudiencePreviewViewModel(api: mock, campaignId: 1)
        await vm.load()
        #expect(vm.errorMessage != nil)
        #expect(vm.preview == nil)
    }

    @Test("load calls audience preview endpoint once")
    func loadCallsEndpoint() async {
        let mock = MockAPIClient()
        let vm = CampaignAudiencePreviewViewModel(api: mock, campaignId: 5)
        await vm.load()
        let count = await mock.audiencePreviewCalled
        #expect(count == 1)
    }
}
