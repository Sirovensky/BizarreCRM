import Foundation

// MARK: - ChurnCampaignSpec

/// A pre-filled campaign spec generated from the churn cohort.
/// Passed to the Marketing module (§37) to create a targeted campaign.
public struct ChurnCampaignSpec: Sendable, Equatable {
    public let name: String
    /// Audience rule: customers matching this risk level or higher.
    public let riskLevel: ChurnRiskLevel
    /// Customer IDs to pre-populate the segment.
    public let customerIds: [Int64]
    /// Suggested message body.
    public let suggestedMessage: String

    public init(
        name: String,
        riskLevel: ChurnRiskLevel,
        customerIds: [Int64],
        suggestedMessage: String
    ) {
        self.name             = name
        self.riskLevel        = riskLevel
        self.customerIds      = customerIds
        self.suggestedMessage = suggestedMessage
    }
}

// MARK: - ChurnTargetCampaignBuilder

/// §44.3 — Pure helper that produces a `ChurnCampaignSpec` from a cohort.
///
/// The caller passes the spec to the Marketing module's campaign creation flow.
public enum ChurnTargetCampaignBuilder {

    /// Generates a ready-to-use campaign spec from a churn cohort.
    ///
    /// - Parameters:
    ///   - cohort: The cohort from `GET /customers/churn-cohort`.
    ///   - riskLevel: The minimum risk level used for cohort filtering.
    /// - Returns: A new `ChurnCampaignSpec`. Never mutates its inputs.
    public static func build(
        from cohort: ChurnCohortDTO,
        riskLevel: ChurnRiskLevel
    ) -> ChurnCampaignSpec {
        let ids = cohort.customers.map(\.customerId)
        let name = "Win-back: \(riskLevel.label) (\(ids.count) customers)"
        let message = defaultMessage(for: riskLevel, count: ids.count)
        return ChurnCampaignSpec(
            name:             name,
            riskLevel:        riskLevel,
            customerIds:      ids,
            suggestedMessage: message
        )
    }

    // MARK: Private

    private static func defaultMessage(for riskLevel: ChurnRiskLevel, count: Int) -> String {
        switch riskLevel {
        case .critical:
            return "We miss you! As one of our valued customers, we\u{2019}d love to see you back. " +
                   "Here\u{2019}s an exclusive offer — reply for details."
        case .high:
            return "Hi! It\u{2019}s been a while. We\u{2019}re offering a special discount for your next visit. " +
                   "Come see us soon!"
        case .medium:
            return "Hi! We noticed you haven\u{2019}t visited recently. " +
                   "We have new services and deals we\u{2019}d love to share with you."
        case .low:
            return "Thanks for being a loyal customer! Here\u{2019}s a reminder we\u{2019}re here whenever you need us."
        }
    }
}
