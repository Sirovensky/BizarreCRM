import SwiftUI
import DesignSystem
import Networking

// MARK: - Hex colour helper (file-private)

private extension Color {
    /// Initialise from a 6-digit or 3-digit CSS hex string, with or without `#`.
    /// Returns `nil` when the string is malformed.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        guard s.count == 6 || s.count == 3 else { return nil }
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard let value = UInt64(s, radix: 16) else { return nil }
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >>  8) / 255.0
        let b = Double( value & 0x0000FF       ) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - MembershipListViewModel

@MainActor
@Observable
public final class MembershipListViewModel {

    public enum State: Equatable, Sendable {
        case loading
        case loaded
        case comingSoon
        case failed(String)
    }

    public private(set) var state: State = .loading
    public private(set) var memberships: [Membership] = []
    public private(set) var plans: [MembershipPlan] = []
    /// Keyed by Membership.id — preserves rich admin data (tierName, color, customer name).
    public private(set) var adminSubsByMembershipId: [String: AdminSubscriptionDTO] = [:]

    private let manager: MembershipSubscriptionManager
    private let api: any APIClient

    public init(api: any APIClient, manager: MembershipSubscriptionManager) {
        self.api = api
        self.manager = manager
    }

    public func load() async {
        state = .loading
        do {
            // Server route: GET /api/v1/membership/subscriptions (admin)
            let adminSubs = try await api.listAllSubscriptions()
            // Map AdminSubscriptionDTO → domain Membership
            let domain: [Membership] = adminSubs.map { sub in
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
                let startDate = isoFormatter.date(from: sub.currentPeriodStart) ?? Date()
                let endDate = isoFormatter.date(from: sub.currentPeriodEnd)
                return Membership(
                    id: String(sub.id),
                    customerId: String(sub.customerId),
                    planId: String(sub.tierId),
                    status: MembershipStatus(rawValue: sub.status) ?? .active,
                    startDate: startDate,
                    endDate: endDate,
                    autoRenew: true,
                    nextBillingAt: endDate
                )
            }
            await manager.hydrate(memberships: domain)
            memberships = await manager.activeMemberships
            // Build lookup so the row can display tier name + badge colour.
            adminSubsByMembershipId = Dictionary(
                uniqueKeysWithValues: adminSubs.map { (String($0.id), $0) }
            )
            state = .loaded
        } catch let t as APITransportError {
            if case .httpStatus(let c, _) = t, c == 404 || c == 501 {
                state = .comingSoon
            } else {
                state = .failed(t.localizedDescription)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func refresh() async { await load() }

    public func cancel(id: String) async {
        _ = await manager.cancel(membershipId: id)
        memberships = await manager.activeMemberships
    }

    public func pause(id: String) async {
        _ = await manager.pause(membershipId: id)
        memberships = await manager.activeMemberships
    }

    public func resume(id: String) async {
        _ = await manager.resume(membershipId: id)
        memberships = await manager.activeMemberships
    }
}

// MARK: - MembershipListView

/// §38 — Admin view showing all active memberships.
///
/// iPhone: `List` with swipe actions for cancel/pause/resume.
/// iPad: `Table` with sortable columns + `.contextMenu` per row.
public struct MembershipListView: View {

    @State private var vm: MembershipListViewModel
    @State private var searchText: String = ""
    @Environment(\.horizontalSizeClass) private var hSizeClass

    public init(api: any APIClient, manager: MembershipSubscriptionManager) {
        _vm = State(wrappedValue: MembershipListViewModel(api: api, manager: manager))
    }

    private var filtered: [Membership] {
        guard !searchText.isEmpty else { return vm.memberships }
        return vm.memberships.filter {
            $0.customerId.localizedCaseInsensitiveContains(searchText)
            || $0.planId.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        Group {
            switch vm.state {
            case .loading:
                ProgressView("Loading memberships…")
                    .accessibilityLabel("Loading memberships")
            case .comingSoon:
                comingSoonView
            case .failed(let msg):
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(msg)
                )
            case .loaded:
                if vm.memberships.isEmpty {
                    ContentUnavailableView(
                        "No Memberships",
                        systemImage: "person.crop.circle.badge.xmark",
                        description: Text("No active memberships found.")
                    )
                } else if hSizeClass == .regular {
                    iPadTable
                } else {
                    iPhoneList
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search by customer or plan")
        .navigationTitle("Memberships")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await vm.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh memberships")
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.refresh() }
    }

    // MARK: - iPhone list

    private var iPhoneList: some View {
        List(filtered) { membership in
            MembershipRow(
                membership: membership,
                adminSub: vm.adminSubsByMembershipId[membership.id]
            )
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                swipeTrailing(membership)
            }
            .contextMenu { contextMenuItems(membership) }
            .accessibilityElement(children: .combine)
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    // MARK: - iPad table

    @ViewBuilder
    private var iPadTable: some View {
        Table(filtered) {
            TableColumn("Customer") { m in
                let sub = vm.adminSubsByMembershipId[m.id]
                let name = [sub?.firstName, sub?.lastName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(name.isEmpty ? "ID \(m.customerId)" : name)
                        .font(.brandBodyMedium())
                        .textSelection(.enabled)
                    if !name.isEmpty {
                        Text("ID \(m.customerId)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .textSelection(.enabled)
                    }
                }
            }
            TableColumn("Tier") { m in
                TierBadge(
                    tierName: vm.adminSubsByMembershipId[m.id]?.tierName,
                    colorHex: vm.adminSubsByMembershipId[m.id]?.color
                )
            }
            TableColumn("Status") { m in
                StatusChip(status: m.status)
            }
            TableColumn("Start Date") { m in
                Text(m.startDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.brandLabelSmall())
            }
            TableColumn("Renews") { m in
                if let next = m.nextBillingAt {
                    Text(next.formatted(date: .abbreviated, time: .omitted))
                        .font(.brandLabelSmall())
                } else {
                    Text("—").foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .contextMenu(forSelectionType: Membership.ID.self) { ids in
            if let id = ids.first {
                contextMenuItems(forId: id)
            }
        }
    }

    // MARK: - Context menu + swipe actions

    @ViewBuilder
    private func swipeTrailing(_ membership: Membership) -> some View {
        switch membership.status {
        case .active:
            Button(role: .destructive) { Task { await vm.cancel(id: membership.id) } } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }
            Button { Task { await vm.pause(id: membership.id) } } label: {
                Label("Pause", systemImage: "pause.circle")
            }
            .tint(.bizarreWarning)
        case .paused:
            Button { Task { await vm.resume(id: membership.id) } } label: {
                Label("Resume", systemImage: "play.circle")
            }
            .tint(.bizarreSuccess)
            Button(role: .destructive) { Task { await vm.cancel(id: membership.id) } } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func contextMenuItems(_ membership: Membership) -> some View {
        contextMenuItems(forId: membership.id)
    }

    @ViewBuilder
    private func contextMenuItems(forId id: String) -> some View {
        if let m = vm.memberships.first(where: { $0.id == id }) {
            if m.status == .active {
                Button { Task { await vm.pause(id: id) } } label: {
                    Label("Pause", systemImage: "pause.circle")
                }
            }
            if m.status == .paused {
                Button { Task { await vm.resume(id: id) } } label: {
                    Label("Resume", systemImage: "play.circle")
                }
            }
            Divider()
            Button(role: .destructive) { Task { await vm.cancel(id: id) } } label: {
                Label("Cancel Membership", systemImage: "xmark.circle")
            }
        }
    }

    // MARK: - Coming soon

    private var comingSoonView: some View {
        ContentUnavailableView(
            "Memberships Coming Soon",
            systemImage: "clock.badge",
            description: Text("Membership subscriptions will be available once the server endpoint is enabled.")
        )
    }
}

// MARK: - MembershipRow

private struct MembershipRow: View {
    let membership: Membership
    let adminSub: AdminSubscriptionDTO?

    private var customerDisplayName: String {
        let parts = [adminSub?.firstName, adminSub?.lastName].compactMap { $0 }
        return parts.isEmpty ? "Customer \(membership.customerId)" : parts.joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(customerDisplayName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                TierBadge(
                    tierName: adminSub?.tierName,
                    colorHex: adminSub?.color
                )
                if let next = membership.nextBillingAt {
                    Text("Renews \(next.formatted(date: .abbreviated, time: .omitted))")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer()
            StatusChip(status: membership.status)
        }
        .padding(.vertical, BrandSpacing.xxs)
    }
}

// MARK: - TierBadge

/// Displays a coloured pill for a membership tier.
///
/// Falls back to a neutral "Member" label when no tier name is available.
/// The colour is decoded from the server's hex string; falls back to
/// `.bizarreOnSurfaceMuted` on parse failure.
private struct TierBadge: View {
    let tierName: String?
    let colorHex: String?

    private var label: String { tierName ?? "Member" }

    private var badgeColor: Color {
        // Try to parse the server hex string first.
        if let hex = colorHex, let c = Color(hex: hex) { return c }
        // Fall back to the typed tier colour when the name matches.
        if let name = tierName {
            return LoyaltyTier.parse(name).displayColor
        }
        return .bizarreOnSurfaceMuted
    }

    var body: some View {
        HStack(spacing: BrandSpacing.xxs) {
            if let name = tierName {
                Image(systemName: LoyaltyTier.parse(name).systemSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(badgeColor)
                    .accessibilityHidden(true)
            }
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(badgeColor)
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .background(Capsule().fill(badgeColor.opacity(0.12)))
        .accessibilityLabel("Tier: \(label)")
    }
}

// MARK: - StatusChip

private struct StatusChip: View {
    let status: MembershipStatus

    private var color: Color {
        switch status {
        case .active:       return .bizarreSuccess
        case .paused:       return .bizarreWarning
        case .cancelled:    return .bizarreError
        case .pending:      return .bizarreOnSurfaceMuted
        case .gracePeriod:  return .bizarreOrange
        case .expired:      return .bizarreError
        }
    }

    var body: some View {
        Text(status.displayName)
            .font(.brandLabelSmall())
            .foregroundStyle(color)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .background(Capsule().fill(color.opacity(0.15)))
            .accessibilityLabel("Status: \(status.displayName)")
    }
}
