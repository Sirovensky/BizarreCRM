import Foundation

/// Pre-baked segment rulesets for common audience patterns.
public enum SegmentPresets {
    public struct Preset: Sendable {
        public let name: String
        public let rule: SegmentRuleGroup
    }

    /// §37 — Full preset library including birthday-month, LTV-tier, and service-history presets.
    public static let all: [Preset] = [vips, dormant, new, highLTV, `repeat`, atRisk,
                                       birthdayThisMonth, platinumTier, phoneRepairHistory]

    public static let vips = Preset(
        name: "VIPs",
        rule: SegmentRuleGroup(op: "AND", rules: [
            .leaf(field: "lifetime_spend", op: ">", value: "500"),
            .leaf(field: "ticket_count", op: ">", value: "3")
        ])
    )

    public static let dormant = Preset(
        name: "Dormant",
        rule: SegmentRuleGroup(op: "AND", rules: [
            .leaf(field: "last_visit_days_ago", op: ">", value: "90")
        ])
    )

    public static let new = Preset(
        name: "New",
        rule: SegmentRuleGroup(op: "AND", rules: [
            .leaf(field: "ticket_count", op: "=", value: "1"),
            .leaf(field: "last_visit_days_ago", op: "<", value: "30")
        ])
    )

    public static let highLTV = Preset(
        name: "High-LTV",
        rule: SegmentRuleGroup(op: "AND", rules: [
            .leaf(field: "lifetime_spend", op: ">", value: "1000")
        ])
    )

    public static let `repeat` = Preset(
        name: "Repeat",
        rule: SegmentRuleGroup(op: "AND", rules: [
            .leaf(field: "ticket_count", op: ">", value: "1")
        ])
    )

    public static let atRisk = Preset(
        name: "At-risk",
        rule: SegmentRuleGroup(op: "AND", rules: [
            .leaf(field: "last_visit_days_ago", op: ">", value: "60"),
            .leaf(field: "ticket_count", op: ">", value: "2")
        ])
    )

    // MARK: - §37 New audience builder presets

    /// Customers whose birthday falls in the current calendar month.
    public static let birthdayThisMonth = Preset(
        name: "Birthday this month",
        rule: SegmentRuleGroup(op: "AND", rules: [
            .leaf(field: "birthday_month", op: "=", value: "\(Calendar.current.component(.month, from: Date()))")
        ])
    )

    /// Customers in the Platinum LTV tier (highest value).
    public static let platinumTier = Preset(
        name: "Platinum tier",
        rule: SegmentRuleGroup(op: "AND", rules: [
            .leaf(field: "ltv_tier", op: "=", value: "platinum")
        ])
    )

    /// Customers who have had at least one phone repair in service history.
    public static let phoneRepairHistory = Preset(
        name: "Phone repair customers",
        rule: SegmentRuleGroup(op: "AND", rules: [
            .leaf(field: "service_type", op: "contains", value: "phone")
        ])
    )
}
