#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §7.6 Invoice Aging Report
// GET /reports/aging → buckets 0-30 / 31-60 / 61-90 / 90+
// iPhone: grouped list by bucket; iPad/Mac: Table with sortable columns + row actions

@MainActor
@Observable
final class InvoiceAgingViewModel {

    enum LoadState: Sendable {
        case idle, loading, loaded(InvoiceAgingReport), failed(String)
    }

    private(set) var loadState: LoadState = .idle
    private(set) var isSendingReminder: Bool = false
    var reminderMessage: String?

    @ObservationIgnored private let api: APIClient

    init(api: APIClient) { self.api = api }

    func load() async {
        loadState = .loading
        do {
            let report = try await api.invoiceAgingReport()
            loadState = .loaded(report)
        } catch {
            AppLog.ui.error("InvoiceAging load failed: \(error.localizedDescription, privacy: .public)")
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Send a reminder email via bulk-action endpoint.
    func sendReminder(invoiceId: Int64) async {
        isSendingReminder = true
        reminderMessage = nil
        defer { isSendingReminder = false }
        do {
            _ = try await api.invoiceBulkAction(InvoiceBulkActionRequest(ids: [invoiceId], action: "send_reminder"))
            reminderMessage = "Reminder sent"
        } catch {
            AppLog.ui.error("Aging reminder failed: \(error.localizedDescription, privacy: .public)")
            reminderMessage = "Failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - View

public struct InvoiceAgingView: View {
    @State private var vm: InvoiceAgingViewModel
    @State private var path: [Int64] = []
    @State private var showPaySheet: Int64?
    @ObservationIgnored private let detailRepo: InvoiceDetailRepository
    @ObservationIgnored private let api: APIClient

    public init(detailRepo: InvoiceDetailRepository, api: APIClient) {
        self.detailRepo = detailRepo
        self.api = api
        _vm = State(wrappedValue: InvoiceAgingViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { iPhoneLayout } else { iPadLayout }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        // Record payment sheet
        .sheet(
            isPresented: Binding(get: { showPaySheet != nil }, set: { if !$0 { showPaySheet = nil } })
        ) {
            if let id = showPaySheet {
                InvoiceDetailView(repo: detailRepo, invoiceId: id, api: api)
            }
        }
        // Reminder result toast
        .overlay(alignment: .bottom) {
            if let msg = vm.reminderMessage {
                Text(msg)
                    .font(.brandBodyMedium())
                    .padding()
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, BrandSpacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        vm.reminderMessage = nil
                    }
                    .accessibilityLabel(msg)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.reminderMessage)
    }

    // MARK: - iPhone: grouped list by bucket

    private var iPhoneLayout: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Invoice Aging")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Int64.self) { id in
                InvoiceDetailView(repo: detailRepo, invoiceId: id, api: api)
            }
        }
    }

    // MARK: - iPad: Table with sortable columns

    private var iPadLayout: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                if case .loaded(let report) = vm.loadState {
                    iPadTable(report: report)
                } else {
                    content
                }
            }
            .navigationTitle("Invoice Aging")
            .navigationDestination(for: Int64.self) { id in
                InvoiceDetailView(repo: detailRepo, invoiceId: id, api: api)
            }
        }
    }

    // MARK: - iPad Table

    @ViewBuilder
    private func iPadTable(report: InvoiceAgingReport) -> some View {
        let allInvoices: [AgingInvoiceSummary] = report.buckets.flatMap(\.invoices)
        Table(allInvoices) {
            TableColumn("Invoice #") { inv in
                Text(inv.displayId)
                    .font(.brandMono(size: 14))
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
            }
            .width(min: 100, ideal: 120, max: 140)

            TableColumn("Customer") { inv in
                Text(inv.customerName ?? "—")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
            }

            TableColumn("Amount") { inv in
                Text(formatMoney(inv.totalCents))
                    .font(.brandBodyMedium().monospacedDigit())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .width(min: 80, ideal: 100, max: 120)

            TableColumn("Days Overdue") { inv in
                Text("\(inv.daysOverdue)d")
                    .font(.brandBodyMedium().monospacedDigit())
                    .foregroundStyle(agingColor(for: inv.daysOverdue))
            }
            .width(min: 80, ideal: 100, max: 120)

            TableColumn("Actions") { inv in
                HStack(spacing: BrandSpacing.sm) {
                    Button("Remind") { Task { await vm.sendReminder(invoiceId: inv.id) } }
                        .buttonStyle(.bordered)
                        .tint(.bizarreOrange)
                        .controlSize(.small)
                        .accessibilityLabel("Send reminder for invoice \(inv.displayId)")
                    Button("Pay") { showPaySheet = inv.id }
                        .buttonStyle(.borderedProminent)
                        .tint(.bizarreOrange)
                        .controlSize(.small)
                        .accessibilityLabel("Record payment for invoice \(inv.displayId)")
                }
            }
            .width(min: 120, ideal: 150)
        }
        .tableStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase)
    }

