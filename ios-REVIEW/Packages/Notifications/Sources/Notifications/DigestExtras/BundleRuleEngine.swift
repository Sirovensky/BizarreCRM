import Foundation

// MARK: - RuleBundleResult

/// Output from `BundleRuleEngine.apply(rules:to:)`.
/// Matched notifications are collected into named `RuleBundle` groups;
/// unmatched notifications are returned as `unmatched`.
public struct RuleBundleResult: Sendable, Equatable {

    /// Groups produced by rules. One rule may produce multiple groups
    /// (e.g. `byEntity` groups per unique `entityID`).
    public let groups: [RuleBundle]

    /// Notifications that were not claimed by any rule.
    public let unmatched: [GroupableNotification]

    public init(groups: [RuleBundle], unmatched: [GroupableNotification]) {
        self.groups    = groups
        self.unmatched = unmatched
    }
}

// MARK: - RuleBundle

/// A single output bundle produced by one `BundleRule`.
public struct RuleBundle: Identifiable, Sendable, Equatable {
    public let id: String
    public let ruleName: String
    public let groupKey: String       // rule.id + grouping discriminator
    public let items: [GroupableNotification]

    public var count: Int { items.count }

    public init(
        id: String = UUID().uuidString,
        ruleName: String,
        groupKey: String,
        items: [GroupableNotification]
    ) {
        self.id       = id
        self.ruleName = ruleName
        self.groupKey = groupKey
        self.items    = items
    }
}

// MARK: - BundleRuleEngine

/// Pure, stateless function that applies an ordered list of `BundleRule`s
/// to a flat notification list and returns grouped output.
///
/// Design constraints:
/// - No mutation: the input array is never modified.
/// - First-match wins: a notification is claimed by the first enabled rule
///   whose criteria match it. Subsequent rules never see it.
/// - Critical-priority notifications bypass all rules and land in `unmatched`.
/// - Rules with `isEnabled == false` are silently skipped.
/// - Empty rule list → all notifications land in `unmatched`.
///
/// Grouping semantics:
/// - `.all`      → all matched items land in one `RuleBundle` keyed `<ruleID>:all`.
/// - `.byEntity` → items keyed by `entityID` (falls back to `event.category.rawValue`).
/// - `.byDay`    → items keyed by ISO-8601 day string derived from `receivedAt`.
public enum BundleRuleEngine {

    // MARK: - Public API

    /// Apply rules to a notification list.
    ///
    /// - Parameters:
    ///   - rules:    Ordered list of rules. First match wins.
    ///   - items:    Flat list of notifications to process.
    ///   - calendar: Calendar used for `.byDay` grouping (default `.current`).
    /// - Returns: `RuleBundleResult` with groups + unmatched remainder.
    public static func apply(
        rules: [BundleRule],
        to items: [GroupableNotification],
        calendar: Calendar = .current
    ) -> RuleBundleResult {
        let enabledRules = rules.filter(\.isEnabled)

        // Partition items: critical always bypass rules
        let (critical, eligible) = items.reduce(
            into: ([GroupableNotification](), [GroupableNotification]())
        ) { acc, n in
            if n.priority == .critical { acc.0.append(n) }
            else { acc.1.append(n) }
        }

        var claimed   = Set<String>()           // notification IDs already assigned
        var allGroups = [RuleBundle]()

        for rule in enabledRules {
            // Only look at items not yet claimed
            let candidates = eligible.filter {
                !claimed.contains($0.id) && rule.criteria.matches($0)
            }
            guard !candidates.isEmpty else { continue }

            let groups = makeGroups(rule: rule, candidates: candidates, calendar: calendar)
            for group in groups {
                group.items.forEach { claimed.insert($0.id) }
            }
            allGroups.append(contentsOf: groups)
        }

        // Unmatched = critical + not claimed by any rule
        let unclaimed = eligible.filter { !claimed.contains($0.id) }
        let unmatched = critical + unclaimed

        return RuleBundleResult(groups: allGroups, unmatched: unmatched)
    }

    // MARK: - Private grouping helpers

    private static func makeGroups(
        rule: BundleRule,
        candidates: [GroupableNotification],
        calendar: Calendar
    ) -> [RuleBundle] {
        switch rule.grouping {
        case .all:
            return [RuleBundle(
                ruleName: rule.name,
                groupKey: "\(rule.id):all",
                items: candidates
            )]

        case .byEntity:
            return groupByKey(candidates, key: { $0.entityID ?? $0.category.rawValue })
                .map { key, group in
                    RuleBundle(
                        ruleName: rule.name,
                        groupKey: "\(rule.id):entity:\(key)",
                        items: group
                    )
                }

        case .byDay:
            let formatter = iso8601DayFormatter(timeZone: calendar.timeZone)
            return groupByKey(candidates, key: { formatter.string(from: $0.receivedAt) })
                .map { key, group in
                    RuleBundle(
                        ruleName: rule.name,
                        groupKey: "\(rule.id):day:\(key)",
                        items: group
                    )
                }
        }
    }

    /// Group a flat array by a string key, preserving input order within each group.
    private static func groupByKey(
        _ items: [GroupableNotification],
        key: (GroupableNotification) -> String
    ) -> [(String, [GroupableNotification])] {
        var order = [String]()
        var dict  = [String: [GroupableNotification]]()
        for item in items {
            let k = key(item)
            if dict[k] == nil {
                order.append(k)
                dict[k] = []
            }
            dict[k]!.append(item)
        }
        return order.compactMap { k in dict[k].map { (k, $0) } }
    }

    private static func iso8601DayFormatter(timeZone: TimeZone = .current) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale     = Locale(identifier: "en_US_POSIX")
        f.timeZone   = timeZone
        return f
    }
}

// MARK: - GroupableNotification + entityID

/// Lightweight entity-ID shim used by `.byEntity` grouping.
/// Extracted from the notification's body prefix "EntityID:<value>" if present,
/// otherwise `nil`. The engine falls back to category name when nil.
private extension GroupableNotification {
    var entityID: String? {
        // Convention: body may start with "EntityID:<id>\n..."
        guard body.hasPrefix("EntityID:") else { return nil }
        let rest = body.dropFirst("EntityID:".count)
        return String(rest.prefix(while: { !$0.isNewline && !$0.isWhitespace }))
    }
}
