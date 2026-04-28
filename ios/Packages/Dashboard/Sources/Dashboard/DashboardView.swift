import SwiftUI
import Core
import DesignSystem
import Networking
import Sync
import Timeclock
#if canImport(UIKit)
import UIKit
#endif

public struct DashboardView: View {
    @State private var vm: DashboardViewModel
    @State private var clockVM: ClockInOutViewModel

    /// Called when the user taps a KPI tile. The App layer should handle
    /// navigation to the filtered list (e.g. push Tickets with `status_group=open`).
    ///
    /// If `nil`, tile taps do nothing (non-interactive appearance).
    ///
    /// **Wiring note (Discovered §3.1):** `DeepLinkRoute` in Core does not yet
    /// have filtered-list cases; Agent 10 must add `.ticketList(filter:)`,
    /// `.inventoryList(filter:)`, etc. before this callback can use deep-link
    /// routing. The callback interface is stable; App-layer wiring can follow.
    public var onTileTap: (@MainActor (DashboardTileDestination) -> Void)?

    /// §3.1 / §3.14 New-tenant empty state CTA — "Create your first ticket".
    public var onCreateTicket: (() -> Void)?

    /// §3.1 / §3.14 New-tenant empty state CTA — "Import data".
    public var onImportData: (() -> Void)?

    // §3.4 My Queue callbacks
    /// Called when the user taps a ticket in My Queue — should navigate to ticket detail.
    public var onMyQueueTicketTap: ((Int64) -> Void)?
    /// Quick action: Start work on a ticket from My Queue.
    public var onMyQueueStartWork: ((Int64) -> Void)?
    /// Quick action: Mark ready on a ticket from My Queue.
    public var onMyQueueMarkReady: ((Int64) -> Void)?
    /// Quick action: Complete a ticket from My Queue.
    public var onMyQueueComplete: ((Int64) -> Void)?

    // §3.8 Quick-action toolbar callbacks (iPad/Mac toolbar items; no FAB on iPad)
    public var onNewTicket: (() -> Void)?
    public var onNewSale: (() -> Void)?
    public var onNewCustomer: (() -> Void)?
    public var onScanBarcode: (() -> Void)?
    public var onNewSMS: (() -> Void)?

    // §3.9 Tap greeting → Settings → Profile
    public var onTapGreeting: (() -> Void)?

    // §3.9 Avatar — shown in toolbar; long-press → Switch user (§2.5)
    /// URL string for the current user's avatar image. Nil shows initials fallback.
    public var userAvatarURL: String?
    /// Initials shown when no avatar URL is available (e.g. "JD").
    public var userInitials: String?
    /// Long-press on the avatar chip → Switch user (§2.5). Nil disables long-press.
    public var onSwitchUser: (() -> Void)?

    // §3.10 Sync-status tap callback
    public var onTapSyncSettings: (() -> Void)?

    // §3.12 SMS tile tap callback + Team Inbox tap callback
    public var onTapSMSTab: (() -> Void)?
    public var onTapTeamInbox: (() -> Void)?

    // §3.3 Dismiss attention row — server-backed (POST /notifications/:id/dismiss)
    // The notification ID comes from the attention item. Best-effort; local dismiss
    // happens immediately; server call fires async.
    public var onDismissAttentionItem: ((AttentionRowKind) -> Void)?

    @ObservationIgnored private let api: APIClient

