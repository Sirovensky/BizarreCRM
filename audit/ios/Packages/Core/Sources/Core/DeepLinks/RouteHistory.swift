import Foundation

// MARK: - RouteHistory

/// Maintains a breadcrumb trail of deep-link destinations navigated during
/// the current session.
///
/// Used by:
/// - Debug overlay to display the last N routes reached via deep link.
/// - Navigation breadcrumb UI that can optionally back-step through the trail.
///
/// Thread-safe: actor-isolated; all mutations happen on the actor.
/// The `entries` snapshot is `@MainActor`-safe for SwiftUI binding.
///
/// Capacity is capped at `maxCapacity` (default 50) to avoid unbounded growth.
public actor RouteHistory {

    // MARK: - Shared instance

    public static let shared = RouteHistory()

    // MARK: - Entry

    public struct Entry: Sendable, Identifiable, Equatable {
        public let id: UUID
        public let destination: DeepLinkDestination
        public let arrivedAt: Date

        public init(destination: DeepLinkDestination, arrivedAt: Date = .now) {
            self.id          = UUID()
            self.destination = destination
            self.arrivedAt   = arrivedAt
        }
    }

    // MARK: - State

    private var _entries: [Entry] = []
    public let maxCapacity: Int

    // MARK: - Init

    public init(maxCapacity: Int = 50) {
        self.maxCapacity = maxCapacity
    }

    // MARK: - Public API

    /// Append a destination to the trail.
    ///
    /// Duplicates of the most recent entry are silently dropped to avoid
    /// recording the same route twice (e.g. when `onRoute` fires for a
    /// repeated `.dashboard` tap).
    public func record(_ destination: DeepLinkDestination) {
        if _entries.last?.destination == destination { return }
        _entries.append(Entry(destination: destination))
        if _entries.count > maxCapacity {
            _entries.removeFirst(_entries.count - maxCapacity)
        }
    }

    /// A snapshot of all recorded entries, oldest-first.
    public var entries: [Entry] { _entries }

    /// The most recently recorded entry, or `nil` if the trail is empty.
    public var last: Entry? { _entries.last }

    /// Clear the history (e.g. on sign-out).
    public func clear() {
        _entries.removeAll()
    }

    /// Returns the last `count` entries, most-recent-first.
    public func tail(_ count: Int) -> [Entry] {
        Array(_entries.suffix(count).reversed())
    }
}

// MARK: - DeepLinkDestination display helpers

extension DeepLinkDestination {

    /// A short human-readable label for breadcrumb UI and the debug overlay.
    public var breadcrumbLabel: String {
        switch self {
        case .dashboard(let slug):
            return "Dashboard · \(slug)"
        case .ticket(let slug, let id):
            return "Ticket \(id) · \(slug)"
        case .customer(let slug, let id):
            return "Customer \(id) · \(slug)"
        case .invoice(let slug, let id):
            return "Invoice \(id) · \(slug)"
        case .estimate(let slug, let id):
            return "Estimate \(id) · \(slug)"
        case .lead(let slug, let id):
            return "Lead \(id) · \(slug)"
        case .appointment(let slug, let id):
            return "Appointment \(id) · \(slug)"
        case .inventory(let slug, let sku):
            return "Inventory \(sku) · \(slug)"
        case .smsThread(let slug, let phone):
            return "SMS \(phone) · \(slug)"
        case .reports(let slug, let name):
            return "Report \(name) · \(slug)"
        case .posRoot(let slug):
            return "POS · \(slug)"
        case .posNewCart(let slug):
            return "POS New Cart · \(slug)"
        case .posReturn(let slug):
            return "POS Return · \(slug)"
        case .settings(let slug, let section):
            let tab = section ?? "root"
            return "Settings/\(tab) · \(slug)"
        case .auditLogs(let slug):
            return "Audit Logs · \(slug)"
        case .search(let slug, let query):
            let q = query ?? ""
            return "Search \"\(q)\" · \(slug)"
        case .notifications(let slug):
            return "Notifications · \(slug)"
        case .timeclock(let slug):
            return "Timeclock · \(slug)"
        case .magicLink:
            return "Magic Link"
        case .resetPassword:
            return "Reset Password"
        case .setupInvite:
            return "Setup Invite"
        }
    }
}
