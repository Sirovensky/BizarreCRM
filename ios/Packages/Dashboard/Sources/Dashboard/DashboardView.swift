import SwiftUI
import Core
import DesignSystem
import Networking
import Sync
import Timeclock
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §3.6 Recent Activity

/// A single event in the recent-activity feed.
/// The feed is a thin stub: icon + description + relative timestamp.
/// Real data will come from `GET /activity?limit=20` (§3.6).
public struct ActivityEvent: Identifiable, Sendable {
    public let id: UUID
    public let icon: String   // SF Symbol name
    public let description: String
    public let date: Date

    public init(id: UUID = UUID(), icon: String, description: String, date: Date) {
        self.id = id
        self.icon = icon
        self.description = description
        self.date = date
    }
}

// MARK: - §3.7 Announcement

/// A single announcement from the system.
/// In production these come from `GET /system/announcements?since=<last_seen>`.
/// `lastSeenKey` is the `UserDefaults` key used to persist the dismissed ID.
public struct DashboardAnnouncement: Sendable {
    public let id: String
    public let body: String

    public init(id: String, body: String) {
        self.id = id
        self.body = body
    }
}

public struct DashboardView: View {
    @State private var vm: DashboardViewModel
    @State private var clockVM: ClockInOutViewModel

    /// - Parameters:
    ///   - repo: Dashboard data repository.
    ///   - api: APIClient for all network calls (timeclock included).
    ///   - userIdProvider: Closure that returns the current user's ID for
    ///     timeclock calls. Defaults to `{ 0 }` — a placeholder until
    ///     `GET /auth/me` is wired (TODO post-phase-11).
    public init(
        repo: DashboardRepository,
        api: APIClient,
        userIdProvider: (@Sendable () async -> Int64)? = nil
    ) {
        _vm = State(wrappedValue: DashboardViewModel(repo: repo))
        _clockVM = State(wrappedValue: ClockInOutViewModel(api: api, userIdProvider: userIdProvider))
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Dashboard")
                #if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .refreshable { await vm.forceRefresh() }
                .task { await vm.load() }
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        case .failed:
            // When offline with no cached data, show the offline empty state.
            // Otherwise show the error pane with retry.
            if !Reachability.shared.isOnline && vm.lastSyncedAt == nil {
                OfflineEmptyStateView(entityName: "dashboard data")
                    .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            } else if case let .failed(message) = vm.state {
                DashboardErrorPane(message: message) {
                    Task { await vm.load() }
                }
                .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            }
        case .loaded(let snapshot):
            LoadedBody(snapshot: snapshot, clockVM: clockVM, lastSyncedAt: vm.lastSyncedAt)
                .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        }
    }
}

// MARK: - Loaded state

