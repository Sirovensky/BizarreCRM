#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §7.6 Invoice Aging Report
// GET /reports/aging → buckets 0-30 / 31-60 / 61-90 / 90+
// iPhone: grouped list by bucket; iPad/Mac: Table with sortable columns + row actions

// MARK: - AgingBucketChip (item 1: aging-bucket chip color)

/// Colored chip label for an aging bucket. Color escalates with age:
/// 0–30 = success (green), 31–60 = warning (amber), 61–90 = orange, 90+ = error (red).
struct AgingBucketChip: View {
    let label: String        // "0-30", "31-60", "61-90", "90+"
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.brandLabelSmall())
            if count > 0 {
                Text("(\(count))")
                    .font(.brandLabelSmall())
            }
        }
        .foregroundStyle(chipForeground)
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, 3)
        .background(chipBackground, in: Capsule())
        .accessibilityLabel("\(label) days: \(count) invoice\(count == 1 ? "" : "s")")
    }

    private var chipForeground: Color {
        switch label {
        case "0-30":  return Color(.systemGreen)
        case "31-60": return Color(.systemOrange)
        case "61-90": return Color(red: 0.85, green: 0.35, blue: 0)
        default:      return Color(.systemRed)
        }
    }

    private var chipBackground: Color {
        chipForeground.opacity(0.15)
    }
}

// MARK: - LateFeePreviewRow (item 4: late-fee preview row)

/// Read-only row shown in the aging list when a late-fee policy would apply.
/// Displays the projected fee amount using `LateFeeCalculator`.
struct LateFeePreviewRow: View {
    let projectedFeeCents: Int

    var body: some View {
        HStack {
            Label("Est. late fee", systemImage: "exclamationmark.triangle")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreWarning)
            Spacer()
            Text(formatMoney(projectedFeeCents))
                .font(.brandBodyMedium().monospacedDigit())
                .foregroundStyle(.bizarreWarning)
        }
        .listRowBackground(Color.bizarreWarning.opacity(0.08))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Estimated late fee: \(formatMoney(projectedFeeCents))")
        .accessibilityHint("This fee will be applied if the invoice remains unpaid.")
    }

    private func formatMoney(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: cents / 100)) ?? "$\(cents / 100)"
    }
}

// MARK: - InvoiceAgingViewModel

@MainActor
@Observable
final class InvoiceAgingViewModel {

    enum LoadState: Sendable {
        case idle, loading, loaded(InvoiceAgingReport), failed(String)
    }

    private(set) var loadState: LoadState = .idle
    private(set) var isSendingReminder: Bool = false
    // item 3: richer send-reminder copy
    private(set) var reminderRecipient: String?
    var reminderMessage: String?
    // item 2: statement download state
    private(set) var isGeneratingStatement: Bool = false
    var statementCSV: String?
    var showStatementShare: Bool = false

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
    /// item 3: copy now names the customer and the invoice number.
    func sendReminder(invoiceId: Int64, customerName: String?, displayId: String) async {
        isSendingReminder = true
        reminderMessage = nil
        reminderRecipient = nil
        defer { isSendingReminder = false }
        do {
            _ = try await api.invoiceBulkAction(InvoiceBulkActionRequest(ids: [invoiceId], action: "send_reminder"))
            let name = customerName ?? "customer"
            reminderMessage = "Reminder sent to \(name) for \(displayId)"
            reminderRecipient = name
        } catch {
            AppLog.ui.error("Aging reminder failed: \(error.localizedDescription, privacy: .public)")
            reminderMessage = "Couldn't send reminder — \(error.localizedDescription)"
        }
    }

