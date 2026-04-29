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

// MARK: - EstimateConvertToInvoiceViewModel (§8 item 5: polished flow)

@MainActor
@Observable
final class EstimateConvertToInvoiceViewModel {
    var isSubmitting: Bool = false
    var errorMessage: String?
    var convertedInvoiceId: Int64?
    /// §8 item 5: optional due date the staff sets before converting.
    var dueDate: Date = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    var showDueDatePicker: Bool = false

    private let api: APIClient
    let estimateId: Int64
    let orderId: String

    init(api: APIClient, estimateId: Int64, orderId: String) {
        self.api = api
        self.estimateId = estimateId
        self.orderId = orderId
    }

    var dueDateFormatted: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: dueDate)
    }

    func convert() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            // §8 item 5: pass due_date to the server so the created invoice has a due date.
            struct ConvertBody: Encodable {
                let dueDate: String
                enum CodingKeys: String, CodingKey { case dueDate = "due_date" }
            }
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withFullDate]
            let body = ConvertBody(dueDate: isoFormatter.string(from: dueDate))
            let resp = try await api.post(
                "/api/v1/estimates/\(estimateId)/convert-to-invoice",
                body: body,
                as: ConvertToInvoiceResponse.self
            )
            convertedInvoiceId = resp.invoiceId
            AppLog.ui.info("Estimate \(self.estimateId) converted to invoice \(resp.invoiceId) due \(isoFormatter.string(from: self.dueDate)).")
        } catch {
            errorMessage = AppError.from(error).errorDescription ?? error.localizedDescription
            AppLog.ui.error("Estimate convert-to-invoice failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// Sentinel empty body for POSTs without a payload.
private struct EmptyBody: Encodable {}

// MARK: - EstimateConvertToInvoiceSheet (§8 item 5: polished flow)

/// §8.2 + §8 item 5: Convert-estimate-to-invoice sheet.
/// Polished flow adds:
///   - Due-date picker (defaults to 30 days out)
///   - Line-items preview (up to 3 rows + overflow count)
///   - Inline success state with invoice ID before auto-dismiss
public struct EstimateConvertToInvoiceSheet: View {
    private let estimate: Estimate
    private let api: APIClient
    private let onSuccess: @MainActor (Int64) -> Void

    @State private var vm: EstimateConvertToInvoiceViewModel
    @State private var showSuccess: Bool = false
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
                if showSuccess {
                    successState
                } else {
                    confirmationForm
                }
            }
            .navigationTitle("Convert to Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !showSuccess {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(vm.isSubmitting)
                            .accessibilityLabel("Cancel conversion")
                    }
                }
            }
            .onChange(of: vm.convertedInvoiceId) { _, invoiceId in
                if invoiceId != nil {
                    withAnimation { showSuccess = true }
                    // Auto-dismiss after brief success display
                    Task {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        if let id = invoiceId {
                            onSuccess(id)
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Confirmation form

    private var confirmationForm: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                // Header icon + description
                VStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                    Text("Convert to Invoice")
                        .font(.brandTitleLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Creates a new invoice from \(estimate.orderId ?? "this estimate"). The estimate will be marked as converted.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, BrandSpacing.lg)

                // Customer + total summary
                HStack {
                    VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                        Text(estimate.customerName)
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOnSurface)
                        Text(estimate.orderId ?? "EST-?")
                            .font(.brandMono(size: 13))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    Spacer()
                    Text(formatMoney(estimate.total ?? 0))
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }
                .padding(BrandSpacing.lg)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Customer: \(estimate.customerName). Total: \(formatMoney(estimate.total ?? 0))")

                // §8 item 5: Line items preview (up to 3 + overflow label)
                if let items = estimate.lineItems, !items.isEmpty {
                    lineItemsPreview(items)
                }

                // §8 item 5: Due date picker
                dueDateSection

                if let err = vm.errorMessage {
                    HStack(spacing: BrandSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.bizarreError)
                            .accessibilityHidden(true)
                        Text(err)
                            .font(.brandLabelMedium())
                            .foregroundStyle(.bizarreError)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(BrandSpacing.md)
                    .background(Color.bizarreError.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    .accessibilityLabel("Error: \(err)")
                }

                Button {
                    Task { await vm.convert() }
                } label: {
                    Group {
                        if vm.isSubmitting {
                            ProgressView().tint(.white)
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
                .accessibilityLabel(vm.isSubmitting ? "Converting…" : "Convert estimate to invoice")

                Button("Cancel") { dismiss() }
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .disabled(vm.isSubmitting)

                Spacer(minLength: BrandSpacing.xl)
            }
            .padding(.horizontal, BrandSpacing.lg)
        }
    }

    // MARK: - §8 item 5: Line items preview

    @ViewBuilder
    private func lineItemsPreview(_ items: [EstimateLineItem]) -> some View {
        let previewItems = Array(items.prefix(3))
        let overflow = items.count - previewItems.count

        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Line Items")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)

            ForEach(previewItems) { item in
                HStack {
                    Text(item.description ?? item.itemName ?? "Item")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    Spacer()
                    if let total = item.total {
                        Text(formatMoney(total))
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.description ?? item.itemName ?? "Item")\(item.total.map { ": \(formatMoney($0))" } ?? "")")
            }

            if overflow > 0 {
                Text("+ \(overflow) more item\(overflow == 1 ? "" : "s")")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    // MARK: - §8 item 5: Due date picker section

    private var dueDateSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Invoice Due Date")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)

            Button {
                withAnimation { vm.showDueDatePicker.toggle() }
            } label: {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                    Text(vm.dueDateFormatted)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    Image(systemName: vm.showDueDatePicker ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                }
                .padding(BrandSpacing.md)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Invoice due date: \(vm.dueDateFormatted). Tap to change.")

            if vm.showDueDatePicker {
                DatePicker(
                    "Due Date",
                    selection: $vm.dueDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(.bizarreOrange)
                .accessibilityLabel("Select invoice due date")
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - §8 item 5: Success state

    private var successState: some View {
        VStack(spacing: BrandSpacing.lg) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            VStack(spacing: BrandSpacing.sm) {
                Text("Invoice Created")
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
                if let invoiceId = vm.convertedInvoiceId {
                    Text("Invoice #\(invoiceId) is ready")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Text("Opening now…")
                    .font(.brandLabelMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .multilineTextAlignment(.center)

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Invoice created successfully. Opening invoice now.")
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

#endif