private struct LoadedBody: View {
    let snapshot: DashboardSnapshot
    var clockVM: ClockInOutViewModel
    /// §3.10 — last sync timestamp for the inline sync-status pill.
    var lastSyncedAt: Date? = nil
    /// §3.7 — announcement to show above the KPI grid (nil = none).
    var announcement: DashboardAnnouncement? = nil
    /// §3.6 — recent-activity events (empty = section hidden).
    var recentActivity: [ActivityEvent] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                // §3.10 — greeting row with inline sync-status pill
                HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.sm) {
                    greeting
                    Spacer(minLength: BrandSpacing.xs)
                    SyncStatusPill(lastSyncedAt: lastSyncedAt)
                }
                // §3.7 — announcement banner above KPI grid
                if let ann = announcement {
                    AnnouncementBanner(announcement: ann)
                }
                ClockInOutTile(vm: clockVM)
                heroCard
                secondaryGrid
                attentionCard
                // §3.6 — recent activity feed below attention card
                if !recentActivity.isEmpty {
                    RecentActivityCard(events: recentActivity)
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.top, BrandSpacing.sm)
            .padding(.bottom, BrandSpacing.lg)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// §3.9 — dynamic greeting by hour. Reads the current locale's first
    /// day-part name, falls back to "Hello" if the clock lies. No server
    /// round trip; the user's first name would need `/auth/me` which is
    /// still TBD, so for now we keep it impersonal.
    private var greeting: some View {
        Text(dashboardGreeting(for: Date()))
            .font(.brandTitleLarge())
            .foregroundStyle(.bizarreOnSurface)
            .accessibilityAddTraits(.isHeader)
            .layoutPriority(1)
    }

    // greetingText extracted to module-level `dashboardGreeting(for:)` for testability.

    // Hero = the one primary focus. On a repair-shop dashboard that's
    // "open tickets right now". Larger, more visual weight than the rest.
    private var heroCard: some View {
        let s = snapshot.summary
        return HeroMetricCard(
            value: "\(s.openTickets)",
            label: "Open tickets",
            supporting: "\(s.ticketsCreatedToday) new today"
        )
    }

    // Compact stat tiles — muted hierarchy.
    // iPhone: 2-column grid (adaptive minimum 140 pt).
    // iPad (regular-width): fixed 3-column grid per §3 spec.
    //
    // §3.1 — delta field is nil until the server returns a prior-period
    // comparison value. When present, a green ▲ / red ▼ badge appears.
    private var secondaryGrid: some View {
        let s = snapshot.summary
        let tiles: [StatTile] = [
            .init(label: "Revenue",      value: Self.money(s.revenueToday),   icon: "dollarsign.circle", delta: nil),
            .init(label: "Closed",       value: "\(s.closedToday)",           icon: "checkmark.seal",    delta: nil),
            .init(label: "Appointments", value: "\(s.appointmentsToday)",     icon: "calendar",           delta: nil),
            .init(label: "Inventory",    value: Self.money(s.inventoryValue), icon: "shippingbox",        delta: nil),
        ]

        let columns: [GridItem] = Platform.isCompact
            ? [GridItem(.adaptive(minimum: 140), spacing: BrandSpacing.md)]
            : [
                GridItem(.flexible(), spacing: BrandSpacing.md),
                GridItem(.flexible(), spacing: BrandSpacing.md),
                GridItem(.flexible(), spacing: BrandSpacing.md),
              ]

        return LazyVGrid(columns: columns, spacing: BrandSpacing.md) {
            ForEach(tiles) { tile in
                StatTileCard(tile: tile)
            }
        }
    }

    @ViewBuilder
    private var attentionCard: some View {
        let a = snapshot.attention
        let items: [AttentionItem] = [
            .init(label: "Stale tickets",    count: a.staleTickets.count),
            .init(label: "Overdue invoices", count: a.overdueInvoices.count),
            .init(label: "Missing parts",    count: a.missingPartsCount),
            .init(label: "Low stock",        count: a.lowStockCount),
        ]
        let total = items.reduce(0) { $0 + $1.count }

        if total > 0 {
            AttentionCard(items: items)
        } else {
            // §3.3 — empty state: "All clear. Nothing needs your attention."
            AttentionEmptyCard()
        }
    }

    private static func money(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }
}

// MARK: - Hero metric card

private struct HeroMetricCard: View {
    let value: String
    let label: String
    let supporting: String

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(label.uppercased())
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .tracking(0.8)
            Text(value)
                .font(.brandDisplayMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(supporting)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .monospacedDigit()
        }
        .padding(BrandSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value). \(supporting).")
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Stat tile

private struct StatTile: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let icon: String
    /// §3.1 — previous-period delta as a percentage (positive = up, negative = down).
    /// `nil` means no comparison data is available (no badge rendered).
    let delta: Double?
}

private struct StatTileCard: View {
    let tile: StatTile

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(alignment: .top) {
                Image(systemName: tile.icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Spacer(minLength: BrandSpacing.xs)
                // §3.1 — delta badge
                if let delta = tile.delta {
                    DeltaBadge(delta: delta)
                }
            }
            Text(tile.value)
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(tile.label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.label)
        .accessibilityValue(deltaBadgeA11yValue)
    }

