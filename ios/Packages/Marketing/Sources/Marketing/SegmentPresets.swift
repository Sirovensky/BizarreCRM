import Foundation

/// Pre-baked segment rulesets for common audience patterns.
public enum SegmentPresets {
    public struct Preset: Sendable {
        public let name: String
        public let rule: SegmentRuleGroup
    }

    public static let all: [Preset] = [vips, dormant, new, highLTV, `repeat`, atRisk]

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
}
