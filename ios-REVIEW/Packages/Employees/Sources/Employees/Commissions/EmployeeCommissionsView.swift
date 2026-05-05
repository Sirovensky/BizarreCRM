import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - EmployeeCommissionsView
//
// Read-only commission list for the signed-in employee.
// iPhone: NavigationStack + List.
// iPad: NavigationSplitView — list on left, detail card on right.
// Liquid Glass on navigation chrome per visual language mandate.

public struct EmployeeCommissionsView: View {

    @Bindable var vm: EmployeeCommissionsViewModel
    /// iPad: selected commission for detail pane.
    @State private var selectedCommission: EmployeeCommission?

    public init(vm: EmployeeCommissionsViewModel) {
        self.vm = vm
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .navigationTitle("My Commissions")
        .task { await vm.load() }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        List {
            if vm.loadState == .loaded {
                Section {
                    totalRow
                }
                Section("Transactions") {
                    commissionRows
                }
            }
        }
        .refreshable { await vm.load() }
        .overlay { stateOverlay }
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        NavigationSplitView {
            List(selection: $selectedCommission) {
                Section {
                    totalRow
                        .listRowBackground(Color.bizarreSurface1)
                }
                Section("Transactions") {
                    commissionRows
                }
            }
            .navigationTitle("My Commissions")
            .frame(minWidth: 280, idealWidth: 340)
            .overlay { stateOverlay }
            .refreshable { await vm.load() }
        } detail: {
            if let commission = selectedCommission {
                CommissionDetailPanel(commission: commission)
                    .brandHover()
            } else {
                ContentUnavailableView(
                    "Select a Commission",
                    systemImage: "dollarsign.circle",
                    description: Text("Choose a transaction from the list")
                )
            }
        }
    }

    // MARK: - Shared subviews

    private var totalRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Total Earned")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(vm.formattedTotal)
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
            Spacer()
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Total commissions earned: \(vm.formattedTotal)")
    }

    @ViewBuilder
    private var commissionRows: some View {
        if vm.commissions.isEmpty && vm.loadState == .loaded {
            Text("No commission records found")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityLabel("No commission records found")
        } else {
            ForEach(vm.commissions) { commission in
                CommissionRow(commission: commission)
                    .brandHover()
            }
        }
    }

    // MARK: - State overlay

    @ViewBuilder
    private var stateOverlay: some View {
        switch vm.loadState {
        case .loading:
            ProgressView("Loading commissions…")
                .accessibilityLabel("Loading commissions")
        case let .failed(msg):
            ContentUnavailableView(
                "Couldn't Load Commissions",
                systemImage: "exclamationmark.triangle",
                description: Text(msg)
            )
        default:
            EmptyView()
        }
    }
}

// MARK: - CommissionRow

private struct CommissionRow: View {
    let commission: EmployeeCommission

    private static let isoFormatter = ISO8601DateFormatter()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f
    }()

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(orderLabel)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(dateLabel)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Text(formattedAmount)
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOrange)
                .monospacedDigit()
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var orderLabel: String {
        if let orderId = commission.ticketOrderId { return "Ticket #\(orderId)" }
        if let orderId = commission.invoiceOrderId { return "Invoice #\(orderId)" }
        return "Commission #\(commission.id)"
    }

    private var dateLabel: String {
        guard let date = Self.isoFormatter.date(from: commission.createdAt) else {
            return String(commission.createdAt.prefix(10))
        }
        return Self.dateFormatter.string(from: date)
    }

    private var formattedAmount: String {
        Self.currencyFormatter.string(from: NSNumber(value: commission.amount)) ?? "$\(commission.amount)"
    }

    private var accessibilityLabel: String {
        "\(orderLabel). Earned \(formattedAmount) on \(dateLabel)."
    }
}

// MARK: - CommissionDetailPanel (iPad)

private struct CommissionDetailPanel: View {
    let commission: EmployeeCommission

    private static let isoFormatter = ISO8601DateFormatter()
    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                amountCard
                detailsSection
            }
            .padding(BrandSpacing.lg)
        }
        .navigationTitle(orderTitle)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var amountCard: some View {
        VStack(spacing: BrandSpacing.sm) {
            Text("Commission Earned")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(formattedAmount)
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Commission earned: \(formattedAmount)")
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            detailRow(label: "Date", value: dateTimeLabel)
            if let orderId = commission.ticketOrderId {
                detailRow(label: "Ticket", value: "#\(orderId)")
            }
            if let orderId = commission.invoiceOrderId {
                detailRow(label: "Invoice", value: "#\(orderId)")
            }
            detailRow(label: "Record #", value: "\(commission.id)")
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(value)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var orderTitle: String {
        if let orderId = commission.ticketOrderId { return "Ticket #\(orderId)" }
        if let orderId = commission.invoiceOrderId { return "Invoice #\(orderId)" }
        return "Commission #\(commission.id)"
    }

    private var dateTimeLabel: String {
        guard let date = Self.isoFormatter.date(from: commission.createdAt) else {
            return commission.createdAt
        }
        return Self.dateTimeFormatter.string(from: date)
    }

    private var formattedAmount: String {
        Self.currencyFormatter.string(from: NSNumber(value: commission.amount)) ?? "$\(commission.amount)"
    }
}