    private var deltaBadgeA11yValue: String {
        guard let delta = tile.delta else { return tile.value }
        let sign = delta >= 0 ? "up" : "down"
        let pct = abs(delta)
        let formatted = String(format: "%.0f", pct)
        return "\(tile.value), \(sign) \(formatted) percent vs prior period"
    }
}

// MARK: - §3.1 Delta badge

/// Green ▲ / red ▼ percentage change vs. the prior period.
/// Positive delta = green (improvement), negative = red (decline).
private struct DeltaBadge: View {
    let delta: Double

    private var isPositive: Bool { delta >= 0 }
    private var arrow: String { isPositive ? "arrow.up" : "arrow.down" }
    private var color: Color { isPositive ? .bizarreSuccess : .bizarreError }
    private var label: String {
        let pct = abs(delta)
        if pct < 10 {
            return String(format: "%.1f%%", pct)
        } else {
            return String(format: "%.0f%%", pct)
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: arrow)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(label)
                .font(.brandLabelSmall())
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, BrandSpacing.xs)
        .padding(.vertical, BrandSpacing.xxs)
        .background(color.opacity(0.15), in: Capsule())
        .accessibilityHidden(true)  // parent tile exposes the full a11y value
    }
}

// MARK: - Attention card

private struct AttentionItem: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
}

private struct AttentionCard: View {
    let items: [AttentionItem]

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.bizarreWarning)
                    .accessibilityHidden(true)
                Text("Needs attention")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
            }

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    AttentionRow(item: item)
                    if idx < items.count - 1 {
                        Divider()
                            .overlay(Color.bizarreOutline.opacity(0.25))
                    }
                }
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }
}

// MARK: - §3.3 Needs-attention empty state

/// Shown when there are zero attention items.
/// "All clear. Nothing needs your attention." + sparkle icon.
private struct AttentionEmptyCard: View {
    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("All clear")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Nothing needs your attention right now.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreSuccess.opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Needs attention: all clear. Nothing needs your attention right now.")
    }
}

private struct AttentionRow: View {
    let item: AttentionItem

    var body: some View {
        HStack {
            Text(item.label)
                .font(.brandBodyMedium())
                .foregroundStyle(item.count > 0 ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
            Spacer(minLength: BrandSpacing.sm)
            Text("\(item.count)")
                .font(.brandTitleSmall())
                .foregroundStyle(item.count > 0 ? .bizarreWarning : .bizarreOnSurfaceMuted)
                .monospacedDigit()
        }
        .padding(.vertical, BrandSpacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.label)
        .accessibilityValue("\(item.count)")
        .contextMenu {
            #if canImport(UIKit)
            Button {
                UIPasteboard.general.string = "\(item.label): \(item.count)"
            } label: {
                Label("Copy '\(item.label): \(item.count)'", systemImage: "doc.on.doc")
            }
            #endif
        }
    }
}

// MARK: - Layout helpers (internal for testability)

/// Returns the number of KPI grid columns for the given compactness flag.
/// - compact (iPhone): adaptive — 1 or 2 columns depending on available width.
///   We return 1 here to signal "adaptive" mode; the real minimum is 140 pt.
/// - regular (iPad): always 3 fixed columns.
func kpiGridColumnCount(isCompact: Bool) -> Int {
    isCompact ? 1 : 3
}

/// Returns the attention items from a `NeedsAttention` snapshot,
/// in a stable order. Caller sums `.count` to decide whether to show the card.
func attentionItems(from attention: NeedsAttention) -> [AttentionItemModel] {
    [
        .init(label: "Stale tickets",    count: attention.staleTickets.count),
        .init(label: "Overdue invoices", count: attention.overdueInvoices.count),
        .init(label: "Missing parts",    count: attention.missingPartsCount),
        .init(label: "Low stock",        count: attention.lowStockCount),
    ]
}

/// View-model for a single row in the Needs Attention card.
struct AttentionItemModel: Equatable {
    let label: String
    let count: Int
}

/// Returns the time-of-day greeting string for the given date.
/// Extracted from `LoadedBody` so tests can reach it without UIKit.
func dashboardGreeting(for date: Date) -> String {
    let hour = Calendar.current.component(.hour, from: date)
    switch hour {
    case 5..<12:  return "Good morning"
    case 12..<17: return "Good afternoon"
    case 17..<22: return "Good evening"
    default:      return "Working late"
    }
}

// MARK: - §3.10 Sync-status pill

/// Glass pill in the dashboard greeting row showing sync health.
///
/// States mirror `StalenessLevel` from the Sync package:
///   - fresh  → "Synced N min ago"  (green)
///   - warning → "Synced N hr ago"  (amber)
///   - stale  → "Stale data"         (red)
///   - never  → "Never synced"       (red)
///
/// Tap → §3.10 deep-link to Settings → Data → Sync Issues (wiring TBD).
private struct SyncStatusPill: View {
    let lastSyncedAt: Date?

