import SwiftUI
import Core
import DesignSystem
import Networking
import Sync
import Timeclock
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §3.10 Sync-status pill destination key

/// Environment key that lets callers inject a navigation destination for the
/// sync-status pill. Dashboard itself has no Settings dependency, so we use
/// a closure bridge: the app root sets this and the pill calls it on tap.
private struct SyncPillActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Called when the user taps the sync-status pill. Typically opens
    /// Settings → Data → Sync Issues. Nil = pill is non-interactive.
    public var syncPillAction: (() -> Void)? {
        get { self[SyncPillActionKey.self] }
        set { self[SyncPillActionKey.self] = newValue }
    }
}

public struct DashboardView: View {
    @State private var vm: DashboardViewModel
    @State private var clockVM: ClockInOutViewModel
    @Environment(\.syncPillAction) private var syncPillAction

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
                        // §3.10 — tapping the pill opens Settings → Data → Sync Issues
                        // when the host app wires `.environment(\.syncPillAction, …)`.
                        StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
                            .onTapGesture { syncPillAction?() }
                            .accessibilityHint(
                                syncPillAction != nil
                                    ? "Double-tap to view sync details"
                                    : ""
                            )
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
            LoadedBody(snapshot: snapshot, clockVM: clockVM)
                .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        }
    }
}

// MARK: - Loaded state

