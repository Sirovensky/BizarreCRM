import SwiftUI
import Core
import DesignSystem
import Networking

public struct InvoiceListView: View {
    @State private var vm: InvoiceListViewModel
    @State private var searchText: String = ""
    @State private var path: [Int64] = []
    private let detailRepo: InvoiceDetailRepository

    public init(repo: InvoiceRepository, detailRepo: InvoiceDetailRepository) {
        self.detailRepo = detailRepo
        _vm = State(wrappedValue: InvoiceListViewModel(repo: repo))
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterChips.padding(.vertical, BrandSpacing.sm)
                    content
                }
            }
            .navigationTitle("Invoices")
            .searchable(text: $searchText, prompt: "Search invoices")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .task { await vm.load() }
            .refreshable { await vm.refresh() }
            .navigationDestination(for: Int64.self) { id in
                InvoiceDetailView(repo: detailRepo, invoiceId: id)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36)).foregroundStyle(.bizarreError)
                Text("Couldn't load invoices").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
                Button("Try again") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.invoices.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "doc.text").font(.system(size: 48)).foregroundStyle(.bizarreOnSurfaceMuted)
                Text(searchText.isEmpty ? "No invoices" : "No results")
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(vm.invoices) { inv in
                    NavigationLink(value: inv.id) { InvoiceRow(invoice: inv) }
                        .listRowBackground(Color.bizarreSurface1)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                ForEach(InvoiceFilter.allCases) { option in
                    FilterChip(label: option.displayName, selected: vm.filter == option) {
                        Task { await vm.applyFilter(option) }
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.base)
        }
    }
}

private struct InvoiceRow: View {
    let invoice: InvoiceSummary

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(invoice.displayId)
                    .font(.brandMono(size: 15))
                    .foregroundStyle(.bizarreOnSurface)
                Text(invoice.customerName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let issued = invoice.createdAt {
                    Text(issued.prefix(10))
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            Spacer(minLength: BrandSpacing.sm)

            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                Text(formatMoney(invoice.total ?? 0))
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                statusBadge
                if let due = invoice.amountDue, due > 0 {
                    Text("Due \(formatMoney(due))")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreError)
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusBadge: some View {
        let label: String = invoice.status.map { $0.capitalized } ?? "—"
        let bg: Color
        let fg: Color
        switch invoice.statusKind {
        case .paid:     bg = .bizarreSuccess; fg = .black
        case .partial:  bg = .bizarreWarning; fg = .black
        case .unpaid:   bg = .bizarreError;   fg = .black
        case .void_:    bg = .bizarreOnSurfaceMuted; fg = .bizarreSurfaceBase
        case .other:    bg = .bizarreSurface2; fg = .bizarreOnSurface
        }
        Text(label)
            .font(.brandLabelSmall())
            .padding(.horizontal, BrandSpacing.sm).padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(fg)
            .background(bg, in: Capsule())
    }

    private func formatMoney(_ dollars: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }
}

private struct FilterChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.brandLabelLarge())
                .padding(.horizontal, BrandSpacing.base).padding(.vertical, BrandSpacing.sm)
                .foregroundStyle(selected ? Color.black : Color.bizarreOnSurface)
                .background(selected ? Color.bizarreOrange : Color.bizarreSurface1, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.bizarreOutline.opacity(selected ? 0 : 0.6), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
