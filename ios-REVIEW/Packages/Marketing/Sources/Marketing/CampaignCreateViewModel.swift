import Foundation
import Observation
import Core
import Networking

public enum ScheduleChoice: Equatable, Sendable {
    case now
    case scheduled(Date)
}

@MainActor
@Observable
public final class CampaignCreateViewModel {
    public var name: String = ""
    public var campaignType: CampaignType = .custom
    public var channel: CampaignChannel = .sms
    public var audience: AudienceSelection = .all
    public var template: String = ""
    public var templateSubject: String = ""  // email subject
    public var schedule: ScheduleChoice = .now
    public var abEnabled: Bool = false
    public var variantB: String = ""

    // §37 Extended scheduler
    public var scheduleKind: CampaignScheduleKind = .sendNow
    public var scheduledSendAt: Date = Date().addingTimeInterval(3600)
    public var recurrenceConfig: CampaignRecurrenceConfig = CampaignRecurrenceConfig()
    public var triggerConfig: CampaignTriggerConfig = CampaignTriggerConfig()

    // §37 Compliance
    public var compliance: CampaignComplianceConfig = CampaignComplianceConfig()

    // Legacy compat accessors
    public var audienceSegmentId: String? { audience.segmentIdString }
    public var audienceSegmentName: String? {
        if case .all = audience { return nil }
        return audience.displayName
    }
    public var recipientsEstimate: Int { audience.recipientCount }

    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    public private(set) var successCampaign: Campaign?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: Derived

    public var estimatedCostText: String {
        EstimatedCostCalculator.formattedCost(recipients: recipientsEstimate)
    }

    public var requiresApproval: Bool {
        EstimatedCostCalculator.requiresApproval(recipients: recipientsEstimate)
    }

    public var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !template.trimmingCharacters(in: .whitespaces).isEmpty &&
        !requiresApproval
    }

    public var needsSubject: Bool { channel == .email || channel == .both }

    /// SMS char count (160-char boundary awareness).
    public var templateCharCount: Int { template.count }

    public var templateSegments: Int {
        guard template.count > 0 else { return 0 }
        return max(1, Int(ceil(Double(template.count) / 160.0)))
    }

    // MARK: Actions

    /// Legacy compatibility — select a CRM segment as audience.
    public func selectSegment(id: String, name: String, count: Int) {
        audience = .segment(id: id, name: name, count: count)
    }

    /// Select an SMS group as audience.
    public func selectSmsGroup(id: Int, name: String, count: Int) {
        audience = .smsGroup(id: id, name: name, count: count)
    }

    public func clearAudience() {
        audience = .all
    }

    public func insertDynamicVar(_ variable: String) {
        template += "{{\(variable)}}"
    }

    public func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedTemplate = template.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedTemplate.isEmpty else {
            errorMessage = "Name and message are required."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            // Use the real server endpoint if we have a numeric segment id
            let segmentIntId: Int? = audience.segmentIdString.flatMap { Int($0) }
                ?? audience.smsGroupId  // treat smsGroup as segment_id on server

            let req = CreateCampaignServerRequest(
                name: trimmedName,
                type: campaignType.rawValue,
                channel: channel.rawValue,
                templateBody: trimmedTemplate,
                templateSubject: needsSubject ? templateSubject.trimmingCharacters(in: .whitespaces) : nil,
                segmentId: segmentIntId
            )
            let row = try await api.createCampaignServer(req)
            successCampaign = Campaign.from(row)
        } catch {
            AppLog.ui.error("Campaign create failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func requestApprovalSend(campaignId: String, pin: String) async -> Bool {
        do {
            try await api.approveSendCampaign(id: campaignId, managerPin: pin)
            return true
        } catch {
            errorMessage = "Approval failed: \(error.localizedDescription)"
            return false
        }
    }
}
