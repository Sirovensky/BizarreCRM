#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - CustomersThreeColumnView

/// iPad-only three-column layout: filter sidebar | customer list | detail.
///
/// ## Columns
/// 1. **Sidebar** (`CustomerFilterSidebar`) — All / Recent / VIP / At Risk
/// 2. **List** — filtered `CustomerSummary` rows with context menus
/// 3. **Detail** — `CustomerDetailView` + trailing `CustomerInspector`
///
/// ## Keyboard shortcuts
/// The view embeds `CustomerKeyboardShortcuts` so ⌘N / ⌘F / ⌘R work regardless
/// of which column has focus.
///
/// ## Glass chrome
/// Navigation chrome uses `.brandGlass` via `BrandGlassContainer` on toolbar elements.
/// List rows carry only `.hoverEffect(.highlight)` per HIG — no glass on data rows.
public struct CustomersThreeColumnView: View {
    // MARK: - State

    @State private var vm: CustomerListViewModel
    @State private var activeFilter: CustomerFilter = .all
    @State private var searchText: String = ""
    @State private var selectedCustomerId: Int64?
    @State private var showingCreate: Bool = false
    @State private var showingSearch: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // MARK: - Dependencies

    private let listRepo: CustomerRepository
    private let detailRepo: CustomerDetailRepository
    private let api: APIClient

    // MARK: - Init

    public init(
        repo: CustomerRepository,
        detailRepo: CustomerDetailRepository,
        api: APIClient
    ) {
        self.listRepo = repo
        self.detailRepo = detailRepo
        self.api = api
        _vm = State(wrappedValue: CustomerListViewModel(repo: repo))
    }

    // MARK: - Filtered customers

    private var filteredCustomers: [CustomerSummary] {
        let filtered = vm.customers.filter { activeFilter.matches($0) }
        guard !searchText.isEmpty else { return filtered }
        let q = searchText.lowercased()
        return filtered.filter {
            $0.displayName.lowercased().contains(q)
            || ($0.email?.lowercased().contains(q) == true)
            || ($0.phone?.contains(q) == true)
            || ($0.mobile?.contains(q) == true)
        }
    }

    // MARK: - Body

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Column 1: filter sidebar
            CustomerFilterSidebar(selection: $activeFilter)
        } content: {
            // Column 2: customer list
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                customerList
            }
            .navigationTitle(activeFilter.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, isPresented: $showingSearch, prompt: "Search customers")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .task { await vm.load() }
            .refreshable { await vm.refresh() }
            .toolbar {
                listToolbar
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 480)
            .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.refresh() } }) {
                CustomerCreateView(api: api)
            }
        } detail: {
            // Column 3: detail + inspector
            if let id = selectedCustomerId {
                detailPane(customerId: id)
            } else {
                EmptySelectionPlaceholder()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(
            // Keyboard shortcuts — always active regardless of column focus
            CustomerKeyboardShortcuts(
                onNewCustomer: { showingCreate = true },
                onFocusSearch: { showingSearch = true },
                onRefresh:     { Task { await vm.refresh() } }
            )
        )
    }

    // MARK: - Customer list

    @ViewBuilder
    private var customerList: some View {
        if vm.isLoading && vm.customers.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage, vm.customers.isEmpty {
            errorState(message: err)
        } else if filteredCustomers.isEmpty {
            emptyState
        } else {
            List(selection: $selectedCustomerId) {
                ForEach(filteredCustomers) { customer in
                    CustomerListRow(customer: customer)
                        .tag(customer.id)
                        .hoverEffect(.highlight)
                        .listRowBackground(Color.bizarreSurface1)
                        .listRowInsets(EdgeInsets(
                            top: BrandSpacing.sm,
                            leading: BrandSpacing.base,
                            bottom: BrandSpacing.sm,
                            trailing: BrandSpacing.base
                        ))
                        .listRowSeparatorTint(Color.bizarreOutline.opacity(0.2))
                        .contextMenu {
                            CustomerContextMenu(
                                customer: customer,
                                onOpen: { selectedCustomerId = customer.id },
                                api: api
                            )
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Detail pane

    private func detailPane(customerId: Int64) -> some View {
        NavigationStack {
            CustomerDetailView(repo: detailRepo, customerId: customerId, api: api)
                .inspector(isPresented: .constant(true)) {
                    CustomerInspector(
                        customerId: customerId,
                        api: api
                    )
                }
        }
    }

    // MARK: - Toolbar

    private var listToolbar: some ToolbarContent {
        Group {
            ToolbarItem(placement: .primaryAction) {
                BrandGlassContainer {
                    Button { showingCreate = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New customer (⌘N)")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { Task { await vm.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh customers (⌘R)")
                .disabled(vm.isLoading)
            }
        }
    }

    // MARK: - Empty / Error

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: activeFilter == .all ? "person.2" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(searchText.isEmpty ? "No \(activeFilter.rawValue.lowercased()) customers" : "No results for \u{201C}\(searchText)\u{201D}")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
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
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - CustomerListRow

/// Single row for the three-column list column.
private struct CustomerListRow: View {
    let customer: CustomerSummary

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            ZStack {
                Circle().fill(Color.bizarreOrangeContainer)
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
                Text("\(count)")
                    .font(.brandLabelSmall())
                    .monospacedDigit()
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xs)
                    .background(Color.bizarreSurface2.opacity(0.7), in: Capsule())
                    .accessibilityLabel("\(count) tickets")
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(RowAccessibilityFormatter.customerRow(
            name: customer.displayName,
            phone: customer.phone ?? customer.mobile,
            openTicketCount: customer.ticketCount ?? 0,
            ltvCents: nil,
            lastVisitAt: nil
        ))
        .accessibilityHint(RowAccessibilityFormatter.customerRowHint)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - EmptySelectionPlaceholder

private struct EmptySelectionPlaceholder: View {
    var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "person.crop.rectangle.stack")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("Select a customer")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Choose someone from the list to see their profile and health details.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.xl)
            }
        }
    }
}
#endif
