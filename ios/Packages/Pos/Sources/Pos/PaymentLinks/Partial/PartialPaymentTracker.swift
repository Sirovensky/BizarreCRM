#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §41.4 Partial payment tracker

/// Shows payment history + remaining balance for a payment link.
/// Displayed from `PaymentLinkDetailView` when the link is partially paid or
/// past due.
public struct PartialPaymentTracker: View {
    @State private var vm: PartialPaymentTrackerViewModel

    public init(link: PaymentLink, api: APIClient) {
        _vm = State(wrappedValue: PartialPaymentTrackerViewModel(link: link, api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Payment history")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.payments.isEmpty {
            ProgressView()
        } else {
            list
        }
    }

    private var list: some View {
        List {
            Section {
                balanceSummary
            }
            Section("Payments") {
                if vm.payments.isEmpty {
                    Text("No payments recorded yet.")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .font(.brandBodyMedium())
                } else {
                    ForEach(vm.payments) { payment in
                        PartialPaymentRow(payment: payment)
                            .listRowBackground(Color.bizarreSurface1)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(vm.a11yLabel(for: payment))
                    }
                }
            }
            if vm.isOverdueAndUnderpaid {
                Section {
                    HStack(spacing: BrandSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading) {
                            Text("Past due")
                                .font(.brandLabelLarge())
                                .foregroundStyle(.bizarreOnSurface)
                            Text("Remaining balance \(CartMath.formatCents(vm.remainingCents)) is past the link expiry.")
                                .font(.brandBodySmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                    .listRowBackground(Color.bizarreSurface1)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var balanceSummary: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("Total amount")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .font(.brandBodyMedium())
                Spacer()
                Text(CartMath.formatCents(vm.link.amountCents))
                    .font(.brandTitleSmall())
                    .monospacedDigit()
            }
            HStack {
                Text("Paid so far")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .font(.brandBodyMedium())
                Spacer()
                Text(CartMath.formatCents(vm.paidCents))
                    .font(.brandTitleSmall())
                    .foregroundStyle(.green)
                    .monospacedDigit()
            }
            Divider()
            HStack {
                Text("Remaining")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text(CartMath.formatCents(vm.remainingCents))
                    .font(.brandTitleMedium())
                    .foregroundStyle(vm.remainingCents > 0 ? .bizarreOrange : .green)
                    .monospacedDigit()
            }
            ProgressView(value: vm.paidFraction)
                .tint(.green)
                .accessibilityLabel("Paid \(Int(vm.paidFraction * 100))%")
        }
        .padding(.vertical, BrandSpacing.xs)
    }
}

// MARK: - Row

struct PartialPaymentRow: View {
    let payment: PartialPayment

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(CartMath.formatCents(payment.amountCents))
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                Text(payment.paidAt)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            if let method = payment.method {
                Text(method.uppercased())
                    .font(.brandLabelSmall())
                    .foregroundStyle(.white)
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, 3)
                    .background(Color.bizarreOrange, in: Capsule())
            }
        }
        .padding(.vertical, BrandSpacing.xs)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class PartialPaymentTrackerViewModel {
    public private(set) var payments: [PartialPayment] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    public let link: PaymentLink
    private let api: APIClient

    public init(link: PaymentLink, api: APIClient) {
        self.link = link
        self.api = api
    }

    public var paidCents: Int { payments.reduce(0) { $0 + $1.amountCents } }
    public var remainingCents: Int { max(0, link.amountCents - paidCents) }
    public var paidFraction: Double {
        guard link.amountCents > 0 else { return 0 }
        return min(1, Double(paidCents) / Double(link.amountCents))
    }

    public var isOverdueAndUnderpaid: Bool {
        guard remainingCents > 0, let expiresAt = link.expiresAt else { return false }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        guard let expiry = fmt.date(from: expiresAt) else { return false }
        return expiry < Date()
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            payments = try await api.listPartialPayments(linkId: link.id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not load payment history."
        }
    }

    public func a11yLabel(for payment: PartialPayment) -> String {
        "\(CartMath.formatCents(payment.amountCents)) paid on \(payment.paidAt)"
    }
}
#endif
