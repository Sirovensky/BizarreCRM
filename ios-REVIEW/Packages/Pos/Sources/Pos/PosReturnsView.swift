#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §16.9 — entry screen for processing returns. Staff arrive here via the
/// POS toolbar "Process return" action. Search by order id or phone →
/// invoice list → refund sheet.
///
/// The view model lives inside this file (kept small — the whole returns
/// feature is under 400 LOC between the list + refund sheet) because it
/// is the only caller and the state is local to the screen.
struct PosReturnsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: PosReturnsViewModel
    @State private var selectedInvoice: InvoiceSummary?

    let api: APIClient?

    init(api: APIClient?) {
        self.api = api
        _vm = State(wrappedValue: PosReturnsViewModel(api: api))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchField
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.top, BrandSpacing.sm)
                        .padding(.bottom, BrandSpacing.xs)
                    content
                }
            }
            .navigationTitle("Process return")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await vm.load() }
            .sheet(item: $selectedInvoice) { invoice in
                PosRefundSheet(invoice: invoice, api: api)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            TextField("Search by order id or phone", text: Binding(
                get: { vm.query },
                set: { vm.onQueryChange($0) }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier("pos.returns.search")
            if !vm.query.isEmpty {
                Button { vm.onQueryChange("") } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, BrandSpacing.md)
        .frame(minHeight: 48)
        .background(Color.bizarreSurface2.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5))
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.invoices.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            errorState(err)
        } else if vm.invoices.isEmpty {
            emptyState
        } else {
            invoiceList
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.bizarreError)
            Text("Couldn't load invoices")
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
        .accessibilityIdentifier("pos.returns.error")
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(vm.query.isEmpty ? "Search by order id or phone." : "No invoices match \u{201C}\(vm.query)\u{201D}")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("pos.returns.empty")
    }

    private var invoiceList: some View {
        List(vm.invoices) { invoice in
            Button {
                selectedInvoice = invoice
            } label: {
                PosReturnsRow(invoice: invoice)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.bizarreSurface1)
            .hoverEffect(.highlight)
            .accessibilityIdentifier("pos.returns.row.\(invoice.id)")
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

/// Row component for the invoice list. Lightweight — totals + customer +
/// status pill.
struct PosReturnsRow: View {
    let invoice: InvoiceSummary

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.displayId)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text(invoice.customerName)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: BrandSpacing.sm)
            VStack(alignment: .trailing, spacing: 2) {
                Text(CartMath.formatCents(Int(((invoice.total ?? 0) * 100).rounded())))
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                if let status = invoice.status {
                    Text(status.uppercased())
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

/// View model. Internal — only the returns view touches this.
@MainActor
@Observable
final class PosReturnsViewModel {
    private(set) var invoices: [InvoiceSummary] = []
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    var query: String = ""

    @ObservationIgnored private let api: APIClient?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(api: APIClient?) { self.api = api }

    func load() async {
        if invoices.isEmpty { isLoading = true }
        defer { isLoading = false }
        await fetch()
    }

    func onQueryChange(_ new: String) {
        query = new
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await fetch()
        }
    }

    private func fetch() async {
        guard let api else {
            errorMessage = "Server not connected."
            invoices = []
            return
        }
        errorMessage = nil
        do {
            let response = try await api.listInvoices(
                filter: .all,
                keyword: query.isEmpty ? nil : query,
                pageSize: 50
            )
            invoices = response.invoices
        } catch {
            errorMessage = error.localizedDescription
            invoices = []
        }
    }
}
#endif
