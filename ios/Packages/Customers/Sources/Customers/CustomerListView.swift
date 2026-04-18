import SwiftUI
import Core
import DesignSystem
import Networking

public struct CustomerListView: View {
    @State private var vm: CustomerListViewModel
    @State private var searchText: String = ""
    public var onOpen: ((Int64) -> Void)?

    public init(repo: CustomerRepository, onOpen: ((Int64) -> Void)? = nil) {
        _vm = State(wrappedValue: CustomerListViewModel(repo: repo))
        self.onOpen = onOpen
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Customers")
            .searchable(text: $searchText, prompt: "Search customers")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .task { await vm.load() }
            .refreshable { await vm.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.bizarreError)
                Text("Couldn't load customers")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(err)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
                Button("Try again") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.customers.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "person.2")
                    .font(.system(size: 48))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(searchText.isEmpty ? "No customers yet" : "No results")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(vm.customers) { customer in
                    Button { onOpen?(customer.id) } label: {
                        CustomerRow(customer: customer)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.bizarreSurface1)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
