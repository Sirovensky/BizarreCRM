#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
import Sync
import Customers

public struct TicketListView: View {
    @State private var vm: TicketListViewModel
    @State private var searchText: String = ""
    @State private var path: [Int64] = []
    @State private var selected: Int64?
    @State private var showingCreate: Bool = false
    private let repo: TicketRepository
    private let api: APIClient?
    private let customerRepo: CustomerRepository?

    // §22 quick-action handlers — no-op unless api is wired.
    private var quickActionHandlers: TicketQuickActionHandlers {
        TicketQuickActionHandlers(
            onAdvanceStatus: { [weak vm] ticket, transition in
                guard let vm else { return }
                Task { await vm.advanceStatus(ticket: ticket, transition: transition) }
            },
            onAssign: { _, _ in
                // TODO: POST /tickets/:id/assign — endpoint pending §4 write flow
            },
            onAddNote: { _ in
                // TODO: present AddNoteSheet — §4 write flow
            },
            onDuplicate: { _ in
                // TODO: POST /tickets/:id/duplicate — endpoint pending §4
            },
            onArchive: { [weak vm] ticket in
                guard let vm else { return }
                Task { await vm.archive(ticket: ticket) }
            },
            onDelete: { [weak vm] ticket in
                guard let vm else { return }
                Task { await vm.delete(ticket: ticket) }
            }
        )
    }

    /// List + detail only. Create/Edit unavailable.
    public init(repo: TicketRepository) {
        self.repo = repo
        self.api = nil
        self.customerRepo = nil
        _vm = State(wrappedValue: TicketListViewModel(repo: repo))
    }

    /// Enables the "+" toolbar + Edit in the row context menu.
    public init(repo: TicketRepository, api: APIClient, customerRepo: CustomerRepository) {
        self.repo = repo
        self.api = api
        self.customerRepo = customerRepo
        _vm = State(wrappedValue: TicketListViewModel(repo: repo))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
    }

    // MARK: - iPhone (compact)

