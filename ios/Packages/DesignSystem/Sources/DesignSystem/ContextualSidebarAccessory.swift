import SwiftUI

// §22 — Sidebar badge counts for use next to tab labels in iPad
// `NavigationSplitView` sidebar.
//
// Reads counts from `WidgetSnapshot` (App Group cache written by Phase 6 B).
// Falls back gracefully to hidden state when no snapshot is available.
//
// Usage:
//   Label {
//       HStack {
//           Text("Tickets")
//           Spacer()
//           SidebarBadge(count: vm.openTicketCount)
//       }
//   } icon: {
//       Image(systemName: "ticket")
//   }

// MARK: - Badge view

/// A compact badge pill shown alongside a sidebar label.
///
/// Displays nothing when `count` is 0 to avoid visual noise.
/// Uses Liquid Glass chrome for the badge background per §30 (glass on chrome only).
public struct SidebarBadge: View {
    public let count: Int

    public init(count: Int) {
        self.count = count
    }

    public var body: some View {
        if count > 0 {
            Text(formatted)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xxs)
                .background(Color.bizarreOrange, in: Capsule())
                .accessibilityLabel("\(count) \(count == 1 ? "item" : "items")")
        }
    }

    private var formatted: String {
        count > 999 ? "999+" : "\(count)"
    }
}

// MARK: - ViewModel

/// Reads `WidgetSnapshot` badge counts from App Group UserDefaults and
/// exposes them to the sidebar. `@Observable` so SwiftUI re-renders when
/// the snapshot changes (e.g. after background sync).
///
/// Scope: tablet sidebar only — iPhone hides badge counts by default.
@MainActor
@Observable
public final class ContextualSidebarAccessoryViewModel {

    // MARK: Published counts

    /// Number of open (non-terminal) tickets.
    public private(set) var openTicketCount: Int = 0

    /// Number of upcoming (non-cancelled, future) appointments.
    public private(set) var pendingAppointmentCount: Int = 0

    // MARK: Private state

    private let suiteName: String

    // MARK: Init

    /// - Parameter suiteName: App Group suite. Defaults to `group.com.bizarrecrm`.
    public init(suiteName: String = "group.com.bizarrecrm") {
        self.suiteName = suiteName
        reload()
    }

    // MARK: Public API

    /// Re-read counts from App Group UserDefaults. Call after each background sync.
    public func reload() {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: "com.bizarrecrm.widget.snapshot"),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshotCodable.self, from: data) else {
            return
        }
        openTicketCount = snapshot.openTicketCount
        pendingAppointmentCount = snapshot.nextAppointments.count
    }
}

// MARK: - Local snapshot decodable (avoids cross-module import of Core)
//
// DesignSystem cannot import Core (that would create a circular dependency via
// the Core → DesignSystem import). We decode only the fields we need.

private struct WidgetSnapshotCodable: Decodable {
    let openTicketCount: Int
    let nextAppointments: [ApptEntry]

    struct ApptEntry: Decodable {
        let id: Int64
    }
}

// MARK: - Sidebar row modifier

/// Adds a `SidebarBadge` as an overlay trailing the label in a sidebar row.
///
/// Use with `Label` inside a `NavigationSplitView` sidebar `List`.
public struct SidebarBadgeModifier: ViewModifier {
    public let count: Int

    public init(count: Int) {
        self.count = count
    }

    public func body(content: Content) -> some View {
        HStack {
            content
            Spacer()
            SidebarBadge(count: count)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Convenience

public extension View {
    /// Overlay a badge count pill on a sidebar row.
    func sidebarBadge(_ count: Int) -> some View {
        self.modifier(SidebarBadgeModifier(count: count))
    }
}
