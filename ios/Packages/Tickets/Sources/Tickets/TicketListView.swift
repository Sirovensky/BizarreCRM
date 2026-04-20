#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
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
            .toolbar { newTicketToolbar }
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
            .toolbar { newTicketToolbar }
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

    @ViewBuilder
    private func listContent(onSelect: @escaping (Int64) -> Void) -> some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            TicketErrorState(message: err) { Task { await vm.load() } }
        } else if vm.tickets.isEmpty {
            TicketEmptyState(hint: emptyHint)
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
                        .contextMenu { rowContextMenu(for: ticket) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func ticketRow(ticket: TicketSummary, onSelect: @escaping (Int64) -> Void) -> some View {
        if Platform.isCompact {
            NavigationLink(value: ticket.id) {
                TicketRow(ticket: ticket)
            }
            .hoverEffect(.highlight)
        } else {
            Button { onSelect(ticket.id) } label: {
                TicketRow(ticket: ticket)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .tag(ticket.id)
        }
    }

    /// Edit navigates to detail (hosts the edit toolbar). Duplicate /
    /// Mark-complete are stubs pending one-shot backend endpoints.
    @ViewBuilder
    private func rowContextMenu(for ticket: TicketSummary) -> some View {
        if api != nil {
            Button {
                if Platform.isCompact {
                    path.append(ticket.id)
                } else {
                    selected = ticket.id
                }
            } label: {
                Label("Edit", systemImage: "pencil")
            }
        }
        Button {
            // TODO: POST /tickets/:id/duplicate
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        .disabled(true)
        Button {
            // TODO: one-shot status-change endpoint
        } label: {
            Label("Mark complete", systemImage: "checkmark.circle")
        }
        .disabled(true)
    }

    private var emptyHint: String {
        if !searchText.isEmpty { return "No results for \"\(searchText)\"." }
        switch vm.filter {
        case .all:        return "Create a ticket to get started."
        case .myTickets:  return "No tickets are assigned to you."
        case .open:       return "Nothing open right now."
        case .inProgress: return "No tickets in progress."
        case .waiting:    return "Nothing waiting."
        case .closed:     return "Nothing closed yet."
        }
    }

    private var filterChips: some View {
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

private struct TicketEmptyState: View {
    let hint: String

    var body: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "tray")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(hint)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
#endif
