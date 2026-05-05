#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
import Customers
import Sync

// §22 — iPad 3-column NavigationSplitView wrapper
//
// Layout: sidebar (filter picker) | list (ticket list) | detail (TicketDetailView)
//
// Integration:
//   The app-shell selects this view on iPad regular size class; iPhone keeps
//   the existing TicketListView (compact layout).  TicketsThreeColumnView is
//   an *opt-in wrapper* — it does NOT replace TicketListView.
//
// Usage:
//   if horizontalSizeClass == .regular {
//       TicketsThreeColumnView(repo: repo, api: api, customerRepo: customerRepo)
//   } else {
//       TicketListView(repo: repo, api: api, customerRepo: customerRepo)
//   }

/// Three-column NavigationSplitView for iPad regular size class.
///
/// Column 1 (sidebar)  — filter picker
/// Column 2 (content)  — ticket list with search, keyboard shortcuts, context menus
/// Column 3 (detail)   — TicketDetailView or empty placeholder
public struct TicketsThreeColumnView: View {

    // MARK: - State

    @State private var vm: TicketListViewModel
    @State private var selectedFilter: TicketListFilter = .all
    @State private var selectedTicketId: Int64?
    @State private var searchText: String = ""
    @State private var showingCreate: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // MARK: - Dependencies

    private let repo: TicketRepository
    private let api: APIClient?
    private let customerRepo: CustomerRepository?

    // MARK: - Quick-action handlers

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

    // MARK: - Init

    /// Full-featured init — enables create flow and all quick actions.
    public init(repo: TicketRepository, api: APIClient, customerRepo: CustomerRepository) {
        self.repo = repo
        self.api = api
        self.customerRepo = customerRepo
        _vm = State(wrappedValue: TicketListViewModel(repo: repo))
    }

    /// Read-only init — list + detail only.
    public init(repo: TicketRepository) {
        self.repo = repo
        self.api = nil
        self.customerRepo = nil
        _vm = State(wrappedValue: TicketListViewModel(repo: repo))
    }

    // MARK: - Body

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .modifier(TicketKeyboardShortcuts(
            onNew: { showingCreate = true },
            onSearch: { /* search field focused via @FocusState — wired in contentColumn */ },
            onRefresh: { Task { await vm.refresh() } }
        ))
        .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.refresh() } }) {
            if let api, let customerRepo {
                TicketCreateView(api: api, customerRepo: customerRepo)
            }
        }
    }

    // MARK: - Sidebar column (filter picker)

    private var sidebarColumn: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            List {
                Section("Filters") {
                    ForEach(TicketListFilter.allCases) { filter in
                        Button {
                            selectedFilter = filter
                        } label: {
                            HStack {
                                Label(filter.displayName, systemImage: filterSystemImage(filter))
                                Spacer()
                                if selectedFilter == filter {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(filter.displayName)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Tickets")
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
        .onChange(of: selectedFilter) { _, newFilter in
            Task { await vm.applyFilter(newFilter) }
        }
    }

    // MARK: - Content column (ticket list)

    private var contentColumn: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            ticketListContent
        }
        .navigationTitle(selectedFilter.displayName)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search tickets")
        .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
        .task { await vm.load() }
        .refreshable { await vm.refresh() }
        .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 480)
        .toolbar {
            contentToolbar
        }
    }

    @ViewBuilder
    private var ticketListContent: some View {
        if vm.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading tickets")
        } else if let err = vm.errorMessage {
            ipadErrorState(message: err)
        } else if vm.tickets.isEmpty {
            ipadEmptyState
        } else {
            List(selection: $selectedTicketId) {
                ForEach(vm.tickets) { ticket in
                    ticketRow(ticket)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func ticketRow(_ ticket: TicketSummary) -> some View {
        let currentStatus = TicketStatus(rawValue: ticket.status?.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "") ?? "")
        TicketSummaryRow(ticket: ticket)
            .tag(ticket.id)
            .hoverEffect(.highlight)
            .contextMenu {
                TicketContextMenu(
                    ticket: ticket,
                    currentStatus: currentStatus,
                    handlers: quickActionHandlers,
                    onOpen: { selectedTicketId = ticket.id }
                )
            }
            .listRowBackground(Color.bizarreSurface1)
            .listRowInsets(EdgeInsets(
                top: BrandSpacing.sm,
                leading: BrandSpacing.base,
                bottom: BrandSpacing.sm,
                trailing: BrandSpacing.base
            ))
            .listRowSeparatorTint(Color.bizarreOutline.opacity(0.2))
    }

    private var ipadEmptyState: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(emptyHint)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ipadErrorState(message: String) -> some View {
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
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail column

    @ViewBuilder
    private var detailColumn: some View {
        if let id = selectedTicketId {
            NavigationStack {
                if let api {
                    TicketDetailView(repo: repo, ticketId: id, api: api)
                } else {
                    TicketDetailView(repo: repo, ticketId: id)
                }
            }
        } else {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("Select a ticket")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Choose a ticket from the list to view details.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BrandSpacing.lg)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("No ticket selected. Choose a ticket from the list.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var contentToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingCreate = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("New ticket")
            .disabled(api == nil || customerRepo == nil)
            .brandGlass(.clear, in: Circle())
        }

        ToolbarItem(placement: .topBarLeading) {
            StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
        }

        ToolbarItem(placement: .secondaryAction) {
            TicketQuickActionsToolbar(
                handlers: quickActionHandlers,
                selectedTicketId: selectedTicketId,
                tickets: vm.tickets
            )
        }
    }

    // MARK: - Helpers

    private var emptyHint: String {
        if !searchText.isEmpty { return "No results for \"\(searchText)\"." }
        switch selectedFilter {
        case .all:       return "Create a ticket to get started."
        case .open:      return "Nothing open right now."
        case .onHold:    return "Nothing on hold."
        case .closed:    return "Nothing closed yet."
        case .cancelled: return "No cancelled tickets."
        case .active:    return "No active tickets in progress."
        case .myTickets: return "No tickets are assigned to you."
        }
    }

    private func filterSystemImage(_ filter: TicketListFilter) -> String {
        switch filter {
        case .all:       return "tray.2"
        case .open:      return "tray"
        case .onHold:    return "clock"
        case .closed:    return "checkmark.circle"
        case .cancelled: return "xmark.circle"
        case .active:    return "wrench.and.screwdriver"
        case .myTickets: return "person.crop.circle"
        }
    }
}

// MARK: - Ticket summary row (content column)

/// Minimal row used in the three-column content column.
/// Mirrors `TicketListView`'s internal `TicketRow` without creating a dependency.
private struct TicketSummaryRow: View {
    let ticket: TicketSummary

    var body: some View {
        HStack(alignment: .center, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(primaryLine)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                Text(ticket.orderId)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: BrandSpacing.sm)

            if let status = ticket.status {
                StatusPill(status.name, hue: groupHue(status.group))
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(primaryLine), \(ticket.orderId), status: \(ticket.status?.name ?? "unknown")")
        .accessibilityHint("Tap to view details")
    }

    private var primaryLine: String {
        if let name = ticket.customer?.displayName, !name.isEmpty { return name }
        if let device = ticket.firstDevice?.deviceName, !device.isEmpty { return device }
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
}

#endif