    private var compactLayout: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterChips
                    listContent { id in
                        path.append(id)
                    }
                }
            }
            .navigationTitle("Tickets")
            .searchable(text: $searchText, prompt: "Search tickets")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .task { await vm.load() }
            .refreshable { await vm.refresh() }
            .navigationDestination(for: Int64.self) { id in
                detailView(for: id)
            }
            .toolbar {
                newTicketToolbar
                stalenessToolbarItem
            }
            .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.refresh() } }) {
                if let api, let customerRepo {
                    TicketCreateView(api: api, customerRepo: customerRepo)
                }
            }
        }
    }

    // MARK: - iPad (regular)

    private var regularLayout: some View {
        NavigationSplitView {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterChips
                    listContent { id in
                        selected = id
                    }
                }
            }
            .navigationTitle("Tickets")
            .searchable(text: $searchText, prompt: "Search tickets")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .task { await vm.load() }
            .refreshable { await vm.refresh() }
            .toolbar {
                newTicketToolbar
                stalenessToolbarItem
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 520)
            .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.refresh() } }) {
                if let api, let customerRepo {
                    TicketCreateView(api: api, customerRepo: customerRepo)
                }
            }
        } detail: {
            if let id = selected {
                NavigationStack {
                    detailView(for: id)
                }
            } else {
                EmptyTicketDetailPlaceholder()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Shared

    @ViewBuilder
    private func detailView(for id: Int64) -> some View {
        if let api {
            TicketDetailView(repo: repo, ticketId: id, api: api)
        } else {
            TicketDetailView(repo: repo, ticketId: id)
        }
    }

    private var newTicketToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingCreate = true
            } label: {
                Image(systemName: "plus")
            }
            .keyboardShortcut("N", modifiers: .command)
            .accessibilityLabel("New ticket")
            .disabled(api == nil || customerRepo == nil)
        }
    }

    private var stalenessToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
        }
    }

    @ViewBuilder
    private func listContent(onSelect: @escaping (Int64) -> Void) -> some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            // §4.13: Network error on list — keep cached data visible (handled above when tickets non-empty)
            TicketErrorState(message: err) { Task { await vm.load() } }
        } else if vm.tickets.isEmpty && !Reachability.shared.isOnline {
            OfflineEmptyStateView(entityName: "tickets")
        } else if vm.tickets.isEmpty {
            // §4.13: No tickets empty glass illustration + "Create one." CTA
            TicketEmptyState(hint: emptyHint, showCreate: vm.filter == .all && searchText.isEmpty) {
                showingCreate = true
            }
        } else {
            List(selection: Binding<Int64?>(
                get: { Platform.isCompact ? nil : selected },
                set: { if let id = $0 { selected = id } }
            )) {
                ForEach(vm.tickets) { ticket in
                    ticketRow(ticket: ticket, onSelect: onSelect)
                        .listRowBackground(Color.bizarreSurface1)
                        .listRowInsets(EdgeInsets(top: BrandSpacing.sm, leading: BrandSpacing.base, bottom: BrandSpacing.sm, trailing: BrandSpacing.base))
                        .listRowSeparatorTint(Color.bizarreOutline.opacity(0.2))
                }
                // §4.1 Footer state row
                ListFooterRow(
                    count: vm.tickets.count,
                    isLoading: vm.isRefreshing,
                    lastSyncedAt: vm.lastSyncedAt,
                    isOffline: !Reachability.shared.isOnline
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func ticketRow(ticket: TicketSummary, onSelect: @escaping (Int64) -> Void) -> some View {
        let currentStatus = TicketStatus(rawValue: ticket.status?.name.lowercased().replacingOccurrences(of: " ", with: "") ?? "")
        if Platform.isCompact {
            NavigationLink(value: ticket.id) {
                TicketRow(ticket: ticket)
            }
            .hoverEffect(.highlight)
            .contextMenu {
                TicketQuickActionsContent(
                    ticket: ticket,
                    currentStatus: currentStatus,
                    assignees: [],
                    handlers: quickActionHandlers
                )
            }
            .modifier(TicketRowSwipeActions(
                ticket: ticket,
                currentStatus: currentStatus,
                handlers: quickActionHandlers
            ))
        } else {
            Button { onSelect(ticket.id) } label: {
                TicketRow(ticket: ticket)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .tag(ticket.id)
            .contextMenu {
                TicketQuickActionsContent(
                    ticket: ticket,
                    currentStatus: currentStatus,
                    assignees: [],
                    handlers: quickActionHandlers
                )
            }
            .modifier(TicketRowSwipeActions(
                ticket: ticket,
                currentStatus: currentStatus,
                handlers: quickActionHandlers
            ))
        }
    }

    private var emptyHint: String {
        if !searchText.isEmpty { return "No results for \"\(searchText)\"." }
        switch vm.filter {
        case .all:        return "No tickets yet. Create one."
        case .myTickets:  return "No tickets are assigned to you."
        case .open:       return "Nothing open right now."
        case .onHold:     return "Nothing on hold."
        case .active:     return "No active tickets."
        case .closed:     return "Nothing closed yet."
        case .cancelled:  return "Nothing cancelled."
        }
    }

    // MARK: - §4.1 Filter chips (All / Open / On Hold / Active / Closed / Cancelled)

    private var filterChips: some View {
        VStack(spacing: 0) {
            // Status group chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.xs) {
                    ForEach(TicketListFilter.allCases) { option in
                        FilterChip(
                            label: option.displayName,
                            selected: vm.filter == option
                        ) {
                            Task { await vm.applyFilter(option) }
                        }
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.sm)
            }
            .scrollClipDisabled()

            // §4.1 Urgency chips (Critical / High / Medium / Normal / Low)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.xs) {
                    ForEach(TicketUrgencyFilter.allCases) { urgency in
                        UrgencyChip(
                            urgency: urgency,
                            selected: vm.urgencyFilter == urgency
                        ) {
                            Task { await vm.applyUrgency(urgency) }
                        }
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.sm)
            }
            .scrollClipDisabled()
        }
    }
}

// MARK: - §4.1 Urgency chip

private struct UrgencyChip: View {
    let urgency: TicketUrgencyFilter
    let selected: Bool
    let action: () -> Void

    /// Map the urgency level to a SwiftUI semantic color.
    private var dotColor: Color {
        switch urgency {
        case .critical: return Color(UIColor.systemRed)
        case .high:     return Color(UIColor.systemOrange)
        case .medium:   return Color(UIColor.systemYellow)
        case .normal:   return Color(UIColor.systemGreen)
        case .low:      return Color(UIColor.systemGray)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: BrandSpacing.xxs) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(urgency.displayName)
                    .font(.brandLabelLarge())
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.xs)
            .foregroundStyle(selected ? Color.black : Color.bizarreOnSurface)
            .background(
                selected ? dotColor.opacity(0.25) : Color.bizarreSurface1,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        selected ? dotColor : Color.bizarreOutline.opacity(0.4),
                        lineWidth: selected ? 1.0 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(urgency.displayName)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Row

private struct TicketRow: View {
    let ticket: TicketSummary

    var body: some View {
        HStack(alignment: .center, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(primaryLine)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                Text(secondaryLine)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: BrandSpacing.sm)

            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                if let status = ticket.status {
                    StatusPill(status.name, hue: groupHue(status.group))
                }
                Text(formatMoney(ticket.total))
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            RowAccessibilityFormatter.ticketRow(
                id: ticket.orderId,
                customer: ticket.customer?.displayName ?? "",
                device: ticket.firstDevice?.deviceName ?? "",
                status: ticket.status?.name ?? "",
                dueAt: nil
            )
        )
        .accessibilityHint(RowAccessibilityFormatter.ticketRowHint)
        .accessibilityAddTraits(.isButton)
    }

    // Customer-first, falling back to device or order ID.
    private var primaryLine: String {
        if let name = ticket.customer?.displayName, !name.isEmpty { return name }
        if let device = ticket.firstDevice?.deviceName, !device.isEmpty { return device }
        return ticket.orderId
    }

    private var secondaryLine: String {
        let device = ticket.firstDevice?.deviceName ?? ""
        if !device.isEmpty && device != primaryLine {
            return "\(ticket.orderId)  \u{2022}  \(device)"
        }
        return ticket.orderId
    }

    private func groupHue(_ group: TicketSummary.Status.Group) -> StatusPill.Hue {
        switch group {
        case .inProgress: return .inProgress
        case .waiting:    return .awaiting
        case .complete:   return .completed
        case .cancelled:  return .archived
        }
    }

    private func formatMoney(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(cents / 100)"
    }
}

// MARK: - Filter chip

private struct FilterChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.brandLabelLarge())
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.xs)
                .foregroundStyle(selected ? Color.black : Color.bizarreOnSurface)
                .background(
                    selected ? Color.bizarreOrange : Color.bizarreSurface1,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.bizarreOutline.opacity(selected ? 0 : 0.4), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Empty / Error / Placeholder

private struct TicketErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load tickets")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Try again", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// §4.13: Glass illustration empty state with optional "Create one." CTA.
private struct TicketEmptyState: View {
    let hint: String
    var showCreate: Bool = false
    var onCreate: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
                .padding(.bottom, BrandSpacing.xs)
            Text(hint)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
            if showCreate, let onCreate {
                Button(action: onCreate) {
                    Text("Create a Ticket")
                        .font(.brandLabelLarge())
                        .padding(.horizontal, BrandSpacing.lg)
                        .padding(.vertical, BrandSpacing.sm)
                        .foregroundStyle(.white)
                        .background(Color.bizarreOrange, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create your first ticket")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyTicketDetailPlaceholder: View {
    var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("Select a ticket from the list.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
    }
}

/// §4.1 Footer states: Loading… / Showing N / End of list / Offline — N cached, last synced Xh ago.
private struct ListFooterRow: View {
    let count: Int
    let isLoading: Bool
    let lastSyncedAt: Date?
    let isOffline: Bool

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Spacer()
            content
            Spacer()
        }
        .padding(.vertical, BrandSpacing.sm)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            HStack(spacing: BrandSpacing.xs) {
                ProgressView().scaleEffect(0.7)
                Text("Loading…")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        } else if isOffline {
            Text(offlineLabel)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreWarning)
                .multilineTextAlignment(.center)
        } else if count > 0 {
            Text("Showing \(count) tickets")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private var offlineLabel: String {
        var parts = ["\(count) cached"]
        if let synced = lastSyncedAt {
            let hrs = Int(Date().timeIntervalSince(synced) / 3600)
            if hrs < 1 {
                let mins = Int(Date().timeIntervalSince(synced) / 60)
                parts.append("last synced \(max(mins, 1))m ago")
            } else {
                parts.append("last synced \(hrs)h ago")
            }
        }
        return "Offline — " + parts.joined(separator: ", ")
    }
}
#endif