    /// - Parameters:
    ///   - repo: Dashboard data repository.
    ///   - api: APIClient for all network calls (timeclock + My Queue included).
    ///   - userIdProvider: Closure that returns the current user's ID for
    ///     timeclock calls. Defaults to `{ 0 }` — a placeholder until
    ///     `GET /auth/me` is wired (TODO post-phase-11).
    ///   - onTileTap: Called when the user taps a KPI tile. Nil = non-interactive.
    ///   - onCreateTicket: Called from the new-tenant empty state CTA. Nil hides button.
    ///   - onImportData: Called from the new-tenant empty state CTA. Nil hides button.
    ///   - onMyQueueTicketTap: Called when the user taps a ticket row in My Queue.
    ///   - onMyQueueStartWork / onMyQueueMarkReady / onMyQueueComplete: Quick-action
    ///     callbacks from My Queue swipe / context menu.
    public init(
        repo: DashboardRepository,
        api: APIClient,
        userIdProvider: (@Sendable () async -> Int64)? = nil,
        onTileTap: (@MainActor (DashboardTileDestination) -> Void)? = nil,
        onCreateTicket: (() -> Void)? = nil,
        onImportData: (() -> Void)? = nil,
        onMyQueueTicketTap: ((Int64) -> Void)? = nil,
        onMyQueueStartWork: ((Int64) -> Void)? = nil,
        onMyQueueMarkReady: ((Int64) -> Void)? = nil,
        onMyQueueComplete: ((Int64) -> Void)? = nil,
        onNewTicket: (() -> Void)? = nil,
        onNewSale: (() -> Void)? = nil,
        onNewCustomer: (() -> Void)? = nil,
        onScanBarcode: (() -> Void)? = nil,
        onNewSMS: (() -> Void)? = nil,
        onTapGreeting: (() -> Void)? = nil,
        onTapSyncSettings: (() -> Void)? = nil,
        onTapSMSTab: (() -> Void)? = nil,
        onTapTeamInbox: (() -> Void)? = nil,
        onDismissAttentionItem: ((AttentionRowKind) -> Void)? = nil,
        userAvatarURL: String? = nil,
        userInitials: String? = nil,
        onSwitchUser: (() -> Void)? = nil
    ) {
        self.api = api
        _vm = State(wrappedValue: DashboardViewModel(repo: repo))
        _clockVM = State(wrappedValue: ClockInOutViewModel(api: api, userIdProvider: userIdProvider))
        self.onTileTap = onTileTap
        self.onCreateTicket = onCreateTicket
        self.onImportData = onImportData
        self.onMyQueueTicketTap = onMyQueueTicketTap
        self.onMyQueueStartWork = onMyQueueStartWork
        self.onMyQueueMarkReady = onMyQueueMarkReady
        self.onMyQueueComplete = onMyQueueComplete
        self.onNewTicket = onNewTicket
        self.onNewSale = onNewSale
        self.onNewCustomer = onNewCustomer
        self.onScanBarcode = onScanBarcode
        self.onNewSMS = onNewSMS
        self.onTapGreeting = onTapGreeting
        self.onTapSyncSettings = onTapSyncSettings
        self.onTapSMSTab = onTapSMSTab
        self.onTapTeamInbox = onTapTeamInbox
        self.onDismissAttentionItem = onDismissAttentionItem
        self.userAvatarURL = userAvatarURL
        self.userInitials = userInitials
        self.onSwitchUser = onSwitchUser
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
                    // §3.10 Sync-status badge (leading)
                    ToolbarItem(placement: .topBarLeading) {
                        SyncStatusBadge(onTapSyncSettings: onTapSyncSettings)
                    }
                    // §3.9 User avatar chip — iPhone: top-left companion to SyncBadge
                    //                       iPad/Mac: top-right of toolbar
                    // Tap → Settings → Profile; long-press → Switch user (§2.5)
                    ToolbarItem(placement: Platform.isCompact ? .topBarLeading : .topBarTrailing) {
                        DashboardUserAvatarChip(
                            avatarURL: userAvatarURL,
                            initials: userInitials,
                            onTap: onTapGreeting,
                            onSwitchUser: onSwitchUser
                        )
                    }
                    // Staleness indicator (trailing)
                    ToolbarItem(placement: .topBarTrailing) {
                        StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
                    }
                    // §3.8 iPad/Mac toolbar group — no FAB on iPad/Mac per CLAUDE.md
                    if !Platform.isCompact {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { onNewTicket?() } label: {
                                Label("New Ticket", systemImage: "plus.circle")
                            }
                            .keyboardShortcut("n", modifiers: .command)
                            .accessibilityLabel("New ticket (⌘N)")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { onNewCustomer?() } label: {
                                Label("New Customer", systemImage: "person.badge.plus")
                            }
                            .keyboardShortcut("n", modifiers: [.command, .shift])
                            .accessibilityLabel("New customer (⌘⇧N)")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { onScanBarcode?() } label: {
                                Label("Scan", systemImage: "barcode.viewfinder")
                            }
                            .keyboardShortcut("s", modifiers: [.command, .shift])
                            .accessibilityLabel("Scan barcode (⌘⇧S)")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { onNewSMS?() } label: {
                                Label("New SMS", systemImage: "message.badge.plus")
                            }
                            .keyboardShortcut("m", modifiers: [.command, .shift])
                            .accessibilityLabel("New SMS (⌘⇧M)")
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            DashboardSkeletonView()
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
            ZStack(alignment: .top) {
                LoadedBody(
                    snapshot: snapshot,
                    clockVM: clockVM,
                    api: api,
                    onTileTap: onTileTap,
                    onCreateTicket: onCreateTicket,
                    onImportData: onImportData,
                    onMyQueueTicketTap: onMyQueueTicketTap,
                    onMyQueueStartWork: onMyQueueStartWork,
                    onMyQueueMarkReady: onMyQueueMarkReady,
                    onMyQueueComplete: onMyQueueComplete,
                    onTapSMSTab: onTapSMSTab,
                    onTapTeamInbox: onTapTeamInbox,
                    onTapGreeting: onTapGreeting,
                    onDismissAttentionItem: onDismissAttentionItem
                )
                // §3.14 — Sticky glass banner when showing cached KPIs after a
                // network failure. Retains last good data so the screen doesn't go blank.
                if vm.loadError != nil {
                    DashboardCachedDataBanner {
                        Task { await vm.forceRefresh() }
                    }
                    .padding(.top, BrandSpacing.sm)
                    .padding(.horizontal, BrandSpacing.base)
                }
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        }
    }
}

// MARK: - Loaded state

private struct LoadedBody: View {
    let snapshot: DashboardSnapshot
    var clockVM: ClockInOutViewModel
    let api: APIClient
    var onTileTap: (@MainActor (DashboardTileDestination) -> Void)?
    var onCreateTicket: (() -> Void)?
    var onImportData: (() -> Void)?
    // §3.4 My Queue callbacks
    var onMyQueueTicketTap: ((Int64) -> Void)?
    var onMyQueueStartWork: ((Int64) -> Void)?
    var onMyQueueMarkReady: ((Int64) -> Void)?
    var onMyQueueComplete: ((Int64) -> Void)?
    // §3.12 SMS tab callback + Team Inbox tab callback
    var onTapSMSTab: (() -> Void)?
    var onTapTeamInbox: (() -> Void)?
    // §3.9 Greeting tap → Settings → Profile
    var onTapGreeting: (() -> Void)?
    // §3.3 Dismiss attention item (server-backed)
    var onDismissAttentionItem: ((AttentionRowKind) -> Void)?