    private var logic: StalenessLogic { StalenessLogic(lastSyncedAt: lastSyncedAt) }

    var body: some View {
        HStack(spacing: BrandSpacing.xs) {
            Circle()
                .fill(logic.stalenessLevel.color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(logic.label)
                .font(.brandLabelSmall())
                .foregroundStyle(logic.stalenessLevel.color)
                .lineLimit(1)
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .brandGlass(.clear, in: Capsule(), tint: logic.stalenessLevel.color.opacity(0.12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(logic.a11yLabel)
    }
}

// MARK: - §3.7 Announcement banner

/// Sticky glass banner shown above the KPI grid when `announcement` is non-nil.
/// "Dismiss" persists the last-seen announcement ID in `UserDefaults` so the
/// banner doesn't reappear after dismissal.
///
/// Key used: `dashboard.announcement.lastSeenId`
private struct AnnouncementBanner: View {
    let announcement: DashboardAnnouncement
    @State private var dismissed = false

    private static let defaultsKey = "dashboard.announcement.lastSeenId"

    var body: some View {
        if !dismissed {
            HStack(alignment: .top, spacing: BrandSpacing.sm) {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)

                Text(announcement.body)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    withAnimation(BrandMotion.snappy) {
                        dismissed = true
                    }
                    UserDefaults.standard.set(
                        announcement.id,
                        forKey: Self.defaultsKey
                    )
                } label: {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss announcement")
            }
            .padding(BrandSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .brandGlass(.clear, in: RoundedRectangle(cornerRadius: 14),
                        tint: Color.bizarreOrange.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.bizarreOrange.opacity(0.3), lineWidth: 0.5)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Announcement: \(announcement.body)")
            .onAppear {
                // Re-check dismissal in case the view re-appeared after background.
                let seen = UserDefaults.standard.string(forKey: Self.defaultsKey)
                if seen == announcement.id { dismissed = true }
            }
        }
    }
}

// MARK: - §3.6 Recent activity feed

/// Compact last-N-events list below the attention card.
/// Chronological, icon per event type, tap → deep link (deep-link wiring TBD).
private struct RecentActivityCard: View {
    let events: [ActivityEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // Header
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.bizarreTeal)
                    .accessibilityHidden(true)
                Text("Recent activity")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer(minLength: 0)
            }

            // Rows
            VStack(spacing: 0) {
                ForEach(Array(events.prefix(5).enumerated()), id: \.element.id) { idx, event in
                    ActivityRow(event: event)
                    if idx < min(events.count, 5) - 1 {
                        Divider()
                            .overlay(Color.bizarreOutline.opacity(0.2))
                    }
                }
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent activity")
    }
}

private struct ActivityRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: event.icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.bizarreTeal)
                .frame(width: 22, alignment: .center)
                .accessibilityHidden(true)

            Text(event.description)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(1)

            Spacer(minLength: BrandSpacing.xs)

            Text(event.date, style: .relative)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, BrandSpacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.description), \(event.date.formatted(.relative(presentation: .named)))")
    }
}

// MARK: - Error pane

private struct DashboardErrorPane: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load the dashboard")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
