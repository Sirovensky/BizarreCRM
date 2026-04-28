#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §4.5 Attach ticket to an existing invoice
//
// Staff picks an open invoice from a paged search list.
// On confirm: POST /api/v1/tickets/:id/attach-invoice { invoice_id }.
// On success: parent reloads the ticket detail.

// MARK: - ViewModel

@MainActor
@Observable
public final class TicketAttachInvoiceViewModel {
    public enum Phase: Sendable {
        case idle
        case loading
        case loaded([InvoiceSummary])
        case attaching
        case done
        case error(String)
    }

    public var phase: Phase = .idle
    public var searchText: String = ""
    public var selectedInvoice: InvoiceSummary?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let ticketId: Int64
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(api: APIClient, ticketId: Int64) {
        self.api = api
        self.ticketId = ticketId
    }

    public var invoices: [InvoiceSummary] {
        if case .loaded(let list) = phase { return list }
        return []
    }

    public func loadInvoices() async {
        phase = .loading
        do {
            let list = try await api.listInvoices(keyword: searchText.isEmpty ? nil : searchText)
            phase = .loaded(list)
        } catch {
            phase = .error(error.localizedDescription)
            AppLog.ui.error("AttachInvoice load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func onSearchChange(_ query: String) {
        searchText = query
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await loadInvoices()
        }
    }

    public func attach() async {
        guard let invoice = selectedInvoice else { return }
        phase = .attaching
        do {
            try await api.attachTicketToInvoice(ticketId: ticketId, invoiceId: invoice.id)
            phase = .done
        } catch {
            phase = .error(error.localizedDescription)
            AppLog.ui.error("AttachInvoice submit failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - View

public struct TicketAttachInvoiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TicketAttachInvoiceViewModel
    private let onSuccess: () -> Void

    public init(api: APIClient, ticketId: Int64, onSuccess: @escaping () -> Void) {
        _vm = State(wrappedValue: TicketAttachInvoiceViewModel(api: api, ticketId: ticketId))
        self.onSuccess = onSuccess
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                listContent
            }
            .navigationTitle("Attach to Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $vm.searchText, prompt: "Search invoices")
            .onChange(of: vm.searchText) { _, q in vm.onSearchChange(q) }
            .task { await vm.loadInvoices() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Attach") {
                        Task {
                            await vm.attach()
                            if case .done = vm.phase {
                                onSuccess()
                                dismiss()
                            }
                        }
                    }
                    .disabled(vm.selectedInvoice == nil)
                    .accessibilityLabel("Attach selected invoice to this ticket")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - List content

    @ViewBuilder
    private var listContent: some View {
        switch vm.phase {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading invoices")
        case .error(let msg):
            VStack(spacing: BrandSpacing.md) {
                Text("Could not load invoices")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await vm.loadInvoices() } }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .padding(BrandSpacing.lg)
        case .loaded(let list):
            if list.isEmpty {
                Text("No open invoices found")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(list) { invoice in
                    invoiceRow(invoice)
                        .listRowBackground(Color.bizarreSurface1)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        case .done, .attaching:
            EmptyView()
        }
    }

    private func invoiceRow(_ invoice: InvoiceSummary) -> some View {
        let isSelected = vm.selectedInvoice?.id == invoice.id
        return Button {
            vm.selectedInvoice = isSelected ? nil : invoice
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(invoice.displayId ?? "INV-\(invoice.id)")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    if let name = invoice.customerName, !name.isEmpty {
                        Text(name)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityLabel("Selected")
                }
            }
            .padding(.vertical, BrandSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(
            "\(invoice.displayId ?? "Invoice \(invoice.id)"). " +
            "\(invoice.customerName ?? ""). " +
            (isSelected ? "Selected." : "")
        )
    }
}

// MARK: - InvoiceSummary minimal model for picker
//
// The actual InvoiceSummary lives in Packages/Networking/Invoices.
// We read only the fields we need here.

public extension APIClient {
    /// `GET /api/v1/invoices?keyword=<q>&status=draft,sent&limit=50`
    /// Returns open (unpaid/partial) invoices for the attach-invoice picker.
    func listInvoices(keyword: String? = nil) async throws -> [InvoiceSummary] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "status", value: "draft,sent,partial"),
            URLQueryItem(name: "limit", value: "50")
        ]
        if let kw = keyword, !kw.isEmpty {
            items.append(URLQueryItem(name: "keyword", value: kw))
        }
        return try await get("/api/v1/invoices", query: items, as: [InvoiceSummary].self)
    }
}

/// Minimal invoice row for the attach-invoice picker.
public struct InvoiceSummary: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let displayId: String?
    public let customerName: String?
    public let total: Double?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayId = "display_id"
        case customerName = "customer_name"
        case total, status
    }
}
#endif