    /// §3.1: 3-column at regular width; 4-column when iPad ≥1100pt or Mac.
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var fourColumnIfWide: [GridItem] {
        // On Mac (Designed for iPad) the full window is often >1100pt.
        // We use GeometryReader in the parent ScrollView for finer control,
        // but here we default to 4 if on a Mac, 3 otherwise.
        // Live column adaptation via GeometryReader is done in DashboardKpiTileGrid (iPad target).
        #if targetEnvironment(macCatalyst)
        return Array(repeating: GridItem(.flexible(), spacing: BrandSpacing.md), count: 4)
        #else
        return Array(repeating: GridItem(.flexible(), spacing: BrandSpacing.md), count: 3)
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                // §3.7 Announcements banner — above everything
                AnnouncementsBanner(api: api)

                greeting
                ClockInOutTile(vm: clockVM)

                // §3.12 Unread-SMS tile + Team Inbox tile (shown when tenant has inbox)
                UnreadSMSTile(api: api, onTapSMSTab: onTapSMSTab, onTapTeamInbox: onTapTeamInbox)

                // §3.1 / §3.14 — New-tenant empty state replaces KPI grid
                // when the shop has never had any activity.
                if isNewTenantSnapshot(snapshot) {
                    DashboardNewTenantEmptyState(
                        onCreateTicket: onCreateTicket,
                        onImportData: onImportData
                    )
                } else {
                    heroCard
                    secondaryGrid
                }

                attentionCard

                // §3.4 My Queue — always visible; auto-refreshes every 30s.
                // Shown below the attention card so the most urgent info leads.
                MyQueueView(
                    api: api,
                    onTicketTap: onMyQueueTicketTap,
                    onStartWork: onMyQueueStartWork,
                    onMarkReady: onMyQueueMarkReady,
                    onComplete: onMyQueueComplete
                )
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
    ///
    /// Tap navigates to Settings → Profile (§3.9). If `onTapGreeting` is nil
    /// the greeting is still displayed but non-interactive.
    private var greeting: some View {
        Group {
            if let onTapGreeting {
                Button {
                    onTapGreeting()
                } label: {
                    Text(dashboardGreeting(for: Date()))
                        .font(.brandTitleLarge())
                        .foregroundStyle(.bizarreOnSurface)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dashboardGreeting(for: Date()) + ". Tap to open Profile settings.")
                .accessibilityHint("Opens your profile settings.")
            } else {
                Text(dashboardGreeting(for: Date()))
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    // greetingText extracted to module-level `dashboardGreeting(for:)` for testability.

    // Hero = the one primary focus. On a repair-shop dashboard that's
    // "open tickets right now". Larger, more visual weight than the rest.
    // §3.1: tap → Tickets filtered to open status.
    private var heroCard: some View {
        let s = snapshot.summary
        return HeroMetricCard(
            value: "\(s.openTickets)",
            label: "Open tickets",
            supporting: "\(s.ticketsCreatedToday) new today",
            deepLink: "bizarrecrm://tickets?status_group=open"
        )
    }

    // Compact stat tiles — muted hierarchy.
    // iPhone: 2-column grid (adaptive minimum 140 pt).
    // iPad (regular-width): fixed 3-column grid per §3 spec.
    // §3.1: each tile deep-links to the filtered list via bizarrecrm:// scheme.
    private var secondaryGrid: some View {
        let s = snapshot.summary
        let tiles: [StatTile] = [
            .init(label: "Revenue",      value: Self.money(s.revenueToday),   icon: "dollarsign.circle",
                  deepLink: "bizarrecrm://reports/revenue"),
            .init(label: "Closed",       value: "\(s.closedToday)",           icon: "checkmark.seal",
                  deepLink: "bizarrecrm://tickets?status_group=closed"),
            .init(label: "Appointments", value: "\(s.appointmentsToday)",     icon: "calendar",
                  deepLink: "bizarrecrm://appointments?date=today"),
            .init(label: "Inventory",    value: Self.money(s.inventoryValue), icon: "shippingbox",
                  deepLink: "bizarrecrm://inventory"),
        ]

        // §3.1 column spec:
        //   iPhone: 2-column adaptive (minimum 140 pt)
        //   iPad ≥768 pt: 3 columns; iPad/Mac ≥1100 pt: 4 columns, max 1200 pt content width
        let columns: [GridItem] = Platform.isCompact
            ? [
                GridItem(.adaptive(minimum: 140), spacing: BrandSpacing.md),
                GridItem(.adaptive(minimum: 140), spacing: BrandSpacing.md),
              ]
            : fourColumnIfWide

        return LazyVGrid(columns: columns, spacing: BrandSpacing.md) {
            ForEach(tiles) { tile in
                StatTileCard(
                    tile: tile,
                    onTap: tile.destination.flatMap { dest -> (@MainActor () -> Void)? in
                        guard let handler = onTileTap else { return nil }
                        return { @MainActor in handler(dest) }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var attentionCard: some View {
        let a = snapshot.attention
        let total = a.staleTickets.count + a.overdueInvoices.count + a.missingPartsCount + a.lowStockCount

        if total > 0 {
            // §3.3 — row-level chips for stale tickets and overdue invoices.
            // Forward "View ticket" taps to the dashboard's host (set by
            // RootView/iPadShell) so the rail can switch to the Tickets list.
            // `onViewInvoice` is left nil so `NeedsAttentionCard` falls back
            // to its `openURL("bizarrecrm://invoices/<id>")` path — replacing
            // it with a no-op silently broke a feature that previously worked
            // via the deep-link router.
            NeedsAttentionCard(
                attention: a,
                onViewTicket: onMyQueueTicketTap.map { handler in { id in handler(id) } },
                onViewInvoice: nil
            )
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
    var deepLink: String? = nil

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let link = deepLink, let url = URL(string: link) {
                BrandHaptics.selection()
                openURL(url)
            }
        } label: {
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
        }
        .buttonStyle(.plain)
        #if canImport(UIKit)
        .hoverEffect(.highlight)
        #endif
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value). \(supporting).")
        .accessibilityAddTraits(deepLink != nil ? [.isHeader, .isButton] : .isHeader)
        .accessibilityHint(deepLink != nil ? "Double tap to view open tickets" : "")
    }
}

// MARK: - Stat tile

private struct StatTile: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let icon: String
    /// Custom scheme deep-link URL (bizarrecrm://…) — nil = no deep link.
    let deepLinkURL: URL?

    let destination: DashboardTileDestination?

    init(label: String, value: String, icon: String, deepLink: String? = nil, destination: DashboardTileDestination? = nil) {
        self.label = label
        self.value = value
        self.icon = icon
        self.deepLinkURL = deepLink.flatMap { URL(string: $0) }
        self.destination = destination
    }
}

private struct StatTileCard: View {
    let tile: StatTile
    var onTap: (@MainActor () -> Void)? = nil
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            if let onTap {
                onTap()
            } else if let url = tile.deepLinkURL {
                BrandHaptics.selection()
                openURL(url)
            }
        } label: {
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
        }
        .buttonStyle(.plain)
        #if canImport(UIKit)
        .hoverEffect(.highlight)
        #endif
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.label)
        .accessibilityValue(tile.value)
        .accessibilityHint(tile.deepLinkURL != nil ? "Double tap to open" : "")
        .accessibilityAddTraits(tile.deepLinkURL != nil ? .isButton : [])
    }
}

// MARK: - Attention card (§3.3 — row-level chips, swipe, context menu, dismiss)

/// Attention item kinds shown in the Needs Attention card.
public enum AttentionRowKind: Sendable {
    case staleTicket(NeedsAttention.StaleTicket)
    case overdueInvoice(NeedsAttention.OverdueInvoice)
    case aggregateMissingParts(Int)
    case aggregateLowStock(Int)

    var displayId: String {
        switch self {
        case .staleTicket(let t):      return "#\(t.orderId)"
        case .overdueInvoice(let i):   return "#\(i.orderId ?? "\(i.id)")"
        case .aggregateMissingParts:   return "missing-parts"
        case .aggregateLowStock:       return "low-stock"
        }
    }

    var customerName: String? {
        switch self {
        case .staleTicket(let t):     return t.customerName
        case .overdueInvoice(let i):  return i.customerName
        default:                      return nil
        }
    }

    var label: String {
        switch self {
        case .staleTicket(let t):
            return "Stale ticket \(t.orderId)" + (t.customerName.map { " — \($0)" } ?? "")
        case .overdueInvoice(let i):
            let id = i.orderId ?? "\(i.id)"
            return "Overdue invoice \(id)" + (i.customerName.map { " — \($0)" } ?? "")
        case .aggregateMissingParts(let n):
            return "\(n) missing part\(n == 1 ? "" : "s")"
        case .aggregateLowStock(let n):
            return "\(n) low-stock item\(n == 1 ? "" : "s")"
        }
    }
}

private struct AttentionCard: View {
    let attention: NeedsAttention
    var onViewTicket: ((Int64) -> Void)?
    var onViewInvoice: ((Int64) -> Void)?
    var onSMSCustomer: ((String?) -> Void)?
    var onMarkResolved: ((AttentionRowKind) -> Void)?
    var onSnooze: ((AttentionRowKind, SnoozeDuration) -> Void)?
    var onDismiss: ((AttentionRowKind) -> Void)?

    @State private var dismissedIds: Set<String> = []

    private var rows: [AttentionRowKind] {
        var result: [AttentionRowKind] = []
        result += attention.staleTickets.map { .staleTicket($0) }
        result += attention.overdueInvoices.map { .overdueInvoice($0) }
        if attention.missingPartsCount > 0 {
            result.append(.aggregateMissingParts(attention.missingPartsCount))
        }
        if attention.lowStockCount > 0 {
            result.append(.aggregateLowStock(attention.lowStockCount))
        }
        return result.filter { !dismissedIds.contains($0.displayId) }
    }

    var body: some View {
        if rows.isEmpty { return AnyView(EmptyView()) }
        return AnyView(
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
                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                        AttentionRow(
                            kind: row,
                            onViewTicket: onViewTicket,
                            onViewInvoice: onViewInvoice,
                            onSMSCustomer: onSMSCustomer,
                            onMarkResolved: onMarkResolved,
                            onSnooze: onSnooze,
                            onDismiss: { kind in
                                withAnimation { dismissedIds.insert(kind.displayId) }
                                onDismiss?(kind)
                            }
                        )
                        if idx < rows.count - 1 {
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
        )
    }
}

/// Snooze duration options for the attention row.
enum SnoozeDuration: String, CaseIterable, Sendable {
    case fourHours = "4 hours"
    case tomorrow  = "Tomorrow"
    case nextWeek  = "Next week"

    var seconds: TimeInterval {
        switch self {
        case .fourHours: return 4 * 3600
        case .tomorrow:  return 24 * 3600
        case .nextWeek:  return 7 * 24 * 3600
        }
    }
}

private struct AttentionRow: View {
    let kind: AttentionRowKind
    var onViewTicket: ((Int64) -> Void)?
    var onViewInvoice: ((Int64) -> Void)?
    var onSMSCustomer: ((String?) -> Void)?
    var onMarkResolved: ((AttentionRowKind) -> Void)?
    var onSnooze: ((AttentionRowKind, SnoozeDuration) -> Void)?
    var onDismiss: ((AttentionRowKind) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            // Row label
            HStack {
                Text(kind.label)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(2)
                Spacer(minLength: BrandSpacing.sm)
            }

            // §3.3 Row-level chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.xs) {
                    if case .staleTicket(let t) = kind {
                        AttentionChip(label: "View ticket", icon: "ticket") {
                            onViewTicket?(t.id)
                        }
                    }
                    if case .overdueInvoice(let i) = kind {
                        AttentionChip(label: "View invoice", icon: "doc.text") {
                            onViewInvoice?(i.id)
                        }
                    }
                    if kind.customerName != nil {
                        AttentionChip(label: "SMS customer", icon: "message") {
                            onSMSCustomer?(kind.customerName)
                        }
                    }
                    AttentionChip(label: "Mark resolved", icon: "checkmark.circle") {
                        onMarkResolved?(kind)
                    }
                    Menu {
                        ForEach(SnoozeDuration.allCases, id: \.rawValue) { dur in
                            Button(dur.rawValue) { onSnooze?(kind, dur) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 11))
                            Text("Snooze")
                                .font(.brandLabelSmall())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.bizarreSurface2, in: Capsule())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .accessibilityLabel("Snooze")
                }
            }
        }
        .padding(.vertical, BrandSpacing.sm)
        .contentShape(Rectangle())
        // §3.3 Swipe actions (iPhone): leading = snooze, trailing = dismiss
        .swipeActions(edge: .leading) {
            Menu {
                ForEach(SnoozeDuration.allCases, id: \.rawValue) { dur in
                    Button(dur.rawValue) { onSnooze?(kind, dur) }
                }
            } label: {
                Label("Snooze", systemImage: "clock.arrow.circlepath")
            }
            .tint(.bizarreWarning)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                #if canImport(UIKit)
                let gen = UISelectionFeedbackGenerator()
                gen.selectionChanged()
                #endif
                onDismiss?(kind)
            } label: {
                Label("Dismiss", systemImage: "xmark.circle")
            }
            .tint(.bizarreError)
        }
        // §3.3 Context menu (iPad/Mac)
        .contextMenu {
            if case .staleTicket(let t) = kind {
                Button {
                    onViewTicket?(t.id)
                } label: {
                    Label("View ticket", systemImage: "ticket")
                }
            }
            if case .overdueInvoice(let i) = kind {
                Button {
                    onViewInvoice?(i.id)
                } label: {
                    Label("View invoice", systemImage: "doc.text")
                }
            }
            if kind.customerName != nil {
                Button {
                    onSMSCustomer?(kind.customerName)
                } label: {
                    Label("SMS customer", systemImage: "message")
                }
            }
            Button {
                onMarkResolved?(kind)
            } label: {
                Label("Mark resolved", systemImage: "checkmark.circle")
            }
            Menu("Snooze") {
                ForEach(SnoozeDuration.allCases, id: \.rawValue) { dur in
                    Button(dur.rawValue) { onSnooze?(kind, dur) }
                }
            }
            Divider()
            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = kind.displayId
                #endif
            } label: {
                Label("Copy ID", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                onDismiss?(kind)
            } label: {
                Label("Dismiss", systemImage: "xmark.circle")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.label)
    }
}

// MARK: - Attention chip

private struct AttentionChip: View {
    let label: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.brandLabelSmall())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.bizarreSurface2, in: Capsule())
            .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Aggregate stat attention item (for the attentionCard helper functions below)

private struct AttentionItem: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
}

// MARK: - Attention all-clear

/// §3.3 — Shown in the Needs Attention section when there are no urgent items.
/// Plain surface, no glass on content.
private struct AttentionAllClearView: View {
    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("All clear")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Nothing needs your attention right now.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("All clear. Nothing needs your attention right now.")
    }
}

