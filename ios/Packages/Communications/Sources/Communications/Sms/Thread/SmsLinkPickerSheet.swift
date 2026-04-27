import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - SmsLinkPickerSheet
//
// §12.2 Ticket / invoice / payment-link picker — allows the composer to insert
// a short URL + ID token into the message body.
//
// Architecture:
//   SmsLinkPickerSheet     — sheet UI with 3-tab segmented picker
//   SmsLinkPickerViewModel — @Observable, loads lists lazily per tab
//
// Token inserted into composer: "[Ticket #T-1234 — view: <baseURL>/public/tracking/1234]"
// baseURL is read from ServerURLStore.

public struct SmsLinkPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: SmsLinkPickerViewModel
    @State private var selectedTab: SmsLinkKind = .ticket

    private let onInsert: (String) -> Void

    public init(api: APIClient, baseURL: String, onInsert: @escaping (String) -> Void) {
        _vm = State(wrappedValue: SmsLinkPickerViewModel(api: api, baseURL: baseURL))
        self.onInsert = onInsert
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    tabPicker
                    content
                }
            }
            .navigationTitle("Insert Link")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        Picker("Link type", selection: $selectedTab) {
            Text("Tickets").tag(SmsLinkKind.ticket)
            Text("Invoices").tag(SmsLinkKind.invoice)
            Text("Pay links").tag(SmsLinkKind.paymentLink)
        }
        .pickerStyle(.segmented)
        .padding(BrandSpacing.base)
        .onChange(of: selectedTab) { _, newTab in
            Task { await vm.load(kind: newTab) }
        }
        .task { await vm.load(kind: selectedTab) }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let items = vm.items(for: selectedTab)
        let isLoading = vm.isLoading(for: selectedTab)
        let error = vm.error(for: selectedTab)

        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = error {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32)).foregroundStyle(.bizarreError)
                Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await vm.load(kind: selectedTab) } }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .padding(BrandSpacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: "tray")
                    .font(.system(size: 32)).foregroundStyle(.bizarreOnSurfaceMuted)
                Text("No items found")
                    .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(items) { item in
                Button {
                    onInsert(item.linkToken(baseURL: vm.baseURL))
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: item.kind.systemImage)
                            .foregroundStyle(.bizarreOrange)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                            Text(item.kind.subtitle)
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        Spacer()
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.bizarreOrange)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Insert link for \(item.label)")
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Kind extension

public enum SmsLinkKind: Hashable, Sendable {
    case ticket, invoice, paymentLink

    var systemImage: String {
        switch self {
        case .ticket:      return "ticket"
        case .invoice:     return "doc.text"
        case .paymentLink: return "link"
        }
    }

    var subtitle: String {
        switch self {
        case .ticket:      return "Tracking link"
        case .invoice:     return "Payment link"
        case .paymentLink: return "Pay link"
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class SmsLinkPickerViewModel {
    public let baseURL: String
    @ObservationIgnored private let api: APIClient

    private var ticketItems: [SmsLinkPickerItem] = []
    private var invoiceItems: [SmsLinkPickerItem] = []
    private var paymentLinkItems: [SmsLinkPickerItem] = []

    private var ticketLoading: Bool = false
    private var invoiceLoading: Bool = false
    private var paymentLinkLoading: Bool = false

    private var ticketError: String?
    private var invoiceError: String?
    private var paymentLinkError: String?

    public init(api: APIClient, baseURL: String) {
        self.api = api
        self.baseURL = baseURL
    }

    public func items(for kind: SmsLinkKind) -> [SmsLinkPickerItem] {
        switch kind {
        case .ticket:      return ticketItems
        case .invoice:     return invoiceItems
        case .paymentLink: return paymentLinkItems
        }
    }

    public func isLoading(for kind: SmsLinkKind) -> Bool {
        switch kind {
        case .ticket:      return ticketLoading
        case .invoice:     return invoiceLoading
        case .paymentLink: return paymentLinkLoading
        }
    }

    public func error(for kind: SmsLinkKind) -> String? {
        switch kind {
        case .ticket:      return ticketError
        case .invoice:     return invoiceError
        case .paymentLink: return paymentLinkError
        }
    }

    public func load(kind: SmsLinkKind) async {
        switch kind {
        case .ticket:
            guard ticketItems.isEmpty, !ticketLoading else { return }
            ticketLoading = true; ticketError = nil
            defer { ticketLoading = false }
            do { ticketItems = try await api.listTicketPickerItems() }
            catch { ticketError = error.localizedDescription }

        case .invoice:
            guard invoiceItems.isEmpty, !invoiceLoading else { return }
            invoiceLoading = true; invoiceError = nil
            defer { invoiceLoading = false }
            do { invoiceItems = try await api.listInvoicePickerItems() }
            catch { invoiceError = error.localizedDescription }

        case .paymentLink:
            guard paymentLinkItems.isEmpty, !paymentLinkLoading else { return }
            paymentLinkLoading = true; paymentLinkError = nil
            defer { paymentLinkLoading = false }
            do { paymentLinkItems = try await api.listPaymentLinkPickerItems() }
            catch { paymentLinkError = error.localizedDescription }
        }
    }
}
