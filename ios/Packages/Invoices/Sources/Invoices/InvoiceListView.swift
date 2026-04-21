#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
import Sync

public struct InvoiceListView: View {
    @State private var vm: InvoiceListViewModel
    @State private var searchText: String = ""
    @State private var path: [Int64] = []
    @State private var selectedInvoice: Int64?
    private let detailRepo: InvoiceDetailRepository
    private let api: APIClient

    public init(repo: InvoiceRepository, detailRepo: InvoiceDetailRepository, api: APIClient) {
        self.detailRepo = detailRepo
        self.api = api
        _vm = State(wrappedValue: InvoiceListViewModel(repo: repo))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task {
            vm.isOffline = !Reachability.shared.isOnline
            await vm.load()
        }
        .refreshable { await vm.refresh() }
    }

    private var compactLayout: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterChips.padding(.vertical, BrandSpacing.sm)
                    content
                }
                if vm.isOffline {
                    OfflineBanner(isOffline: true)
                        .padding(.top, BrandSpacing.xs)
                }
            }
            .navigationTitle("Invoices")
            .searchable(text: $searchText, prompt: "Search invoices")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .navigationDestination(for: Int64.self) { id in
                InvoiceDetailView(repo: detailRepo, invoiceId: id, api: api)
            }
            .toolbar {
                ToolbarItem(placement: .status) {
                    StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
                }
            }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            NavigationStack(path: $path) {
                ZStack(alignment: .top) {
                    Color.bizarreSurfaceBase.ignoresSafeArea()
                    VStack(spacing: 0) {
                        filterChips.padding(.vertical, BrandSpacing.sm)
                        content
                    }
                    if vm.isOffline {
                        OfflineBanner(isOffline: true)
                            .padding(.top, BrandSpacing.xs)
                    }
                }
                .navigationTitle("Invoices")
                .searchable(text: $searchText, prompt: "Search invoices")
                .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
                .navigationDestination(for: Int64.self) { id in
                    InvoiceDetailView(repo: detailRepo, invoiceId: id, api: api)
                }
                .toolbar {
                    ToolbarItem(placement: .status) {
                        StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 520)
        } detail: {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.md) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 52))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("Select an invoice")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36)).foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("Couldn't load invoices").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
                Button("Try again") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.invoices.isEmpty && vm.isOffline {
            OfflineEmptyStateView(entityName: "invoices")
        } else if vm.invoices.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "doc.text").font(.system(size: 48)).foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text(searchText.isEmpty ? "No invoices" : "No results")
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(vm.invoices) { inv in
                    NavigationLink(value: inv.id) { InvoiceRow(invoice: inv) }
                        .listRowBackground(Color.bizarreSurface1)
                        .hoverEffect(.highlight)
                        .contextMenu { invoiceContextMenu(for: inv) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - §22 Invoice context menu

    @ViewBuilder
    private func invoiceContextMenu(for inv: InvoiceSummary) -> some View {
        // Email Receipt
        Button {
            // TODO: present InvoiceEmailReceiptSheet — Phase 4 / §7
            selectedInvoice = inv.id
        } label: {
            Label("Email Receipt", systemImage: "envelope")
        }
        .accessibilityLabel("Email receipt for invoice \(inv.displayId)")

        Divider()

        // Refund
        Button {
            // TODO: present InvoiceRefundSheet — Phase 4 / §7
            selectedInvoice = inv.id
        } label: {
            Label("Refund\u{2026}", systemImage: "arrow.uturn.backward.circle")
        }
        .accessibilityLabel("Refund invoice \(inv.displayId)")

        // Void
        Button(role: .destructive) {
            // TODO: present InvoiceVoidConfirmAlert — Phase 4 / §7
            selectedInvoice = inv.id
        } label: {
            Label("Void\u{2026}", systemImage: "xmark.circle")
        }
        .accessibilityLabel("Void invoice \(inv.displayId)")

        // Duplicate
        Button {
            // TODO: POST /invoices/:id/duplicate — Phase 4 / §7
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        .accessibilityLabel("Duplicate invoice \(inv.displayId)")
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
                    .textSelection(.enabled)
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
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.a11yLabel(for: invoice))
        .accessibilityHint(RowAccessibilityFormatter.invoiceRowHint)
        .accessibilityAddTraits(.isButton)
    }

    private var statusBadge: some View {
        let (bg, fg) = statusColors(for: invoice.statusKind)
        let name = invoice.status.map { $0.capitalized } ?? "—"
        return Text(name)
            .font(.brandLabelSmall())
            .padding(.horizontal, BrandSpacing.sm).padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(fg)
            .background(bg, in: Capsule())
            .accessibilityLabel("Status \(name)")
    }

    static func a11yLabel(for inv: InvoiceSummary) -> String {
        // InvoiceSummary.total is Double dollars; convert to cents for RowAccessibilityFormatter.
        let totalCents = Int(((inv.total ?? 0) * 100).rounded())
        // Use createdAt string; parse to Date or fall back to now.
        let issuedDate: Date = {
            guard let str = inv.createdAt else { return Date() }
            let iso = ISO8601DateFormatter()
            if let d = iso.date(from: str) { return d }
            // Try date-only format "YYYY-MM-DD"
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            return df.date(from: String(str.prefix(10))) ?? Date()
        }()
        return RowAccessibilityFormatter.invoiceRow(
            number: inv.displayId,
            customer: inv.customerName,
            totalCents: totalCents,
            status: inv.status ?? "",
            issuedAt: issuedDate
        )
    }

    /// Legacy alias kept for test callsites.
    static func a11y(for inv: InvoiceSummary) -> String { a11yLabel(for: inv) }

    private static func formatMoney(_ dollars: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }

    private func statusColors(for kind: InvoiceSummary.Status) -> (Color, Color) {
        switch kind {
        case .paid:     return (.bizarreSuccess, .black)
        case .partial:  return (.bizarreWarning, .black)
        case .unpaid:   return (.bizarreError,   .black)
        case .void_:    return (.bizarreOnSurfaceMuted, .bizarreSurfaceBase)
        case .other:    return (.bizarreSurface2, .bizarreOnSurface)
        }
    }

    private func formatMoney(_ dollars: Double) -> String { Self.formatMoney(dollars) }
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
#endif
