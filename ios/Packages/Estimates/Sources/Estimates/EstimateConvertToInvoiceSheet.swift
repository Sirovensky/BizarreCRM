#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §8.2 Convert Estimate to Invoice
//
// Server route:
//   POST /api/v1/estimates/:id/convert-to-invoice
//   Response: { success, data: { invoice_id } }
//
// Route confirmed in packages/server/src/routes/estimates.routes.ts.

// MARK: - ConvertToInvoiceResponse

struct ConvertToInvoiceResponse: Decodable, Sendable {
    let invoiceId: Int64
    enum CodingKeys: String, CodingKey { case invoiceId = "invoice_id" }
}

// MARK: - EstimateConvertToInvoiceViewModel

@MainActor
@Observable
final class EstimateConvertToInvoiceViewModel {
    var isSubmitting: Bool = false
    var errorMessage: String?
    var convertedInvoiceId: Int64?

    private let api: APIClient
    let estimateId: Int64
    let orderId: String

    init(api: APIClient, estimateId: Int64, orderId: String) {
        self.api = api
        self.estimateId = estimateId
        self.orderId = orderId
    }

    func convert() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let resp = try await api.post(
                "/api/v1/estimates/\(estimateId)/convert-to-invoice",
                body: EmptyBody(),
                as: ConvertToInvoiceResponse.self
            )
            convertedInvoiceId = resp.invoiceId
            AppLog.ui.info("Estimate \(estimateId) converted to invoice \(resp.invoiceId).")
        } catch {
            errorMessage = AppError.from(error).errorDescription ?? error.localizedDescription
            AppLog.ui.error("Estimate convert-to-invoice failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// Sentinel empty body for POSTs without a payload.
private struct EmptyBody: Encodable {}

// MARK: - EstimateConvertToInvoiceSheet

/// §8.2: One-tap confirmation sheet to convert an estimate to an invoice.
/// On success the `onSuccess` closure receives the new invoice id so the
/// caller can navigate to it.
public struct EstimateConvertToInvoiceSheet: View {
    private let estimate: Estimate
    private let api: APIClient
    private let onSuccess: @MainActor (Int64) -> Void

    @State private var vm: EstimateConvertToInvoiceViewModel
    @Environment(\.dismiss) private var dismiss

    public init(
        estimate: Estimate,
        api: APIClient,
        onSuccess: @escaping @MainActor (Int64) -> Void = { _ in }
    ) {
        self.estimate = estimate
        self.api = api
        self.onSuccess = onSuccess
        _vm = State(wrappedValue: EstimateConvertToInvoiceViewModel(
            api: api,
            estimateId: estimate.id,
            orderId: estimate.orderId ?? "EST-?"
        ))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.xl) {
                    Spacer()

                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)

                    VStack(spacing: BrandSpacing.sm) {
                        Text("Convert to Invoice")
                            .font(.brandTitleLarge())
                            .foregroundStyle(.bizarreOnSurface)
                        Text("This will create a new invoice from \(estimate.orderId ?? "this estimate"). The estimate will be marked as converted.")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, BrandSpacing.xl)
                    }

                    // Summary row
                    HStack {
                        VStack(alignment: .leading) {
                            Text(estimate.customerName)
                                .font(.brandBodyLarge())
                                .foregroundStyle(.bizarreOnSurface)
                        }
                        Spacer()
                        Text(formatMoney(estimate.total ?? 0))
                            .font(.brandTitleMedium())
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                    }
                    .padding(BrandSpacing.lg)
                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                    .padding(.horizontal, BrandSpacing.lg)

                    if let err = vm.errorMessage {
                        Text(err)
                            .font(.brandLabelMedium())
                            .foregroundStyle(.bizarreError)
                            .padding(.horizontal, BrandSpacing.lg)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await vm.convert() }
                    } label: {
                        Group {
                            if vm.isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Convert to Invoice")
                                    .font(.brandBodyLarge())
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BrandSpacing.md)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)
                    .disabled(vm.isSubmitting)
                    .padding(.horizontal, BrandSpacing.lg)
                    .accessibilityLabel(vm.isSubmitting ? "Converting…" : "Convert estimate to invoice")

                    Button("Cancel") { dismiss() }
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .disabled(vm.isSubmitting)

                    Spacer()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: vm.convertedInvoiceId) { _, invoiceId in
                if let id = invoiceId {
                    onSuccess(id)
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

#endif
