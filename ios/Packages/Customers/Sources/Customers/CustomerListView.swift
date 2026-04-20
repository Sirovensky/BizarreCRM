#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

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
            .toolbar { newCustomerToolbar }
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
            .toolbar { newCustomerToolbar }
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

    @ViewBuilder
    private func listContent(onSelect: @escaping (Int64) -> Void) -> some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            ErrorState(message: err) { Task { await vm.load() } }
        } else if vm.customers.isEmpty {
            EmptyState(isSearching: !searchText.isEmpty)
        } else {
            List(selection: Binding<Int64?>(
                get: { Platform.isCompact ? nil : selected },
                set: { if let id = $0 { selected = id } }
            )) {
                ForEach(vm.customers) { customer in
                    customerRow(customer: customer, onSelect: onSelect)
                        .listRowBackground(Color.bizarreSurface1)
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
        } else {
            Button { onSelect(customer.id) } label: {
                CustomerRow(customer: customer)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .tag(customer.id)
        }
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
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnOrange)
            }
            .frame(width: 44, height: 44)

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

            Spacer()

            if let count = customer.ticketCount, count > 0 {
                VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                    Text("\(count)")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                    Text(count == 1 ? "ticket" : "tickets")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
    }
}

// MARK: - Empty / Error / Placeholder

private struct ErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
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

private struct EmptyState: View {
    let isSearching: Bool

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "person.2")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(isSearching ? "No results" : "No customers yet")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyDetailPlaceholder: View {
    var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "person.crop.rectangle.stack")
                    .font(.system(size: 56))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text("Select a customer")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Pick someone from the list to see their full profile.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
            }
        }
    }
}
#endif