private struct LoadedBody: View {
    let snapshot: DashboardSnapshot
    var clockVM: ClockInOutViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                // §3.7 — sticky announcement banner (above KPI grid)
                AnnouncementBannerView()
                greeting
                ClockInOutTile(vm: clockVM)
                heroCard
                secondaryGrid
                attentionCard
                // §3.6 — activity feed with swipe-archive
                ActivityFeedSection()
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
    }

    // greetingText extracted to module-level `dashboardGreeting(for:)` for testability.

    // Hero = the one primary focus. On a repair-shop dashboard that's
    // "open tickets right now". Larger, more visual weight than the rest.
    //
    // §3.2 — subtitle shows "N new today · avg Xh" when avg repair hours are
    // available, otherwise falls back to "N new today · N closed today" so
    // the operator sees throughput at a glance without a second tap.
    private var heroCard: some View {
        let s = snapshot.summary
        let subtitle = heroSubtitle(from: s)
        return HeroMetricCard(
            value: "\(s.openTickets)",
            label: "Open tickets",
            supporting: subtitle
        )
    }

    // Compact stat tiles — muted hierarchy.
    // iPhone: 2-column grid (adaptive minimum 140 pt).
    // iPad (regular-width): fixed 3-column grid per §3 spec.
    private var secondaryGrid: some View {
        let s = snapshot.summary
        let tiles: [StatTile] = [
            .init(label: "Revenue",      value: Self.money(s.revenueToday),   icon: "dollarsign.circle"),
            .init(label: "Closed",       value: "\(s.closedToday)",           icon: "checkmark.seal"),
            .init(label: "Appointments", value: "\(s.appointmentsToday)",     icon: "calendar"),
            .init(label: "Inventory",    value: Self.money(s.inventoryValue), icon: "shippingbox"),
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
        // §3.1 — low-stock uses .error (red) not .warning (amber): running out
        // of parts blocks repairs, making it more urgent than a late invoice.
        let items: [AttentionItem] = [
            .init(label: "Stale tickets",    count: a.staleTickets.count,    accentIsError: false),
            .init(label: "Overdue invoices", count: a.overdueInvoices.count, accentIsError: false),
            .init(label: "Missing parts",    count: a.missingPartsCount,     accentIsError: false),
            .init(label: "Low stock",        count: a.lowStockCount,         accentIsError: true),
        ]
        let total = items.reduce(0) { $0 + $1.count }

        if total > 0 {
            AttentionCard(items: items)
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
}

private struct StatTileCard: View {
    let tile: StatTile

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Image(systemName: tile.icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
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
        .accessibilityValue(tile.value)
    }
}

// MARK: - Attention card

private struct AttentionItem: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
    /// When true the count badge uses `.bizarreError` (red) instead of
    /// `.bizarreWarning` (amber). Used for low-stock: running out of parts
    /// blocks open repairs, warranting the higher-severity color.
    var accentIsError: Bool = false
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

private struct AttentionRow: View {
    let item: AttentionItem

    /// Resolved badge color: error (red) for low-stock, warning (amber) otherwise.
    private var badgeColor: Color {
        guard item.count > 0 else { return .bizarreOnSurfaceMuted }
        return item.accentIsError ? .bizarreError : .bizarreWarning
    }

    var body: some View {
        HStack {
            Text(item.label)
                .font(.brandBodyMedium())
                .foregroundStyle(item.count > 0 ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
            Spacer(minLength: BrandSpacing.sm)
            Text("\(item.count)")
                .font(.brandTitleSmall())
                .foregroundStyle(badgeColor)
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
        .init(label: "Stale tickets",    count: attention.staleTickets.count,    accentIsError: false),
        .init(label: "Overdue invoices", count: attention.overdueInvoices.count, accentIsError: false),
        .init(label: "Missing parts",    count: attention.missingPartsCount,     accentIsError: false),
        // §3.1 — low-stock is error (red): blocking repairs is more urgent than amber.
        .init(label: "Low stock",        count: attention.lowStockCount,         accentIsError: true),
    ]
}

/// View-model for a single row in the Needs Attention card.
struct AttentionItemModel: Equatable {
    let label: String
    let count: Int
    /// When true the badge renders in `.bizarreError` (red) instead of `.bizarreWarning` (amber).
    var accentIsError: Bool = false
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

// MARK: - §3.2 Hero subtitle helper (internal for testability)

/// Builds the hero card supporting subtitle from a `DashboardSummary`.
///
/// When `avgRepairHours` is available it renders "N new today · avg Xh" so
/// the operator sees throughput velocity alongside queue size. Without it the
/// subtitle falls back to "N new today · N closed today" — still useful.
func heroSubtitle(from summary: DashboardSummary) -> String {
    let newPart = "\(summary.ticketsCreatedToday) new today"
    if let avg = summary.avgRepairHours, avg > 0 {
        let hours = String(format: avg < 10 ? "%.1f" : "%.0f", avg)
        return "\(newPart) · avg \(hours)h repair"
    }
    return "\(newPart) · \(summary.closedToday) closed today"
}

// MARK: - §3.7 Announcement banner

/// Sticky glass banner shown above the KPI grid when a new system announcement
/// is available. Copies: headline up to 80 chars, "What's new →" CTA, "Dismiss".
///
/// Persistence: last-seen announcement ID stored in `UserDefaults` under
/// `"dashboard.announcement.lastSeenId"`. The banner hides itself once the
/// user taps Dismiss. Tapping "What's new" would open the full-screen reader
/// (deferred — needs `GET /system/announcements` server endpoint).
private struct AnnouncementBannerView: View {
    // The dismissed-ID key lives in UserDefaults so it survives app restarts.
    private static let lastSeenKey = "dashboard.announcement.lastSeenId"
    // Stub announcement — replaced by server payload once endpoint is live.
    private static let stubId = "announcement-stub-v1"
    private static let stubHeadline = "BizarreCRM 2.0 is here — faster invoicing, smarter reports."

    @State private var isDismissed: Bool = {
        UserDefaults.standard.string(forKey: lastSeenKey) == stubId
    }()

    var body: some View {
        if !isDismissed {
            HStack(alignment: .top, spacing: BrandSpacing.sm) {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(Self.stubHeadline)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(2)
                    // "What's new" CTA — full-screen reader deferred (§3.7 TODO)
                    Text("What's new →")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOrange)
                }

                Spacer(minLength: BrandSpacing.xs)

                Button {
                    withAnimation(BrandMotion.snappy) {
                        UserDefaults.standard.set(Self.stubId, forKey: Self.lastSeenKey)
                        isDismissed = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(BrandSpacing.xs)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Dismiss announcement")
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.bizarreOrange.opacity(0.3), lineWidth: 0.5)
            )
            .accessibilityElement(children: .contain)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - §3.6 Activity feed with swipe-archive

/// Lightweight activity feed section shown below the attention card.
/// Displays the last 5 events (stub data until `GET /activity` is wired into
/// Dashboard). Each row supports trailing swipe-to-archive with haptic.
///
/// Full feed pagination + deep-link taps are deferred (§3.6 TODO).
private struct ActivityFeedSection: View {
    // Stub events — replaced once DashboardSnapshot gains an `activityEvents`
    // field fed by `GET /activity?limit=5`.
    @State private var events: [ActivityFeedEvent] = ActivityFeedEvent.stubs
    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // Collapsible header
            Button {
                withAnimation(BrandMotion.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("Recent activity")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Recent activity, \(isExpanded ? "expanded" : "collapsed")")

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(events) { event in
                        ActivityFeedRow(event: event) {
                            archive(event)
                        }
                        if event.id != events.last?.id {
                            Divider()
                                .overlay(Color.bizarreOutline.opacity(0.2))
                        }
                    }
                }
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
                )
            }
        }
    }

    private func archive(_ event: ActivityFeedEvent) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        withAnimation(BrandMotion.snappy) {
            events.removeAll { $0.id == event.id }
        }
    }
}

private struct ActivityFeedRow: View {
    let event: ActivityFeedEvent
    let onArchive: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: event.icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.summary)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                Text(event.relativeTime)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // §3.6 — trailing swipe-archive with haptic .selection on dismiss
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onArchive) {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(.bizarreOnSurfaceMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.summary)
        .accessibilityValue(event.relativeTime)
        .accessibilityHint("Swipe left to archive")
    }
}

/// View-model for a single activity feed row.
struct ActivityFeedEvent: Identifiable, Sendable {
    let id: String
    let summary: String
    let icon: String
    let relativeTime: String

    // MARK: Stub data (replaced by live server payload in §3.6 full impl)

    static let stubs: [ActivityFeedEvent] = [
        .init(id: "act-1", summary: "Ticket #1042 marked Ready for pickup",  icon: "checkmark.circle",     relativeTime: "2 min ago"),
        .init(id: "act-2", summary: "Invoice #882 paid — $340",              icon: "dollarsign.circle",    relativeTime: "14 min ago"),
        .init(id: "act-3", summary: "New customer: Maria Torres",            icon: "person.badge.plus",    relativeTime: "31 min ago"),
        .init(id: "act-4", summary: "Part 'LCD Display' stock low (2 left)", icon: "exclamationmark.triangle", relativeTime: "1 hr ago"),
        .init(id: "act-5", summary: "SMS sent to James Kim re: Ticket #988", icon: "message",              relativeTime: "2 hr ago"),
    ]
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