// MARK: - Layout helpers (internal for testability)

/// Returns the number of KPI grid columns for the given compactness flag.
/// - compact (iPhone): 2-column adaptive (minimum 140 pt).
/// - regular (iPad ≥768 pt): 3 fixed columns; 4 on Mac.
/// - Mac Catalyst: 4 columns.
func kpiGridColumnCount(isCompact: Bool, isMac: Bool = false) -> Int {
    if isCompact { return 2 }
    return isMac ? 4 : 3
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

// MARK: - §3.14 Cached-data sticky banner

/// Shown as a floating glass banner at the top of the loaded dashboard when
/// the latest network refresh failed but cached KPIs are still visible.
struct DashboardCachedDataBanner: View {
    let onRetry: () -> Void
    @State private var isDismissed = false

    var body: some View {
        if !isDismissed {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.bizarreWarning)
                    .accessibilityHidden(true)
                Text("Showing cached data.")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer(minLength: 0)
                Button("Retry") { onRetry() }
                    .font(.brandLabelLarge().weight(.semibold))
                    .foregroundStyle(.bizarreOrange)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { isDismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss cached-data notice")
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .background(
                Color.bizarreSurface1.opacity(0.92),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.bizarreWarning.opacity(0.35), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Showing cached data. Retry or dismiss.")
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - §3.9 User avatar chip (toolbar)

/// Small circular avatar in the navigation toolbar.
/// - iPhone: appears in `topBarLeading` next to the sync badge.
/// - iPad/Mac: appears in `topBarTrailing`.
/// Tap → Settings → Profile (via `onTap`).
/// Long-press → Switch user sheet (§2.5, via `onSwitchUser`).
struct DashboardUserAvatarChip: View {
    let avatarURL: String?
    let initials: String?
    var onTap: (() -> Void)?
    var onSwitchUser: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            avatarContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your profile. Tap to open settings.")
        .accessibilityHint(onSwitchUser != nil ? "Long-press to switch user." : "")
        .contextMenu {
            if let onTapProfile = onTap {
                Button {
                    onTapProfile()
                } label: {
                    Label("My Profile", systemImage: "person.crop.circle")
                }
            }
            if let onSwitchUser {
                Button {
                    onSwitchUser()
                } label: {
                    Label("Switch User", systemImage: "arrow.left.arrow.right.circle")
                }
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                onSwitchUser?()
            }
        )
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let urlStr = avatarURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
                case .failure, .empty:
                    initialsView
                @unknown default:
                    initialsView
                }
            }
        } else {
            initialsView
        }
    }

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(Color.bizarreOrange.opacity(0.18))
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(Color.bizarreOrange.opacity(0.35), lineWidth: 0.5))
            Text(initials ?? "?")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.bizarreOrange)
        }
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
