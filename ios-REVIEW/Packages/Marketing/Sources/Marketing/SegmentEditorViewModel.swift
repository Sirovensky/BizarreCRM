import Foundation
import Observation
import Core
import Networking

// MARK: - Field / Comparator catalogues

/// §37 — Audience builder segment fields.
/// Covers: tag, last-visit window, LTV tier, device type, service history,
/// birthday month per §37 spec plus the original set.
public enum SegmentField: String, CaseIterable, Sendable {
    case lifetimeSpend     = "lifetime_spend"
    case lastVisitDaysAgo  = "last_visit_days_ago"
    case ticketCount       = "ticket_count"
    case deviceType        = "device_type"
    case birthdayMonth     = "birthday_month"
    case createdAt         = "created_at"
    // §37 new fields for deep audience builder
    case tag               = "tag"
    case ltvTier           = "ltv_tier"         // bronze / silver / gold / platinum
    case serviceType       = "service_type"      // service history (repair type)
    case totalRepairs      = "total_repairs"

    public var displayName: String {
        switch self {
        case .lifetimeSpend:    return "Lifetime spend ($)"
        case .lastVisitDaysAgo: return "Days since last visit"
        case .ticketCount:      return "Ticket count"
        case .deviceType:       return "Device type"
        case .birthdayMonth:    return "Birthday month"
        case .createdAt:        return "Created date"
        case .tag:              return "Tag"
        case .ltvTier:          return "LTV tier"
        case .serviceType:      return "Service type"
        case .totalRepairs:     return "Total repairs"
        }
    }

    /// Comparators valid for this field.
    public var validComparators: [SegmentComparator] {
        switch self {
        case .lifetimeSpend, .lastVisitDaysAgo, .ticketCount, .totalRepairs:
            return [.gt, .lt, .eq, .neq]
        case .birthdayMonth:
            return [.eq, .neq]
        case .tag, .ltvTier, .deviceType, .serviceType:
            return [.eq, .neq, .contains]
        case .createdAt:
            return [.gt, .lt, .eq]
        }
    }
}

public enum SegmentComparator: String, CaseIterable, Sendable {
    case gt       = ">"
    case lt       = "<"
    case eq       = "="
    case neq      = "!="
    case contains = "contains"
    case inList   = "in [list]"

    public var displayName: String { rawValue }
}

// MARK: - SegmentEditorViewModel

@MainActor
@Observable
public final class SegmentEditorViewModel {
    public var name: String = ""
    public var rootGroup: SegmentRuleGroup = SegmentRuleGroup(op: "AND", rules: [])
    public private(set) var liveCount: Int? = nil
    public private(set) var isCountLoading = false
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    public private(set) var savedSegment: Segment?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: Rule tree mutations (immutable-copy pattern)

    public func setRootOp(_ op: String) {
        rootGroup = SegmentRuleGroup(op: op, rules: rootGroup.rules)
        scheduleCountRefresh()
    }

    public func addLeaf() {
        let leaf = SegmentRule.leaf(
            field: SegmentField.lifetimeSpend.rawValue,
            op: SegmentComparator.gt.rawValue,
            value: "0"
        )
        rootGroup = SegmentRuleGroup(op: rootGroup.op, rules: rootGroup.rules + [leaf])
        scheduleCountRefresh()
    }

    public func addGroup() {
        let nested = SegmentRuleGroup(op: "AND", rules: [])
        rootGroup = SegmentRuleGroup(
            op: rootGroup.op,
            rules: rootGroup.rules + [.group(nested)]
        )
        scheduleCountRefresh()
    }

    public func removeRule(at index: Int) {
        var newRules = rootGroup.rules
        guard index < newRules.count else { return }
        newRules.remove(at: index)
        rootGroup = SegmentRuleGroup(op: rootGroup.op, rules: newRules)
        scheduleCountRefresh()
    }

    /// Update a top-level leaf rule by index (returns copy, never mutates in place).
    public func updateLeaf(at index: Int, field: String, op: String, value: String) {
        var newRules = rootGroup.rules
        guard index < newRules.count else { return }
        newRules[index] = .leaf(field: field, op: op, value: value)
        rootGroup = SegmentRuleGroup(op: rootGroup.op, rules: newRules)
        scheduleCountRefresh()
    }

    /// Load a preset ruleset.
    public func applyPreset(_ preset: SegmentPresets.Preset) {
        name = preset.name
        rootGroup = preset.rule
        scheduleCountRefresh()
    }

    // MARK: Live count (debounced 500ms)

    private func scheduleCountRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            await refreshCount()
        }
    }

    public func refreshCount() async {
        isCountLoading = true
        defer { isCountLoading = false }
        do {
            let resp = try await api.previewSegmentCount(rule: rootGroup)
            liveCount = resp.count
        } catch {
            // Live count failure is non-fatal; just clear
            liveCount = nil
            AppLog.ui.warning("Segment preview count failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Save

    public func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            errorMessage = "Segment name is required."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let req = CreateSegmentRequest(name: trimmedName, rule: rootGroup)
            savedSegment = try await api.createSegment(req)
        } catch {
            AppLog.ui.error("Segment save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Serialisation helper (for tests)

    public func serializedRule() throws -> Data {
        try JSONEncoder().encode(rootGroup)
    }
}
