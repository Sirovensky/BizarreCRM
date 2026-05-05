import Foundation

// MARK: - FocusMode

/// Named Focus modes that BizarreCRM can target.
/// iOS does not expose a public API to read the *active* Focus; this enum
/// models the policy the *user* configures inside the app.
///
/// Entitlement note: `com.apple.developer.focus` (read-current-focus) is
/// NOT set in `BizarreCRM.entitlements` by default. The runtime check
/// via `INFocusStatusCenter` requires that entitlement to be provisioned.
/// Until it is provisioned, `FocusFilterDescriptor` operates in policy-only
/// mode — the user picks a mode and configures policy, but the app cannot
/// automatically detect when that mode is active.
public enum FocusMode: String, Sendable, CaseIterable, Codable, Identifiable {
    case doNotDisturb = "Do Not Disturb"
    case work         = "Work"
    case personal     = "Personal"
    case sleep        = "Sleep"
    case driving      = "Driving"
    case custom       = "Custom"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .doNotDisturb: return "moon.fill"
        case .work:         return "briefcase.fill"
        case .personal:     return "person.fill"
        case .sleep:        return "bed.double.fill"
        case .driving:      return "car.fill"
        case .custom:       return "slider.horizontal.3"
        }
    }
}

// MARK: - FocusFilterPolicy

/// Notification-delivery policy for a given Focus mode.
/// Immutable — always construct a new value; never mutate.
public struct FocusFilterPolicy: Sendable, Equatable {
    /// Which Focus mode this policy applies to.
    public let focusMode: FocusMode
    /// Categories that are *allowed* to surface during this Focus.
    /// An empty set means "suppress all non-critical".
    public let allowedCategories: Set<EventCategory>
    /// When true, critical-priority notifications bypass the policy.
    public let allowCriticalOverride: Bool

    public init(
        focusMode: FocusMode,
        allowedCategories: Set<EventCategory>,
        allowCriticalOverride: Bool = true
    ) {
        self.focusMode = focusMode
        self.allowedCategories = allowedCategories
        self.allowCriticalOverride = allowCriticalOverride
    }

    /// Predefined Work policy: only tickets + communications + admin.
    public static func workDefault() -> FocusFilterPolicy {
        FocusFilterPolicy(
            focusMode: .work,
            allowedCategories: [.tickets, .communications, .admin],
            allowCriticalOverride: true
        )
    }

    /// Predefined DND policy: only critical events pass through.
    public static func doNotDisturbDefault() -> FocusFilterPolicy {
        FocusFilterPolicy(
            focusMode: .doNotDisturb,
            allowedCategories: [],
            allowCriticalOverride: true
        )
    }

    /// Sleep policy: suppress everything including non-critical.
    public static func sleepDefault() -> FocusFilterPolicy {
        FocusFilterPolicy(
            focusMode: .sleep,
            allowedCategories: [],
            allowCriticalOverride: false
        )
    }
}

// MARK: - FocusFilterDescriptor

/// Describes per-Focus-mode notification policies.
/// Read-only from the perspective of `NotificationHandler` — the user
/// configures policies via `FocusFilterSettingsView`.
public struct FocusFilterDescriptor: Sendable, Equatable {

    // MARK: - State

    public private(set) var policies: [FocusMode: FocusFilterPolicy]

    // MARK: - Init

    public init(policies: [FocusMode: FocusFilterPolicy] = [:]) {
        self.policies = policies
    }

    /// Build the default descriptor with preset policies.
    public static func defaultDescriptor() -> FocusFilterDescriptor {
        FocusFilterDescriptor(policies: [
            .doNotDisturb: .doNotDisturbDefault(),
            .work: .workDefault(),
            .sleep: .sleepDefault()
        ])
    }

    // MARK: - Querying

    /// Returns whether a notification item should be shown given the active policy.
    /// - Parameters:
    ///   - item: The notification to evaluate.
    ///   - activeMode: The currently active Focus mode (nil = no Focus active → show all).
    public func shouldShow(item: GroupableNotification, activeMode: FocusMode?) -> Bool {
        guard let mode = activeMode, let policy = policies[mode] else {
            return true // No active Focus or no policy → show
        }

        // Critical override
        if policy.allowCriticalOverride && item.priority == .critical {
            return true
        }

        // Allowed category check
        return policy.allowedCategories.contains(item.category)
    }

    // MARK: - Immutable update

    /// Return a new descriptor with an updated policy for a Focus mode.
    public func updatingPolicy(_ policy: FocusFilterPolicy) -> FocusFilterDescriptor {
        var updated = policies
        updated[policy.focusMode] = policy
        return FocusFilterDescriptor(policies: updated)
    }
}
