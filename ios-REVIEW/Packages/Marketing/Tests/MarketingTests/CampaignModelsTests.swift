import Testing
import Foundation
@testable import Marketing

@Suite("Campaign models")
struct CampaignModelsTests {

    // MARK: - AudienceSelection

    @Test("segment selection exposes correct properties")
    func audienceSegment() {
        let sel = AudienceSelection.segment(id: "seg1", name: "VIPs", count: 250)
        #expect(sel.displayName == "VIPs")
        #expect(sel.recipientCount == 250)
        #expect(sel.segmentIdString == "seg1")
        #expect(sel.smsGroupId == nil)
    }

    @Test("smsGroup selection exposes correct properties")
    func audienceSmsGroup() {
        let sel = AudienceSelection.smsGroup(id: 42, name: "Newsletter", count: 88)
        #expect(sel.displayName == "Newsletter")
        #expect(sel.recipientCount == 88)
        #expect(sel.smsGroupId == 42)
        #expect(sel.segmentIdString == nil)
    }

    @Test("all audience has zero recipients")
    func audienceAll() {
        let sel = AudienceSelection.all
        #expect(sel.displayName == "All contacts")
        #expect(sel.recipientCount == 0)
        #expect(sel.segmentIdString == nil)
        #expect(sel.smsGroupId == nil)
    }

    // MARK: - CampaignType

    @Test("CampaignType rawValues match server constants")
    func campaignTypeRawValues() {
        #expect(CampaignType.birthday.rawValue == "birthday")
        #expect(CampaignType.winback.rawValue == "winback")
        #expect(CampaignType.reviewRequest.rawValue == "review_request")
        #expect(CampaignType.churnWarning.rawValue == "churn_warning")
        #expect(CampaignType.custom.rawValue == "custom")
    }

    @Test("CampaignType unknown status falls back to .custom")
    func campaignTypeUnknownFallback() {
        let parsed = CampaignType(rawValue: "totally_unknown") ?? .custom
        #expect(parsed == .custom)
    }

    // MARK: - CampaignChannel

    @Test("CampaignChannel rawValues match server constants")
    func campaignChannelRawValues() {
        #expect(CampaignChannel.sms.rawValue == "sms")
        #expect(CampaignChannel.email.rawValue == "email")
        #expect(CampaignChannel.both.rawValue == "both")
    }

    // MARK: - CampaignStatus filter categories

    @Test("active cases include active and sending")
    func activeCases() {
        #expect(CampaignStatus.activeCases.contains(.active))
        #expect(CampaignStatus.activeCases.contains(.sending))
        #expect(!CampaignStatus.activeCases.contains(.draft))
    }

    @Test("past cases include archived and sent")
    func pastCases() {
        #expect(CampaignStatus.pastCases.contains(.archived))
        #expect(CampaignStatus.pastCases.contains(.sent))
        #expect(!CampaignStatus.pastCases.contains(.active))
    }

    // MARK: - Campaign.from

    @Test("Campaign.from maps all fields correctly")
    func campaignFromMapsFields() {
        let row = makeCampaignServerRow(
            id: 99, name: "Test Campaign",
            status: "active", type: "birthday", channel: "both",
            sentCount: 50, repliedCount: 3, convertedCount: 1
        )
        let c = Campaign.from(row)
        #expect(c.id == "99")
        #expect(c.name == "Test Campaign")
        #expect(c.status == .active)
        #expect(c.type == .birthday)
        #expect(c.channel == .both)
        #expect(c.sentCount == 50)
        #expect(c.repliedCount == 3)
        #expect(c.convertedCount == 1)
        #expect(c.serverRowId == 99)
    }

    @Test("Campaign.from unknown status maps to draft")
    func campaignFromUnknownStatus() {
        let row = makeCampaignServerRow(status: "unknown_value")
        let c = Campaign.from(row)
        #expect(c.status == .draft)
    }
}
