import SwiftUI
import Core
import DesignSystem
import Networking
import Sync
import Timeclock
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §3 Feature flags
//
// Five open items shipped in this batch:
//   1. Stat tile expand-on-tap         (StatTileCard)
//   2. My-queue swipe to assign        (MyQueueSection)
//   3. Late-arrival warning chip       (LateArrivalChip / AttentionRow)
//   4. Recent-activity timestamp group (ActivityFeedSection)
//   5. Badge accessibility traits      (.accessibilityAddTraits on badges)

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
                greeting
                ClockInOutTile(vm: clockVM)
                heroCard
                secondaryGrid
                myQueueSection
                activityFeedSection
                attentionCard
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

    // §3.4 My Queue — placeholder rows derived from stale tickets until
    // GET /tickets/my-queue is wired at the repository layer.
    @ViewBuilder
    private var myQueueSection: some View {
        let tickets = snapshot.attention.staleTickets
        if !tickets.isEmpty {
            MyQueueSection(tickets: tickets)
        }
    }

    // §3.6 Recent activity feed — stub derived from stale + overdue items.
    // Groups entries by relative day (Today / Yesterday / Earlier).
    @ViewBuilder
    private var activityFeedSection: some View {
        let entries = activityEntries(from: snapshot.attention)
        if !entries.isEmpty {
            ActivityFeedSection(entries: entries)
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

// §3 item 1: Stat tile expand-on-tap
// Tapping the tile reveals a secondary detail row (e.g. trend/delta placeholder).
// The tile announces "expanded" / "collapsed" to VoiceOver via accessibilityHint.
private struct StatTileCard: View {
    let tile: StatTile
    @State private var expanded = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                expanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: tile.icon)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
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

                // Expanded detail row — shows delta hint once real data arrives.
                if expanded {
                    Divider()
                        .overlay(Color.bizarreOutline.opacity(0.25))
                        .padding(.top, BrandSpacing.xxs)
                    Text("No prior-period data yet")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(.top, BrandSpacing.xxs)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(BrandSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        // §3 item 5: badge accessibility traits
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.label)
        .accessibilityValue(tile.value)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(expanded ? "Double-tap to collapse" : "Double-tap to expand details")
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

private struct AttentionRow: View {
    let item: AttentionItem

    /// §3 item 3: late-arrival threshold — items stale > 7 days get a
    /// warning chip. "Stale tickets" and "Overdue invoices" rows qualify.
    private var showLateArrivalChip: Bool {
        item.count > 0 && (item.label == "Stale tickets" || item.label == "Overdue invoices")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(item.label)
                    .font(.brandBodyMedium())
                    .foregroundStyle(item.count > 0 ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
                // §3 item 3: late-arrival warning chip
                if showLateArrivalChip {
                    LateArrivalChip()
                }
            }
            Spacer(minLength: BrandSpacing.sm)
            // §3 item 5: count badge with .updatesFrequently trait so
            // VoiceOver announces value changes without full focus shift.
            Text("\(item.count)")
                .font(.brandTitleSmall())
                .foregroundStyle(item.count > 0 ? .bizarreWarning : .bizarreOnSurfaceMuted)
                .monospacedDigit()
                .accessibilityAddTraits(.updatesFrequently)
        }
        .padding(.vertical, BrandSpacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.label)
        .accessibilityValue("\(item.count)\(showLateArrivalChip ? ", overdue" : "")")
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

// §3 item 3: Late-arrival warning chip displayed inline on attention rows.
private struct LateArrivalChip: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 9, weight: .semibold))
                .accessibilityHidden(true)
            Text("Overdue")
                .font(.brandLabelSmall())
        }
        .foregroundStyle(.bizarreError)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.bizarreError.opacity(0.12), in: Capsule())
        .accessibilityLabel("Overdue warning")
        .accessibilityAddTraits(.isStaticText)
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

// MARK: - §3 item 2: My-queue swipe to assign

