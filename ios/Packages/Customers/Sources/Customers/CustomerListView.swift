#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
import Sync

public struct CustomerListView: View {
    @State private var vm: CustomerListViewModel
    @State private var searchText: String = ""
    @State private var path: [Int64] = []
    @State private var selected: Int64?
    @State private var showingCreate: Bool = false
    private let listRepo: CustomerRepository
    private let detailRepo: CustomerDetailRepository
    private let api: APIClient

    public init(repo: CustomerRepository, detailRepo: CustomerDetailRepository, api: APIClient) {
        self.listRepo = repo
        self.detailRepo = detailRepo
        self.api = api
        _vm = State(wrappedValue: CustomerListViewModel(repo: repo))
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
                listContent { id in
                    path.append(id)
                }
            }
            .navigationTitle("Customers")
            .searchable(text: $searchText, prompt: "Search customers")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .task { await vm.load() }
            .refreshable { await vm.refresh() }
            .navigationDestination(for: Int64.self) { id in
                CustomerDetailView(repo: detailRepo, customerId: id, api: api)
            }
            .toolbar {
                newCustomerToolbar
                stalenessToolbarItem
            }
            .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.refresh() } }) {
                CustomerCreateView(api: api)
            }
        }
    }

    // MARK: - iPad (regular)

    private var regularLayout: some View {
        NavigationSplitView {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                listContent { id in
                    selected = id
                }
            }
            .navigationTitle("Customers")
            .searchable(text: $searchText, prompt: "Search customers")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .task { await vm.load() }
            .refreshable { await vm.refresh() }
            .toolbar {
                newCustomerToolbar
                stalenessToolbarItem
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 520)
            .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.refresh() } }) {
                CustomerCreateView(api: api)
            }
        } detail: {
            if let id = selected {
                NavigationStack {
                    CustomerDetailView(repo: detailRepo, customerId: id, api: api)
                }
            } else {
                EmptyDetailPlaceholder()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Shared

    private var newCustomerToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingCreate = true } label: {
                Image(systemName: "plus")
            }
            .keyboardShortcut("N", modifiers: .command)
            .accessibilityLabel("New customer")
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
            CustomerErrorState(message: err) { Task { await vm.load() } }
        } else if vm.customers.isEmpty && !Reachability.shared.isOnline {
            OfflineEmptyStateView(entityName: "customers")
        } else if vm.customers.isEmpty {
            CustomerEmptyState(isSearching: !searchText.isEmpty, query: searchText)
        } else {
            List(selection: Binding<Int64?>(
                get: { Platform.isCompact ? nil : selected },
                set: { if let id = $0 { selected = id } }
            )) {
                ForEach(vm.customers) { customer in
                    customerRow(customer: customer, onSelect: onSelect)
                        .listRowBackground(Color.bizarreSurface1)
                        .listRowInsets(EdgeInsets(
                            top: BrandSpacing.sm,
                            leading: BrandSpacing.base,
                            bottom: BrandSpacing.sm,
                            trailing: BrandSpacing.base
                        ))
                        .listRowSeparatorTint(Color.bizarreOutline.opacity(0.2))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func customerRow(customer: CustomerSummary, onSelect: @escaping (Int64) -> Void) -> some View {
        if Platform.isCompact {
            NavigationLink(value: customer.id) {
                CustomerRow(customer: customer)
            }
            .hoverEffect(.highlight)
            .contextMenu { customerContextMenu(for: customer, onSelect: onSelect) }
        } else {
            Button { onSelect(customer.id) } label: {
                CustomerRow(customer: customer)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .tag(customer.id)
            .contextMenu { customerContextMenu(for: customer, onSelect: onSelect) }
        }
    }

    // MARK: - §22 Customer context menu

    @ViewBuilder
    private func customerContextMenu(
        for customer: CustomerSummary,
        onSelect: @escaping (Int64) -> Void
    ) -> some View {
        // View Customer
        Button {
            onSelect(customer.id)
        } label: {
            Label("View Customer", systemImage: "person.circle")
        }
        .accessibilityLabel("View \(customer.displayName)")

        // New Ticket
        Button {
            // TODO: deep-link to TicketCreateView pre-filled with customer — Phase 4
        } label: {
            Label("New Ticket", systemImage: "ticket")
        }
        .accessibilityLabel("Create new ticket for \(customer.displayName)")

        // New SMS
        if customer.contactLine != nil {
            Button {
                // TODO: open SMS compose sheet — Phase 12
            } label: {
                Label("New SMS", systemImage: "message")
            }
            .accessibilityLabel("Send SMS to \(customer.displayName)")
        }

        Divider()

        // Merge
        Button {
            // TODO: present CustomerMergeView — Phase 4
        } label: {
            Label("Merge\u{2026}", systemImage: "person.2.badge.gearshape")
        }
        .accessibilityLabel("Merge \(customer.displayName) with another customer")

        // Archive (destructive-ish)
        Button {
            // TODO: POST /customers/:id/archive — Phase 4
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
        .accessibilityLabel("Archive \(customer.displayName)")
    }
}

// MARK: - Row

private struct CustomerRow: View {
    let customer: CustomerSummary

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.bizarreOrangeContainer)
                Text(customer.initials)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnOrange)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(customer.displayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let line = customer.contactLine {
                    Text(line)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: BrandSpacing.sm)

            if let count = customer.ticketCount, count > 0 {
                TicketCountBadge(count: count)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

/// Compact pill — single-value chip instead of stacked 20pt + 13pt pair
/// so count + label sit tight and the row stays horizontal.
private struct TicketCountBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: BrandSpacing.xxs) {
            Text("\(count)")
                .monospacedDigit()
            Text(count == 1 ? "ticket" : "tickets")
        }
        .font(.brandLabelSmall())
        .foregroundStyle(.bizarreOnSurfaceMuted)
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xs)
        .background(Color.bizarreSurface2.opacity(0.7), in: Capsule())
        .accessibilityLabel("\(count) \(count == 1 ? "ticket" : "tickets")")
    }
}

// MARK: - Empty / Error / Placeholder

private struct CustomerErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load customers")
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

private struct CustomerEmptyState: View {
    let isSearching: Bool
    let query: String

    var body: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: isSearching ? "magnifyingglass" : "person.2")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(title)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        if isSearching {
            return query.isEmpty ? "No results" : "No results for \u{201C}\(query)\u{201D}"
        }
        return "Tap + to add your first customer."
    }
}

private struct EmptyDetailPlaceholder: View {
    var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "person.crop.rectangle.stack")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("Select a customer")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Pick someone from the list to see their profile.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
            }
        }
    }
}
#endif
