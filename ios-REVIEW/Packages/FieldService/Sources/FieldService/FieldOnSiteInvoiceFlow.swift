// §57.3 FieldOnSiteInvoiceFlow — launches POS in "field mode" with
// pre-filled customer + service lines from the appointment.
// Uses existing ChargeCoordinator (Phase 5 C) from Hardware package.
// No new terminal SDK — delegates to ChargeCoordinator.

import SwiftUI
import Networking
import DesignSystem

// MARK: - FieldInvoiceContext

/// Context passed from field dispatch to the on-site invoice flow.
public struct FieldInvoiceContext: Sendable {
    public let appointmentId: Int64
    public let customerId: Int64
    public let customerName: String
    public let serviceLines: [ServiceLine]
    public let totalCents: Int

    public init(
        appointmentId: Int64,
        customerId: Int64,
        customerName: String,
        serviceLines: [ServiceLine],
        totalCents: Int
    ) {
        self.appointmentId = appointmentId
        self.customerId = customerId
        self.customerName = customerName
        self.serviceLines = serviceLines
        self.totalCents = totalCents
    }
}

public struct ServiceLine: Identifiable, Sendable {
    public let id: UUID
    public let description: String
    public let amountCents: Int

    public init(id: UUID = UUID(), description: String, amountCents: Int) {
        self.id = id
        self.description = description
        self.amountCents = amountCents
    }
}

// MARK: - FieldOnSiteInvoiceFlow

/// §57.3 — Full-screen invoice + charge flow for field technicians.
///
/// Shows itemised service lines pre-filled from the appointment, then
/// initiates a BlockChyp card charge via `ChargeCoordinator`. After
/// successful charge, presents `FieldReceiptDeliverySheet`.
@MainActor
@Observable
public final class FieldOnSiteInvoiceViewModel {

    public enum State: Sendable {
        case reviewing
        case charging
        case charged(transactionId: String)
        case failed(String)
    }

    public private(set) var state: State = .reviewing
    public let context: FieldInvoiceContext

    @ObservationIgnored private let chargeHandler: @Sendable (Int) async throws -> String

    public init(
        context: FieldInvoiceContext,
        chargeHandler: @escaping @Sendable (Int) async throws -> String
    ) {
        self.context = context
        self.chargeHandler = chargeHandler
    }

    public func chargeCard() async {
        state = .charging
        do {
            let txnId = try await chargeHandler(context.totalCents)
            state = .charged(transactionId: txnId)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func retryReset() {
        state = .reviewing
    }
}

// MARK: - FieldOnSiteInvoiceView

public struct FieldOnSiteInvoiceView: View {

    @State private var vm: FieldOnSiteInvoiceViewModel
    @State private var showReceipt = false
    @State private var transactionId: String = ""

    public init(vm: FieldOnSiteInvoiceViewModel) {
        _vm = State(wrappedValue: vm)
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("On-Site Invoice")
                #if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
        .sheet(isPresented: $showReceipt) {
            FieldReceiptDeliverySheet(
                transactionId: transactionId,
                customerName: vm.context.customerName
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .reviewing:
            reviewView
        case .charging:
            VStack(spacing: DesignTokens.Spacing.lg) {
                ProgressView("Processing payment…")
                    .font(.brandBodyMedium())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .charged(let txnId):
            VStack(spacing: DesignTokens.Spacing.lg) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.bizarreSuccess)
                Text("Payment Accepted")
                    .font(.brandTitleMedium())
                Button("Send Receipt") {
                    transactionId = txnId
                    showReceipt = true
                }
                .buttonStyle(.brandGlassProminent)
                .tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let msg):
            VStack(spacing: DesignTokens.Spacing.lg) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.bizarreError)
                Text(msg)
                    .font(.brandBodyMedium())
                    .multilineTextAlignment(.center)
                Button("Retry") { vm.retryReset() }
                    .buttonStyle(.brandGlassProminent)
                    .tint(.bizarreOrange)
            }
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Review view

    private var reviewView: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            customerHeader
            serviceLineList
            Divider()
            totalRow
            Spacer()
            chargeButton
        }
        .padding(DesignTokens.Spacing.xl)
    }

    private var customerHeader: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text("Bill To")
                .font(.brandLabelSmall())
                .foregroundStyle(.secondary)
            Text(vm.context.customerName)
                .font(.brandTitleMedium())
        }
    }

    private var serviceLineList: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Services")
                .font(.brandLabelSmall())
                .foregroundStyle(.secondary)
            ForEach(vm.context.serviceLines) { line in
                HStack {
                    Text(line.description)
                        .font(.brandBodyMedium())
                    Spacer()
                    Text(formatCents(line.amountCents))
                        .font(.brandBodyMedium())
                        .monospacedDigit()
                }
            }
        }
    }

    private var totalRow: some View {
        HStack {
            Text("Total")
                .font(.brandTitleMedium())
            Spacer()
            Text(formatCents(vm.context.totalCents))
                .font(.brandTitleMedium())
                .monospacedDigit()
        }
    }

    private var chargeButton: some View {
        Button {
            Task { await vm.chargeCard() }
        } label: {
            Label("Charge \(formatCents(vm.context.totalCents))",
                  systemImage: "creditcard.fill")
        }
        .buttonStyle(.brandGlassProminent)
        .tint(.bizarreOrange)
    }

    // MARK: - Helpers

    private func formatCents(_ cents: Int) -> String {
        let value = Double(cents) / 100.0
        return String(format: "$%.2f", value)
    }
}