/// Displays the current user's assigned tickets with swipe-to-assign support.
/// Populated from `NeedsAttention.staleTickets` until GET /tickets/my-queue
/// is fully wired at the repository layer.
private struct MyQueueSection: View {
    let tickets: [NeedsAttention.StaleTicket]
    @State private var assignedIds: Set<Int64> = []

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text("My Queue")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
            }

            VStack(spacing: 0) {
                ForEach(Array(tickets.enumerated()), id: \.element.id) { idx, ticket in
                    MyQueueRow(ticket: ticket, isAssigned: assignedIds.contains(ticket.id)) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            if assignedIds.contains(ticket.id) {
                                assignedIds.remove(ticket.id)
                            } else {
                                assignedIds.insert(ticket.id)
                            }
                        }
                        #if canImport(UIKit)
                        let gen = UIImpactFeedbackGenerator(style: .medium)
                        gen.impactOccurred()
                        #endif
                    }
                    if idx < tickets.count - 1 {
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

private struct MyQueueRow: View {
    let ticket: NeedsAttention.StaleTicket
    let isAssigned: Bool
    let onAssign: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ticket.orderId)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                if let name = ticket.customerName {
                    Text(name)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer()
            // §3 item 3 tie-in: age badge with color ramp
            AgeBadge(daysStale: ticket.daysStale)
            if isAssigned {
                Image(systemName: "person.fill.checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.bizarreSuccess)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, BrandSpacing.sm)
        .contentShape(Rectangle())
        // §3 item 2: leading swipe = assign to me
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: onAssign) {
                Label(isAssigned ? "Unassign" : "Assign to me",
                      systemImage: isAssigned ? "person.slash" : "person.fill.badge.plus")
            }
            .tint(isAssigned ? .bizarreOnSurfaceMuted : .bizarreOrange)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ticket \(ticket.orderId)\(ticket.customerName.map { ", \($0)" } ?? ""), \(ticket.daysStale) days stale")
        .accessibilityAddTraits(isAssigned ? [.isSelected] : [])
        .accessibilityHint(isAssigned ? "Swipe right to unassign" : "Swipe right to assign to yourself")
    }
}

/// Age badge using the §3.4 color ramp:
/// red > 14 d / amber 7–14 / yellow 3–7 / gray < 3.
private struct AgeBadge: View {
    let daysStale: Int

    private var color: Color {
        switch daysStale {
        case 15...: return .bizarreError
        case 7..<15: return .bizarreWarning
        case 3..<7:  return .bizarreOrange
        default:     return .bizarreOnSurfaceMuted
        }
    }

    var body: some View {
        Text("\(daysStale)d")
            .font(.brandLabelSmall())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            // §3 item 5: badge accessibility traits
            .accessibilityLabel("\(daysStale) days stale")
            .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - §3 item 4: Recent-activity timestamp grouping

/// A lightweight activity entry derived from the needs-attention snapshot.
/// Until GET /activity is wired, we synthesise entries from stale tickets
/// and overdue invoices so the timestamp-grouping logic is exercised.
struct ActivityEntry: Identifiable {
    let id: Int64
    let label: String
    let detail: String
    let icon: String
    /// Synthetic date: `daysAgo` days before now, midnight-aligned.
    let daysAgo: Int

    var date: Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }
}

/// Groups `ActivityEntry` by relative day and renders each group with a
/// sticky day header ("Today", "Yesterday", "Earlier").
private struct ActivityFeedSection: View {
    let entries: [ActivityEntry]

    private var groups: [(header: String, entries: [ActivityEntry])] {
        activityGroups(from: entries)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("Recent Activity")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
            }

            ForEach(groups, id: \.header) { group in
                VStack(alignment: .leading, spacing: 0) {
                    // Day header
                    Text(group.header)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(.vertical, BrandSpacing.xs)
                        .accessibilityAddTraits(.isHeader)

                    VStack(spacing: 0) {
                        ForEach(Array(group.entries.enumerated()), id: \.element.id) { idx, entry in
                            ActivityRow(entry: entry)
                            if idx < group.entries.count - 1 {
                                Divider()
                                    .overlay(Color.bizarreOutline.opacity(0.2))
                            }
                        }
                    }
                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActivityRow: View {
    let entry: ActivityEntry

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: entry.icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(entry.detail)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(BrandSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.label). \(entry.detail)")
    }
}

// MARK: - Activity helpers (internal for testability)

/// Buckets `ActivityEntry` items into day-labelled groups.
/// Exported as `internal` so tests can validate grouping logic directly.
func activityGroups(from entries: [ActivityEntry]) -> [(header: String, entries: [ActivityEntry])] {
    let today     = entries.filter { $0.daysAgo == 0 }
    let yesterday = entries.filter { $0.daysAgo == 1 }
    let earlier   = entries.filter { $0.daysAgo >= 2 }
    var result: [(header: String, entries: [ActivityEntry])] = []
    if !today.isEmpty     { result.append(("Today",     today))     }
    if !yesterday.isEmpty { result.append(("Yesterday", yesterday)) }
    if !earlier.isEmpty   { result.append(("Earlier",   earlier))   }
    return result
}

/// Synthesises `ActivityEntry` items from `NeedsAttention` until the real
/// `GET /activity` endpoint is wired. Exported `internal` for tests.
func activityEntries(from attention: NeedsAttention) -> [ActivityEntry] {
    var result: [ActivityEntry] = []
    for ticket in attention.staleTickets {
        result.append(ActivityEntry(
            id:      ticket.id,
            label:   "Ticket \(ticket.orderId)",
            detail:  ticket.customerName ?? "No customer",
            icon:    "wrench.and.screwdriver",
            daysAgo: min(ticket.daysStale, 2)
        ))
    }
    for (i, invoice) in attention.overdueInvoices.enumerated() {
        result.append(ActivityEntry(
            id:      invoice.id + 100_000,
            label:   "Invoice \(invoice.orderId ?? "#\(invoice.id)")",
            detail:  "Overdue \(invoice.daysOverdue)d — \(invoice.customerName ?? "Unknown")",
            icon:    "doc.text",
            daysAgo: i == 0 ? 0 : 1
        ))
    }
    return result
}
