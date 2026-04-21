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
    public var audienceSegmentId: String? = nil
    public var audienceSegmentName: String? = nil
    public var template: String = ""
    public var schedule: ScheduleChoice = .now
    public var abEnabled: Bool = false
    public var variantB: String = ""
    public var recipientsEstimate: Int = 0

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

    /// SMS char count (160-char boundary awareness).
    public var templateCharCount: Int { template.count }

    public var templateSegments: Int {
        guard template.count > 0 else { return 0 }
        return max(1, Int(ceil(Double(template.count) / 160.0)))
    }

    // MARK: Actions

    public func selectSegment(id: String, name: String, count: Int) {
        audienceSegmentId = id
        audienceSegmentName = name
        recipientsEstimate = count
    }

    public func insertDynamicVar(_ variable: String) {
        template += "{\(variable)}"
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
            let scheduledAt: Date?
            if case .scheduled(let date) = schedule { scheduledAt = date } else { scheduledAt = nil }

            let req = CreateCampaignRequest(
                name: trimmedName,
                audienceSegmentId: audienceSegmentId,
                template: trimmedTemplate,
                scheduledAt: scheduledAt,
                variantB: abEnabled ? variantB.trimmingCharacters(in: .whitespaces) : nil
            )
            let campaign = try await api.createCampaign(req)
            successCampaign = campaign
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
