import Testing
import Foundation
@testable import Marketing

@Suite("CampaignCreateViewModel")
@MainActor
struct CampaignCreateViewModelTests {

    @Test("initial state is blank")
    func initialState() {
        let mock = MockAPIClient()
        let vm = CampaignCreateViewModel(api: mock)
        #expect(vm.name.isEmpty)
        #expect(vm.template.isEmpty)
        #expect(vm.recipientsEstimate == 0)
        #expect(vm.abEnabled == false)
        #expect(vm.isSaving == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.successCampaign == nil)
        if case .now = vm.schedule { } else {
            Issue.record("Expected .now as default schedule")
        }
    }

    @Test("canSubmit requires name + template, no approval needed")
    func canSubmitRules() {
        let mock = MockAPIClient()
        let vm = CampaignCreateViewModel(api: mock)
        vm.name = ""
        vm.template = "Hello"
        #expect(vm.canSubmit == false)

        vm.name = "Test"
        vm.template = ""
        #expect(vm.canSubmit == false)

        vm.name = "Test"
        vm.template = "Hello"
        #expect(vm.canSubmit == true)
    }

    @Test("canSubmit false when approval required")
    func canSubmitBlockedByApproval() {
        let mock = MockAPIClient()
        let vm = CampaignCreateViewModel(api: mock)
        vm.name = "Big blast"
        vm.template = "Hello"
        vm.selectSegment(id: "seg1", name: "All", count: 200)
        #expect(vm.requiresApproval == true)
        #expect(vm.canSubmit == false)
    }

    @Test("estimatedCostText matches calculator")
    func estimatedCostText() {
        let mock = MockAPIClient()
        let vm = CampaignCreateViewModel(api: mock)
        vm.selectSegment(id: "s1", name: "VIPs", count: 50)
        #expect(vm.estimatedCostText == EstimatedCostCalculator.formattedCost(recipients: 50))
    }

    @Test("insertDynamicVar appends to template")
    func insertDynamicVar() {
        let mock = MockAPIClient()
        let vm = CampaignCreateViewModel(api: mock)
        vm.template = "Hello "
        vm.insertDynamicVar("first_name")
        #expect(vm.template == "Hello {first_name}")
    }

    @Test("templateCharCount and segments correct")
    func charCount() {
        let mock = MockAPIClient()
        let vm = CampaignCreateViewModel(api: mock)
        vm.template = String(repeating: "A", count: 160)
        #expect(vm.templateCharCount == 160)
        #expect(vm.templateSegments == 1)
        vm.template = String(repeating: "A", count: 161)
        #expect(vm.templateSegments == 2)
    }

    @Test("save calls server create API and sets successCampaign on success")
    func saveSuccess() async {
        let mock = MockAPIClient()
        let vm = CampaignCreateViewModel(api: mock)
        vm.name = "Test Campaign"
        vm.template = "Hello {{first_name}}"
        await vm.save()
        #expect(vm.successCampaign != nil)
        #expect(vm.errorMessage == nil)
        let callCount = await mock.campaignServerCreateCalled
        #expect(callCount == 1)
    }

    @Test("save sets errorMessage on server create API failure")
    func saveFailure() async {
        let mock = MockAPIClient()
        mock.campaignServerCreateResult = .failure(URLError(.badServerResponse))
        let vm = CampaignCreateViewModel(api: mock)
        vm.name = "Test"
        vm.template = "Hello"
        await vm.save()
        #expect(vm.errorMessage != nil)
        #expect(vm.successCampaign == nil)
    }

    @Test("save rejects blank name")
    func saveRejectsBlankName() async {
        let mock = MockAPIClient()
        let vm = CampaignCreateViewModel(api: mock)
        vm.name = "   "
        vm.template = "Hello"
        await vm.save()
        #expect(vm.errorMessage != nil)
        let callCount = await mock.campaignServerCreateCalled
        #expect(callCount == 0)
    }

    @Test("selectSegment updates estimate and segment info")
    func selectSegment() {
        let mock = MockAPIClient()
        let vm = CampaignCreateViewModel(api: mock)
        vm.selectSegment(id: "seg42", name: "Premium", count: 88)
        #expect(vm.audienceSegmentId == "seg42")
        #expect(vm.audienceSegmentName == "Premium")
        #expect(vm.recipientsEstimate == 88)
    }

    @Test("schedule .scheduled stores date")
    func scheduleDate() {
        let mock = MockAPIClient()
        let vm = CampaignCreateViewModel(api: mock)
        let future = Date().addingTimeInterval(86400)
        vm.schedule = .scheduled(future)
        if case .scheduled(let d) = vm.schedule {
            #expect(d == future)
        } else {
            Issue.record("Expected .scheduled")
        }
    }

    @Test("channel defaults to .sms")
    func defaultChannel() {
        let vm = CampaignCreateViewModel(api: MockAPIClient())
        #expect(vm.channel == .sms)
    }

    @Test("needsSubject true for email and both channels")
    func needsSubjectFlag() {
        let vm = CampaignCreateViewModel(api: MockAPIClient())
        vm.channel = .sms
        #expect(vm.needsSubject == false)
        vm.channel = .email
        #expect(vm.needsSubject == true)
        vm.channel = .both
        #expect(vm.needsSubject == true)
    }

    @Test("selectSmsGroup populates audience as smsGroup")
    func selectSmsGroup() {
        let vm = CampaignCreateViewModel(api: MockAPIClient())
        vm.selectSmsGroup(id: 7, name: "Newsletter", count: 120)
        if case .smsGroup(let id, let name, let count) = vm.audience {
            #expect(id == 7)
            #expect(name == "Newsletter")
            #expect(count == 120)
        } else {
            Issue.record("Expected .smsGroup audience")
        }
        #expect(vm.recipientsEstimate == 120)
    }

    @Test("clearAudience resets to .all")
    func clearAudience() {
        let vm = CampaignCreateViewModel(api: MockAPIClient())
        vm.selectSegment(id: "s1", name: "VIPs", count: 50)
        vm.clearAudience()
        #expect(vm.audience == .all)
        #expect(vm.recipientsEstimate == 0)
    }

    @Test("campaignType defaults to .custom")
    func defaultType() {
        let vm = CampaignCreateViewModel(api: MockAPIClient())
        #expect(vm.campaignType == .custom)
    }

    @Test("insertDynamicVar uses double-brace syntax")
    func insertDynamicVarBraces() {
        let vm = CampaignCreateViewModel(api: MockAPIClient())
        vm.template = "Hello "
        vm.insertDynamicVar("first_name")
        #expect(vm.template == "Hello {{first_name}}")
    }
}
