import Foundation

// MARK: - BundleRuleCriteria

/// Declarative criteria that a notification must match to be included in the rule.
public struct BundleRuleCriteria: Sendable, Equatable {

    /// If non-nil, notification's event category must match.
    public let category: EventCategory?

    /// If non-nil, notification's event must match one of these values.
    public let events: [NotificationEvent]?

    /// If `true`, only match events whose `defaultPriority` is `.low` or `.normal`.
    /// Critical / timeSensitive are always excluded from user-defined rules.
    public let lowPriorityOnly: Bool

    public init(
        category: EventCategory? = nil,
        events: [NotificationEvent]? = nil,
        lowPriorityOnly: Bool = false
    ) {
        self.category = category
        self.events   = events
        self.lowPriorityOnly = lowPriorityOnly
    }

    // MARK: - Matching

    func matches(_ notification: GroupableNotification) -> Bool {
        if lowPriorityOnly {
            guard notification.priority == .low || notification.priority == .normal else {
                return false
            }
        }
        if let cat = category, notification.category != cat {
            return false
        }
        if let evts = events, !evts.contains(notification.event) {
            return false
        }
        return true
    }
}

// MARK: - BundleRuleGrouping

/// How matched notifications are grouped together.
public enum BundleRuleGrouping: String, Sendable, CaseIterable, Codable {
    /// All matching notifications go into one bundle regardless of metadata.
    case all        = "all"
    /// Group by the entity referenced in the notification's `entityID`.
    case byEntity   = "by_entity"
    /// Group by calendar day (based on `receivedAt`).
    case byDay      = "by_day"

    public var displayName: String {
        switch self {
        case .all:      return "All together"
        case .byEntity: return "Per customer / entity"
        case .byDay:    return "Per day"
        }
    }
}

// MARK: - BundleRule

/// A user-authored rule that bundles a subset of notifications into one or more groups.
///
/// Rules are value types — always copy-on-write via `with*` helpers.
/// Rules are applied in priority order by `BundleRuleEngine`; the first matching rule wins.
public struct BundleRule: Identifiable, Sendable, Equatable {

    // MARK: - Identity

    public let id: String
    public let name: String

    // MARK: - Logic

    public let criteria: BundleRuleCriteria
    public let grouping: BundleRuleGrouping

    /// Whether this rule is currently active. Disabled rules are skipped by the engine.
    public let isEnabled: Bool

    // MARK: - Init

    public init(
        id: String = UUID().uuidString,
        name: String,
        criteria: BundleRuleCriteria,
        grouping: BundleRuleGrouping = .all,
        isEnabled: Bool = true
    ) {
        self.id        = id
        self.name      = name
        self.criteria  = criteria
        self.grouping  = grouping
        self.isEnabled = isEnabled
    }

    // MARK: - Copy-on-write helpers

    public func withName(_ name: String) -> BundleRule {
        BundleRule(id: id, name: name, criteria: criteria, grouping: grouping, isEnabled: isEnabled)
    }

    public func withCriteria(_ criteria: BundleRuleCriteria) -> BundleRule {
        BundleRule(id: id, name: name, criteria: criteria, grouping: grouping, isEnabled: isEnabled)
    }

    public func withGrouping(_ grouping: BundleRuleGrouping) -> BundleRule {
        BundleRule(id: id, name: name, criteria: criteria, grouping: grouping, isEnabled: isEnabled)
    }

    public func withEnabled(_ enabled: Bool) -> BundleRule {
        BundleRule(id: id, name: name, criteria: criteria, grouping: grouping, isEnabled: enabled)
    }

    // MARK: - Factory presets

    /// "Bundle all tickets per customer" — the canonical example from §13.
    public static let ticketsPerCustomer = BundleRule(
        id: "preset.tickets_per_customer",
        name: "Tickets per customer",
        criteria: BundleRuleCriteria(category: .tickets, lowPriorityOnly: false),
        grouping: .byEntity
    )

    /// "Bundle all invoices per day" — the canonical example from §13.
    public static let invoicesPerDay = BundleRule(
        id: "preset.invoices_per_day",
        name: "Invoices per day",
        criteria: BundleRuleCriteria(category: .billing, lowPriorityOnly: true),
        grouping: .byDay
    )
}
