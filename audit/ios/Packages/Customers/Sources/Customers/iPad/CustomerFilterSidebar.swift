#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - CustomerFilter

/// Filter categories surfaced in the iPad three-column sidebar.
public enum CustomerFilter: String, CaseIterable, Sendable, Identifiable, Hashable {
    case all      = "All"
    case recent   = "Recent"
    case vip      = "VIP"
    case atRisk   = "At Risk"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .all:    return "person.2.fill"
        case .recent: return "clock.fill"
        case .vip:    return "star.fill"
        case .atRisk: return "exclamationmark.triangle.fill"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .all:    return "All customers"
        case .recent: return "Recently active customers"
        case .vip:    return "VIP customers"
        case .atRisk: return "At risk customers"
        }
    }

    /// Returns `true` when `customer` matches this filter.
    ///
    /// - `all` always matches.
    /// - `recent` matches customers created or active within the last 30 days.
    /// - `vip` matches customers whose `ticketCount` >= 5 (proxy for high-value relationship).
    /// - `atRisk` matches customers with no activity (ticketCount == 0 and no contactLine).
    public func matches(_ customer: CustomerSummary) -> Bool {
        switch self {
        case .all:
            return true
        case .recent:
            guard let createdAt = customer.createdAt,
                  let date = Self.parseDate(createdAt) else { return false }
            return CustomerHealth.daysSince(date) <= 30
        case .vip:
            return (customer.ticketCount ?? 0) >= 5
        case .atRisk:
            return (customer.ticketCount ?? 0) == 0 && customer.contactLine == nil
        }
    }

    private static func parseDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df.date(from: String(raw.prefix(10)))
    }
}

// MARK: - CustomerHealth (internal helper for filter date math)

private enum CustomerHealth {
    static func daysSince(_ date: Date, relativeTo now: Date = Date()) -> Int {
        max(0, Int(now.timeIntervalSince(date) / 86_400))
    }
}

// MARK: - CustomerFilterSidebar

/// The leftmost column of `CustomersThreeColumnView`.
/// Renders filter categories in a `List` with Liquid Glass chrome.
public struct CustomerFilterSidebar: View {
    @Binding public var selection: CustomerFilter

    public init(selection: Binding<CustomerFilter>) {
        _selection = selection
    }

    public var body: some View {
        List {
            ForEach(CustomerFilter.allCases, id: \.self) { filter in
                Button { selection = filter } label: {
                    HStack {
                        Label(filter.rawValue, systemImage: filter.systemImage)
                        Spacer()
                        if selection == filter {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityLabel(filter.accessibilityLabel)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Filters")
        .navigationBarTitleDisplayMode(.large)
    }
}
#endif
