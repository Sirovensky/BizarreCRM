import SwiftUI
import DesignSystem
import Networking

// MARK: - LoyaltyThreeColumnView

/// §22 — iPad-only 3-column loyalty layout.
///
/// Columns:
///   1. **Tier sidebar** (Bronze / Silver / Gold / Platinum) — `LoyaltyTierSidebar`
///   2. **Member list** — filtered `Table` of memberships for the selected tier
///   3. **Balance + history inspector** — `MembershipBalanceInspector`
///
/// Liquid Glass chrome appears on the navigation bar only.
/// Glass is NOT applied to list rows, data tables, or content backgrounds
/// (per CLAUDE.md "DON'T USE glass on: List rows, cards, data tables").
///
/// This view must only be presented on `horizontalSizeClass == .regular`.
/// Gate with `Platform.isCompact` at the call site.
public struct LoyaltyThreeColumnView: View {

    // MARK: - Dependencies

    private let api: any APIClient
    private let manager: MembershipSubscriptionManager
    private let onEnroll: ((String) -> Void)?
    private let onRedeemPoints: ((String) -> Void)?

    // MARK: - State

    @State private var selectedTier: LoyaltyTier? = .bronze
    @State private var selectedMembershipId: String? = nil
    @State private var searchText: String = ""
    @State private var memberCountsByTier: [LoyaltyTier: Int] = [:]
    @State private var membershipListVM: MembershipListViewModel
    @State private var isRefreshing: Bool = false
    @FocusState private var searchFocused: Bool

    // MARK: - Init

    public init(
        api: any APIClient,
        manager: MembershipSubscriptionManager,
        onEnroll: ((String) -> Void)? = nil,
        onRedeemPoints: ((String) -> Void)? = nil
    ) {
        self.api = api
        self.manager = manager
        self.onEnroll = onEnroll
        self.onRedeemPoints = onRedeemPoints
        _membershipListVM = State(wrappedValue: MembershipListViewModel(api: api, manager: manager))
    }

    // MARK: - Body

    public var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // Column 1: Tier sidebar
            LoyaltyTierSidebar(
                selectedTier: $selectedTier,
                memberCounts: memberCountsByTier,
                onRefresh: refreshAll
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 300)
        } content: {
            // Column 2: Member list
            memberListColumn
                .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        } detail: {
            // Column 3: Inspector
            inspectorColumn
        }
        .loyaltyKeyboardShortcuts(
            onSelectTier: { tier in selectedTier = tier },
            onRefresh: { Task { await refreshAll() } },
            onFocusSearch: { searchFocused = true },
            onClearSelection: { selectedMembershipId = nil }
        )
        .task { await membershipListVM.load() }
        .onChange(of: membershipListVM.memberships) { _, memberships in
            memberCountsByTier = countsByTier(from: memberships)
        }
    }

    // MARK: - Column 2: Member list

    @ViewBuilder
    private var memberListColumn: some View {
        Group {
            switch membershipListVM.state {
            case .loading:
                ProgressView("Loading members…")
                    .accessibilityLabel("Loading members")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .comingSoon:
                ContentUnavailableView(
                    "Memberships Coming Soon",
                    systemImage: "clock.badge",
                    description: Text("Membership data will be available once the server endpoint is enabled.")
                )

            case .failed(let msg):
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(msg)
                )

            case .loaded:
                if filteredMembers.isEmpty {
                    ContentUnavailableView(
                        "No Members",
                        systemImage: "person.crop.circle.badge.xmark",
                        description: Text(searchText.isEmpty
                            ? "No \(selectedTier?.displayName ?? "") members found."
                            : "No results for \"\(searchText)\".")
                    )
                } else {
                    memberTable
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search members")
        .focused($searchFocused, equals: true)
        .navigationTitle(selectedTier?.displayName ?? "Members")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await refreshAll() }
                } label: {
                    Image(systemName: isRefreshing ? "arrow.clockwise" : "arrow.clockwise")
                        .rotationEffect(isRefreshing ? .degrees(360) : .zero)
                        .animation(isRefreshing ? BrandMotion.syncPulse : .none, value: isRefreshing)
                }
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("Refresh member list")
            }
        }
        .refreshable { await refreshAll() }
    }

    private var memberTable: some View {
        Table(filteredMembers, selection: $selectedMembershipId) {
            TableColumn("Customer") { m in
                let sub = membershipListVM.adminSubsByMembershipId[m.id]
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
            TableColumn("Status") { m in
                MemberStatusChip(status: m.status)
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
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first,
               let membership = filteredMembers.first(where: { $0.id == id }) {
                MembershipContextMenu(
                    membership: membership,
                    actions: contextMenuActions
                )
            }
        }
    }

    // MARK: - Column 3: Inspector

    @ViewBuilder
    private var inspectorColumn: some View {
        if let membershipId = selectedMembershipId,
           let membership = membershipListVM.memberships.first(where: { $0.id == membershipId }),
           let customerId = Int64(membership.customerId) {
            MembershipBalanceInspector(api: api, customerId: customerId)
        } else {
            ContentUnavailableView(
                "Select a Member",
                systemImage: "person.crop.circle",
                description: Text("Select a member from the list to view their balance and points history.")
            )
        }
    }

    // MARK: - Derived state

    private var filteredMembers: [Membership] {
        let tierFiltered = membershipListVM.memberships.filter { m in
            guard let tier = selectedTier else { return true }
            // Match tier from the adminSub's tierName or fall back to membership plan.
            if let sub = membershipListVM.adminSubsByMembershipId[m.id],
               let tierName = sub.tierName {
                return LoyaltyTier.parse(tierName) == tier
            }
            // No tier info — show under bronze by default.
            return tier == .bronze
        }
        guard !searchText.isEmpty else { return tierFiltered }
        return tierFiltered.filter { m in
            let sub = membershipListVM.adminSubsByMembershipId[m.id]
            let name = [sub?.firstName, sub?.lastName].compactMap { $0 }.joined(separator: " ")
            return name.localizedCaseInsensitiveContains(searchText)
                || m.customerId.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var contextMenuActions: MembershipContextMenuActions {
        MembershipContextMenuActions(
            onEnroll: { id in onEnroll?(id) },
            onRedeemPoints: { id in onRedeemPoints?(id) },
            onViewHistory: { id in selectedMembershipId = id },
            onTogglePause: { id in
                Task { @MainActor in
                    if let m = membershipListVM.memberships.first(where: { $0.id == id }) {
                        if m.status == .paused {
                            await membershipListVM.resume(id: id)
                        } else {
                            await membershipListVM.pause(id: id)
                        }
                    }
                }
            }
        )
    }

    // MARK: - Actions

    private func refreshAll() async {
        isRefreshing = true
        await membershipListVM.refresh()
        memberCountsByTier = countsByTier(from: membershipListVM.memberships)
        isRefreshing = false
    }

    private func countsByTier(from memberships: [Membership]) -> [LoyaltyTier: Int] {
        var counts: [LoyaltyTier: Int] = [:]
        for m in memberships {
            let sub = membershipListVM.adminSubsByMembershipId[m.id]
            let tier = LoyaltyTier.parse(sub?.tierName ?? "bronze")
            counts[tier, default: 0] += 1
        }
        return counts
    }
}

// MARK: - MemberStatusChip (file-private)

/// Compact status chip reused only within the three-column table.
private struct MemberStatusChip: View {
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
