import Testing
import Foundation
@testable import Marketing
import Networking

// MARK: - CampaignContextMenuViewModelTests

@Suite("CampaignContextMenuViewModel")
@MainActor
struct CampaignContextMenuViewModelTests {

    // MARK: - sendNow

    @Test("sendNow success clears error")
    func sendNowSuccess() async {
        let mock = MockAPIClient()
        let vm = CampaignContextMenuViewModel(api: mock)
        let campaign = makeTestCampaign(serverRowId: 1)

        await vm.sendNow(campaign: campaign)

        #expect(vm.errorMessage == nil)
        #expect(vm.isBusy == false)
    }

    @Test("sendNow calls run-now endpoint")
    func sendNowCallsEndpoint() async {
        let mock = MockAPIClient()
        let vm = CampaignContextMenuViewModel(api: mock)
        let campaign = makeTestCampaign(serverRowId: 42)

        await vm.sendNow(campaign: campaign)

        let called = await mock.runNowCalled
        #expect(called == 1)
    }

    @Test("sendNow failure sets error message")
    func sendNowFailure() async {
        let mock = MockAPIClient()
        mock.campaignRunNowResult = .failure(URLError(.badServerResponse))
        let vm = CampaignContextMenuViewModel(api: mock)
        let campaign = makeTestCampaign(serverRowId: 1)

        await vm.sendNow(campaign: campaign)

        #expect(vm.errorMessage != nil)
        #expect(vm.isBusy == false)
    }

    @Test("sendNow without server row ID sets error, skips endpoint")
    func sendNowNoRowId() async {
        let mock = MockAPIClient()
        let vm = CampaignContextMenuViewModel(api: mock)
        let campaign = makeTestCampaign(serverRowId: nil)

        await vm.sendNow(campaign: campaign)

        #expect(vm.errorMessage != nil)
        let called = await mock.runNowCalled
        #expect(called == 0)
    }

    @Test("sendNow isBusy is false after completion")
    func sendNowIsBusyReset() async {
        let mock = MockAPIClient()
        let vm = CampaignContextMenuViewModel(api: mock)
        let campaign = makeTestCampaign(serverRowId: 1)

        #expect(vm.isBusy == false)
        await vm.sendNow(campaign: campaign)
        #expect(vm.isBusy == false)
    }

    // MARK: - archive

    @Test("archive success clears error")
    func archiveSuccess() async {
        let mock = MockAPIClient()
        let vm = CampaignContextMenuViewModel(api: mock)
        let campaign = makeTestCampaign(serverRowId: 10)

        await vm.archive(campaign: campaign)

        #expect(vm.errorMessage == nil)
        #expect(vm.isBusy == false)
    }

    @Test("archive calls patch endpoint")
    func archiveCallsPatch() async {
        let mock = MockAPIClient()
        let vm = CampaignContextMenuViewModel(api: mock)
        let campaign = makeTestCampaign(serverRowId: 10)

        await vm.archive(campaign: campaign)

        let called = await mock.campaignServerPatchCalled
        #expect(called == 1)
    }

    @Test("archive failure sets error message")
    func archiveFailure() async {
        let mock = MockAPIClient()
        mock.campaignServerPatchResult = .failure(URLError(.networkConnectionLost))
        let vm = CampaignContextMenuViewModel(api: mock)
        let campaign = makeTestCampaign(serverRowId: 10)

        await vm.archive(campaign: campaign)

        #expect(vm.errorMessage != nil)
    }

    @Test("archive without server row ID sets error, skips endpoint")
    func archiveNoRowId() async {
        let mock = MockAPIClient()
        let vm = CampaignContextMenuViewModel(api: mock)
        let campaign = makeTestCampaign(serverRowId: nil)

        await vm.archive(campaign: campaign)

        #expect(vm.errorMessage != nil)
        let called = await mock.campaignServerPatchCalled
        #expect(called == 0)
    }

    // MARK: - duplicate

