import Foundation
import Core
import Networking

// MARK: - §5.7 Suggested tags based on behavior
// e.g. suggest `late-payer` after 3 overdue invoices

/// Pure service that computes tag suggestions for a customer based on their behavior patterns.
/// Works offline using cached customer data fields.
public struct CustomerSuggestedTagsService: Sendable {

    public init() {}

    /// Returns behavior-driven tag suggestions that are NOT already applied.
    ///
    /// Rules:
    /// - `late-payer`  : overdueInvoiceCount >= 3
    /// - `vip`         : ltvCents >= vipThreshold (default $500)
    /// - `at-risk`     : daysSinceLastVisit > 180
    /// - `returning`   : ticketCount >= 5
    /// - `new`         : ticketCount == 1
    /// - `frequent`    : ticketCount >= 10
    /// - `high-value`  : averageTicketCents >= 20000 ($200)
    public func suggestions(
        overdueInvoiceCount: Int = 0,
        ltvCents: Int = 0,
        daysSinceLastVisit: Int? = nil,
        ticketCount: Int = 0,
        averageTicketCents: Int = 0,
        existingTags: [String] = [],
        vipLTVThresholdCents: Int = 50_000
    ) -> [SuggestedTag] {
        let existing = Set(existingTags.map { $0.lowercased() })
        var result: [SuggestedTag] = []

        if overdueInvoiceCount >= 3, !existing.contains("late-payer") {
            result.append(SuggestedTag(
                tag: "late-payer",
                reason: "Has \(overdueInvoiceCount) overdue invoices"
            ))
        }

        if ltvCents >= vipLTVThresholdCents, !existing.contains("vip") {
            let formatted = "$\(ltvCents / 100)"
            result.append(SuggestedTag(
                tag: "vip",
                reason: "Lifetime value \(formatted)"
            ))
        }

        if let days = daysSinceLastVisit, days > 180, !existing.contains("at-risk") {
            result.append(SuggestedTag(
                tag: "at-risk",
                reason: "Last visit \(days) days ago"
            ))
        }

        if ticketCount >= 10, !existing.contains("frequent") {
            result.append(SuggestedTag(
                tag: "frequent",
                reason: "\(ticketCount) tickets total"
            ))
        } else if ticketCount >= 5, !existing.contains("returning") {
            result.append(SuggestedTag(
                tag: "returning",
                reason: "\(ticketCount) tickets total"
            ))
        } else if ticketCount == 1, !existing.contains("new") {
            result.append(SuggestedTag(
                tag: "new",
                reason: "First ticket on record"
            ))
        }

        if averageTicketCents >= 20_000, !existing.contains("high-value") {
            let formatted = "$\(averageTicketCents / 100)"
            result.append(SuggestedTag(
                tag: "high-value",
                reason: "Average ticket \(formatted)"
            ))
        }

        return result
    }
}

// MARK: - Model

public struct SuggestedTag: Sendable, Identifiable, Equatable {
    public var id: String { tag }
    /// The tag string to apply (lowercase).
    public let tag: String
    /// Human-readable explanation for the suggestion.
    public let reason: String

    public init(tag: String, reason: String) {
        self.tag = tag
        self.reason = reason
    }
}