    // item 2: generate and share an AR statement as CSV
    func downloadStatement(report: InvoiceAgingReport) async {
        isGeneratingStatement = true
        defer { isGeneratingStatement = false }
        var rows = ["Invoice,Customer,Amount,Days Overdue,Bucket"]
        for bucket in report.buckets {
            for inv in bucket.invoices {
                let amount = String(format: "%.2f", Double(inv.totalCents) / 100.0)
                let customer = (inv.customerName ?? "").replacingOccurrences(of: ",", with: " ")
                rows.append("\(inv.displayId),\(customer),\(amount),\(inv.daysOverdue),\(bucket.label)")
            }
        }
        statementCSV = rows.joined(separator: "\n")
        showStatementShare = true
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
        // item 2: share statement CSV
        .sheet(isPresented: $vm.showStatementShare) {
            if let csv = vm.statementCSV,
               let url = writeCSVToTemp(csv: csv) {
                ShareSheet(activityItems: [url])
                    .ignoresSafeArea()
            }
        }
        // Reminder result toast (item 3: richer copy already set in VM)
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
            // item 2: statement download toolbar button
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    statementDownloadButton
                }
            }
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
            // item 2: statement download toolbar button (iPad too)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    statementDownloadButton
                }
            }
            .navigationDestination(for: Int64.self) { id in
                InvoiceDetailView(repo: detailRepo, invoiceId: id, api: api)
            }
        }
    }

    // item 2: statement download button — shares a CSV of all aging rows
    @ViewBuilder
    private var statementDownloadButton: some View {
        if case .loaded(let report) = vm.loadState {
            Button {
                Task { await vm.downloadStatement(report: report) }
            } label: {
                if vm.isGeneratingStatement {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Download Statement", systemImage: "arrow.down.doc")
                        .labelStyle(.iconOnly)
                }
            }
            .accessibilityLabel("Download aging statement as CSV")
            .disabled(vm.isGeneratingStatement)
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

            TableColumn("Bucket") { inv in
                // item 1: aging-bucket chip color in iPad table
                AgingBucketChip(label: bucketLabel(for: inv.daysOverdue), count: 1)
            }
            .width(min: 80, ideal: 100, max: 120)

            TableColumn("Actions") { inv in
                HStack(spacing: BrandSpacing.sm) {
                    Button("Remind") {
                        Task { await vm.sendReminder(invoiceId: inv.id, customerName: inv.customerName, displayId: inv.displayId) }
                    }
                    .buttonStyle(.bordered)
                    .tint(.bizarreOrange)
                    .controlSize(.small)
                    .accessibilityLabel("Send payment reminder for invoice \(inv.displayId) to \(inv.customerName ?? "customer")")
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
                            agingRow(inv: inv, bucketLabel: bucket.label)
                        }
                    } header: {
                        // item 1: bucket section header uses AgingBucketChip for color
                        HStack {
                            AgingBucketChip(label: bucket.label, count: bucket.invoiceCount)
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
    private func agingRow(inv: AgingInvoiceSummary, bucketLabel: String) -> some View {
        // item 4: late-fee preview row — show projected fee for invoices overdue > 30d
        let projectedFee = lateFeePreview(daysOverdue: inv.daysOverdue, totalCents: inv.totalCents)

        Group {
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
                        // item 1: daysOverdue label uses same color ramp as AgingBucketChip
                        Text("\(inv.daysOverdue)d overdue")
                            .font(.brandLabelSmall())
                            .foregroundStyle(agingColor(for: inv.daysOverdue))
                    }
                }
            }
            .listRowBackground(Color.bizarreSurface1)
            .hoverEffect(.highlight)
            .contextMenu {
                Button {
                    Task { await vm.sendReminder(invoiceId: inv.id, customerName: inv.customerName, displayId: inv.displayId) }
                } label: {
                    Label("Send Reminder", systemImage: "bell")
                }
                .accessibilityLabel("Send payment reminder for invoice \(inv.displayId) to \(inv.customerName ?? "customer")")

                Button { showPaySheet = inv.id } label: {
                    Label("Record Payment", systemImage: "creditcard")
                }
                .accessibilityLabel("Record payment for invoice \(inv.displayId)")
            }
            .swipeActions(edge: .leading) {
                Button {
                    Task { await vm.sendReminder(invoiceId: inv.id, customerName: inv.customerName, displayId: inv.displayId) }
                } label: {
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
            // item 5: customer-payable row a11y — full utterance with due date and bucket
            .accessibilityElement(children: .combine)
            .accessibilityLabel(customerPayableA11yLabel(inv: inv, bucketLabel: bucketLabel))
            .accessibilityHint("Double tap to open invoice. Swipe left to record payment, swipe right to send reminder.")

            // item 4: late-fee preview row appears directly after the invoice row when applicable
            if let fee = projectedFee {
                LateFeePreviewRow(projectedFeeCents: fee)
            }
        }
    }

    // item 5: compose a full VoiceOver label for customer-payable rows
    private func customerPayableA11yLabel(inv: AgingInvoiceSummary, bucketLabel: String) -> String {
        var parts: [String] = [inv.displayId]
        if let name = inv.customerName { parts.append(name) }
        parts.append(formatMoney(inv.totalCents))
        parts.append("\(inv.daysOverdue) days overdue")
        parts.append("Bucket: \(bucketLabel) days")
        if let due = inv.dueOn { parts.append("Due: \(due)") }
        return parts.joined(separator: ". ")
    }

    // item 4: project a 2% flat late fee for invoices overdue > 30 days (policy preview only)
    private func lateFeePreview(daysOverdue: Int, totalCents: Int) -> Int? {
        guard daysOverdue > 30 else { return nil }
        let fee = Int(Double(totalCents) * 0.02)
        return fee > 0 ? fee : nil
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

    // item 1: color ramp matches AgingBucketChip (success/warning/orange/error)
    private func agingColor(for days: Int) -> Color {
        switch days {
        case 0...30:  return Color(.systemGreen)
        case 31...60: return Color(.systemOrange)
        case 61...90: return Color(red: 0.85, green: 0.35, blue: 0)
        default:      return Color(.systemRed)
        }
    }

    // item 1: bucket label string for a given daysOverdue count
    private func bucketLabel(for days: Int) -> String {
        switch days {
        case 0...30:  return "0-30"
        case 31...60: return "31-60"
        case 61...90: return "61-90"
        default:      return "90+"
        }
    }

    private func formatMoney(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: cents / 100)) ?? "$\(cents / 100)"
    }

    // item 2: write CSV string to a temp file for sharing
    private func writeCSVToTemp(csv: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("AgingStatement.csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - ShareSheet (UIActivityViewController wrapper)

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