    @Test("duplicate success sets duplicatedCampaign")
    func duplicateSuccess() async {
        let mock = MockAPIClient()
        mock.campaignServerCreateResult = .success(makeCampaignServerRow(id: 99, name: "Copy of Summer Promo"))
        let vm = CampaignContextMenuViewModel(api: mock)
        let campaign = makeTestCampaign(serverRowId: 5, name: "Summer Promo")

        await vm.duplicate(campaign: campaign)

        #expect(vm.duplicatedCampaign != nil)
        #expect(vm.duplicatedCampaign?.id == 99)
        #expect(vm.errorMessage == nil)
        #expect(vm.isBusy == false)
    }

    @Test("duplicate calls create endpoint")
    func duplicateCallsCreate() async {
        let mock = MockAPIClient()
        mock.campaignServerCreateResult = .success(makeCampaignServerRow(id: 100))
        let vm = CampaignContextMenuViewModel(api: mock)
        let campaign = makeTestCampaign(serverRowId: 5, name: "Flash Sale")

        await vm.duplicate(campaign: campaign)

        let called = await mock.campaignServerCreateCalled
        #expect(called == 1)
    }

    @Test("duplicate failure sets error message")
    func duplicateFailure() async {
        let mock = MockAPIClient()
        mock.campaignServerCreateResult = .failure(URLError(.badServerResponse))
        let vm = CampaignContextMenuViewModel(api: mock)
        let campaign = makeTestCampaign(serverRowId: 5)

        await vm.duplicate(campaign: campaign)

        #expect(vm.errorMessage != nil)
        #expect(vm.duplicatedCampaign == nil)
    }

    @Test("duplicate name has 'Copy of' prefix")
    func duplicateNamePrefix() async {
        let mock = MockAPIClient()
        mock.campaignServerCreateResult = .success(makeCampaignServerRow(id: 200, name: "Copy of Win-back Q3"))
        let vm = CampaignContextMenuViewModel(api: mock)
        let campaign = makeTestCampaign(serverRowId: 7, name: "Win-back Q3")

        await vm.duplicate(campaign: campaign)

        #expect(vm.duplicatedCampaign?.name == "Copy of Win-back Q3")
    }

    @Test("duplicate isBusy is false after failure")
    func duplicateIsBusyReset() async {
        let mock = MockAPIClient()
        mock.campaignServerCreateResult = .failure(URLError(.timedOut))
        let vm = CampaignContextMenuViewModel(api: mock)
        let campaign = makeTestCampaign(serverRowId: 1)

        await vm.duplicate(campaign: campaign)

        #expect(vm.isBusy == false)
    }

    // MARK: - CampaignContextMenuActions wiring

    @Test("onEdit callback fires with campaign")
    func onEditFires() {
        var received: Campaign?
        let c = makeTestCampaign(serverRowId: 1, name: "Edit me")
        let actions = CampaignContextMenuActions(
            onEdit:      { received = $0 },
            onSendNow:   { _ in },
            onPreview:   { _ in },
            onDuplicate: { _ in },
            onArchive:   { _ in }
        )
        actions.onEdit(c)
        #expect(received?.name == "Edit me")
    }

    @Test("onPreview callback fires with campaign")
    func onPreviewFires() {
        var received: Campaign?
        let c = makeTestCampaign(serverRowId: 2, name: "Preview me")
        let actions = CampaignContextMenuActions(
            onEdit:      { _ in },
            onSendNow:   { _ in },
            onPreview:   { received = $0 },
            onDuplicate: { _ in },
            onArchive:   { _ in }
        )
        actions.onPreview(c)
        #expect(received?.name == "Preview me")
    }
}

// MARK: - Helpers

private func makeTestCampaign(
    serverRowId: Int?,
    name: String = "Test Campaign",
    status: CampaignStatus = .active
) -> Campaign {
    Campaign(
        id: serverRowId.map { String($0) } ?? UUID().uuidString,
        name: name,
        status: status,
        template: "Hello {{name}}",
        createdAt: Date(),
        serverRowId: serverRowId
    )
}
