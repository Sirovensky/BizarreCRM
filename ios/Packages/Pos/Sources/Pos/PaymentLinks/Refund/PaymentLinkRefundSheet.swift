#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §41.5 Refund from link

/// Admin sheet: refund a paid payment link. Mirrors the `PosRefundSheet` /
/// `InvoiceRefundSheet` pattern from Phase 4D.
/// Endpoint: `POST /payment-links/:id/refund`.
public struct PaymentLinkRefundSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: PaymentLinkRefundViewModel

    public init(link: PaymentLink, api: APIClient) {
        _vm = State(wrappedValue: PaymentLinkRefundViewModel(link: link, api: api))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                form
            }
            .navigationTitle("Refund payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Refund issued", isPresented: $vm.showSuccess) {
                Button("Done") { dismiss() }
            } message: {
                Text("A refund of \(CartMath.formatCents(vm.refundCents)) has been submitted.")
            }
            .alert("Error", isPresented: $vm.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "Could not process refund.")
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var form: some View {
        Form {
            Section("Payment link") {
                LabeledContent("Amount", value: CartMath.formatCents(vm.link.amountCents))
                    .font(.brandBodyMedium())
                if let desc = vm.link.description {
                    LabeledContent("Memo", value: desc)
                        .font(.brandBodyMedium())
                }
            }

            Section {
                HStack {
                    Text("Refund amount")
                    Spacer()
                    TextField("0", value: $vm.refundCents, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .frame(width: 80)
                        .accessibilityLabel("Refund amount in cents")
                }
                Text("Max refundable: \(CartMath.formatCents(vm.maxRefundable))")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } header: {
                Text("Refund amount (cents)")
            }

            Section("Reason") {
                Picker("Reason", selection: $vm.reason) {
                    ForEach(PaymentLinkRefundViewModel.Reason.allCases, id: \.self) { r in
                        Text(r.label).tag(r)
                    }
                }
                if vm.reason == .other {
                    TextField("Explain reason", text: $vm.customReason, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityLabel("Custom refund reason")
                }
            }

            Section {
                Button {
                    BrandHaptics.tapMedium()
                    Task { await vm.submit() }
                } label: {
                    HStack(spacing: BrandSpacing.sm) {
                        if vm.isSubmitting { ProgressView() }
                        Text(vm.isSubmitting ? "Processing…" : "Issue refund")
                            .font(.brandTitleSmall())
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(!vm.canSubmit)
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("paymentLink.refund.submitButton")
            }
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Refund request

public struct PaymentLinkRefundRequest: Encodable, Sendable {
    public let amountCents: Int
    public let reason: String

    enum CodingKeys: String, CodingKey {
        case amountCents = "amount_cents"
        case reason
    }
}

// MARK: - APIClient extension

public extension APIClient {
    /// `POST /payment-links/:id/refund`
    func refundPaymentLink(linkId: Int64, request: PaymentLinkRefundRequest) async throws {
        _ = try await post(
            "/api/v1/payment-links/\(linkId)/refund",
            body: request,
            as: EmptyResponse.self
        )
    }
}

/// Placeholder for void-response calls.
private struct EmptyResponse: Decodable, Sendable {}

// MARK: - ViewModel

@MainActor
@Observable
public final class PaymentLinkRefundViewModel {
    public enum Reason: String, CaseIterable, Sendable {
        case duplicate
        case customerRequest = "customer_request"
        case fraudulent
        case other

        public var label: String {
            switch self {
            case .duplicate:        return "Duplicate charge"
            case .customerRequest:  return "Customer request"
            case .fraudulent:       return "Fraudulent"
            case .other:            return "Other"
            }
        }
    }

    public let link: PaymentLink
    public var refundCents: Int
    public var reason: Reason = .customerRequest
    public var customReason: String = ""

    public private(set) var isSubmitting: Bool = false
    public var showSuccess: Bool = false
    public var showError: Bool = false
    public private(set) var errorMessage: String?

    private let api: APIClient

    public init(link: PaymentLink, api: APIClient) {
        self.link = link
        self.refundCents = link.amountCents
        self.api = api
    }

    public var maxRefundable: Int { link.amountCents }

    public var canSubmit: Bool {
        !isSubmitting
        && refundCents > 0
        && refundCents <= maxRefundable
        && (reason != .other || !customReason.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    public func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let reasonString = reason == .other ? customReason : reason.rawValue
        let req = PaymentLinkRefundRequest(amountCents: refundCents, reason: reasonString)
        do {
            try await api.refundPaymentLink(linkId: link.id, request: req)
            BrandHaptics.success()
            showSuccess = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not process refund."
            showError = true
        }
    }
}
#endif
