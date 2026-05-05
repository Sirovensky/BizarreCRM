import SwiftUI
import DesignSystem
import Networking

// MARK: - SubscriptionPaymentHistoryViewModel

/// §38.3 — VM for payment history of a single subscription.
///
/// Server route: `GET /membership/:id/payments`
/// Returns `[SubscriptionPaymentDTO]` inside the standard `{ success, data }` envelope.
@MainActor
@Observable
public final class SubscriptionPaymentHistoryViewModel {

    public enum State: Equatable, Sendable {
        case loading
        case loaded
        case empty
        case failed(String)
    }

    public private(set) var state: State = .loading
    public private(set) var payments: [SubscriptionPaymentDTO] = []

    private let api: any APIClient
    private let subscriptionId: Int

    public init(api: any APIClient, subscriptionId: Int) {
        self.api = api
        self.subscriptionId = subscriptionId
    }

    public func load() async {
        state = .loading
        payments = []
        do {
            let result = try await api.getMembershipPayments(id: subscriptionId)
            payments = result
            state = result.isEmpty ? .empty : .loaded
        } catch let t as APITransportError {
            state = .failed(t.localizedDescription)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func refresh() async { await load() }
}

// MARK: - SubscriptionPaymentHistoryView

/// §38.3 — Shows billing history for one customer subscription.
///
/// iPhone: `List` of payment rows (full-width, inset-grouped).
/// iPad: `Table` with sortable Amount / Status / Date columns.
///
/// Usage (from CustomerDetailView or MembershipDetailView):
/// ```swift
/// NavigationLink("Payment History") {
///     SubscriptionPaymentHistoryView(api: api, subscriptionId: sub.id)
/// }
/// ```
public struct SubscriptionPaymentHistoryView: View {

    @State private var vm: SubscriptionPaymentHistoryViewModel
    @Environment(\.horizontalSizeClass) private var hSizeClass

    public init(api: any APIClient, subscriptionId: Int) {
        _vm = State(wrappedValue: SubscriptionPaymentHistoryViewModel(
            api: api,
            subscriptionId: subscriptionId
        ))
    }

    public var body: some View {
        Group {
            switch vm.state {
            case .loading:
                ProgressView("Loading payment history…")
                    .accessibilityLabel("Loading payment history")
            case .empty:
                ContentUnavailableView(
                    "No Payments",
                    systemImage: "creditcard",
                    description: Text("No payment records found for this subscription.")
                )
            case .failed(let msg):
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(msg)
                )
            case .loaded:
                if hSizeClass == .regular {
                    iPadTable
                } else {
                    iPhoneList
                }
            }
        }
        .navigationTitle("Payment History")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await vm.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh payment history")
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.refresh() }
    }

    // MARK: - iPhone list

    private var iPhoneList: some View {
        List(vm.payments) { payment in
            PaymentRow(payment: payment)
                .accessibilityElement(children: .combine)
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    // MARK: - iPad table

    @ViewBuilder
    private var iPadTable: some View {
        Table(vm.payments) {
            TableColumn("Amount") { p in
                Text(formattedAmount(p.amount))
                    .font(.brandBodyMedium())
                    .fontDesign(.monospaced)
                    .textSelection(.enabled)
            }
            TableColumn("Status") { p in
                PaymentStatusChip(status: p.status)
            }
            TableColumn("Date") { p in
                if let dateStr = p.createdAt {
                    Text(formattedDate(dateStr))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                } else {
                    Text("—").foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
    }

    // MARK: - Formatters

    private func formattedAmount(_ amount: Double) -> String {
        String(format: "$%.2f", amount)
    }

    private func formattedDate(_ raw: String) -> String {
        // Server returns "YYYY-MM-DD HH:MM:SS" — trim time.
        let dateOnly = String(raw.prefix(10))
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        if let date = df.date(from: dateOnly) {
            df.dateStyle = .medium
            df.timeStyle = .none
            return df.string(from: date)
        }
        return raw
    }
}

// MARK: - PaymentRow

private struct PaymentRow: View {
    let payment: SubscriptionPaymentDTO

    private func formattedDate(_ raw: String) -> String {
        let dateOnly = String(raw.prefix(10))
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        if let date = df.date(from: dateOnly) {
            df.dateStyle = .medium
            df.timeStyle = .none
            return df.string(from: date)
        }
        return raw
    }

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(String(format: "$%.2f", payment.amount))
                    .font(.brandTitleSmall())
                    .fontDesign(.monospaced)
                    .foregroundStyle(.bizarreOnSurface)
                if let dateStr = payment.createdAt {
                    Text(formattedDate(dateStr))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer()
            PaymentStatusChip(status: payment.status)
        }
        .padding(.vertical, BrandSpacing.xxs)
    }
}

// MARK: - PaymentStatusChip

private struct PaymentStatusChip: View {
    let status: String

    private var chipColor: Color {
        switch status.lowercased() {
        case "success": return .bizarreSuccess
        case "failed":  return .bizarreError
        case "pending": return .bizarreWarning
        case "refunded": return .bizarreTeal
        default:        return .bizarreOnSurfaceMuted
        }
    }

    private var displayText: String {
        status.prefix(1).uppercased() + status.dropFirst()
    }

    var body: some View {
        Text(displayText)
            .font(.brandLabelSmall())
            .foregroundStyle(chipColor)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .background(Capsule().fill(chipColor.opacity(0.15)))
            .accessibilityLabel("Payment status: \(displayText)")
    }
}