    // MARK: - Shared content (loading / error / iPhone list)

    @ViewBuilder
    private var content: some View {
        switch vm.loadState {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let msg):
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 36)).foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("Couldn't load aging report").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(msg).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted).multilineTextAlignment(.center)
                Button("Try again") { Task { await vm.load() } }.buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let report):
            if report.buckets.allSatisfy({ $0.invoices.isEmpty }) {
                emptyState
            } else {
                agingList(report: report)
            }
        }
    }

    // MARK: - iPhone grouped list

    private func agingList(report: InvoiceAgingReport) -> some View {
        List {
            // Summary header
            Section {
                HStack {
                    Text("Total overdue")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Spacer()
                    Text(formatMoney(report.totalOverdueCents))
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreError)
                        .monospacedDigit()
                }
                .listRowBackground(Color.bizarreSurface1)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Total overdue: \(formatMoney(report.totalOverdueCents))")
            }

            // Buckets
            ForEach(report.buckets) { bucket in
                if !bucket.invoices.isEmpty {
                    Section {
                        ForEach(bucket.invoices) { inv in
                            agingRow(inv: inv)
                        }
                    } header: {
                        HStack {
                            Text(bucket.label)
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            Spacer()
                            Text(formatMoney(bucket.totalCents))
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreError)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func agingRow(inv: AgingInvoiceSummary) -> some View {
        HStack(spacing: BrandSpacing.md) {
            NavigationLink(value: inv.id) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(inv.displayId)
                        .font(.brandMono(size: 14))
                        .foregroundStyle(.bizarreOnSurface)
                    Text(inv.customerName ?? "—")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                    Text(formatMoney(inv.totalCents))
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                    Text("\(inv.daysOverdue)d overdue")
                        .font(.brandLabelSmall())
                        .foregroundStyle(agingColor(for: inv.daysOverdue))
                }
            }
        }
        .listRowBackground(Color.bizarreSurface1)
        .hoverEffect(.highlight)
        .contextMenu {
            Button { Task { await vm.sendReminder(invoiceId: inv.id) } } label: {
                Label("Send Reminder", systemImage: "bell")
            }
            .accessibilityLabel("Send payment reminder for invoice \(inv.displayId)")

            Button { showPaySheet = inv.id } label: {
                Label("Record Payment", systemImage: "creditcard")
            }
            .accessibilityLabel("Record payment for invoice \(inv.displayId)")
        }
        .swipeActions(edge: .leading) {
            Button { Task { await vm.sendReminder(invoiceId: inv.id) } } label: {
                Label("Remind", systemImage: "bell")
            }
            .tint(.bizarreOrange)
        }
        .swipeActions(edge: .trailing) {
            Button { showPaySheet = inv.id } label: {
                Label("Pay", systemImage: "creditcard")
            }
            .tint(.bizarreSuccess)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(inv.displayId). \(inv.customerName ?? "—"). \(formatMoney(inv.totalCents)). \(inv.daysOverdue) days overdue.")
        .accessibilityHint("Double tap to open invoice. Swipe left to record payment, swipe right to send reminder.")
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
            Text("No overdue invoices").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text("All invoices are current.").font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func agingColor(for days: Int) -> Color {
        switch days {
        case 0...30: return .bizarreWarning
        case 31...60: return .bizarreError
        default: return Color(red: 0.7, green: 0, blue: 0)
        }
    }

    private func formatMoney(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: cents / 100)) ?? "$\(cents / 100)"
    }
}
#endif
