#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §7.13 Discount codes on invoice — reuses CouponCode + CouponInputViewModel pattern

// MARK: - InvoiceDiscountState (mirrors CouponInputState without Pos dependency)

/// Lifecycle of a discount code application attempt on an invoice.
public enum InvoiceDiscountState: Equatable, Sendable {
    case idle
    case loading
    /// Server accepted the code; discount amount in cents authorised.
    case applied(code: String, discountCents: Int, message: String?)
    case error(String)

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public var discountCents: Int {
        if case .applied(_, let d, _) = self { return d }
        return 0
    }

    public var appliedCode: String? {
        if case .applied(let c, _, _) = self { return c }
        return nil
    }
}

// MARK: - InvoiceDiscountApplyRequest

/// `POST /api/v1/invoices/:id/apply-discount`
public struct InvoiceDiscountApplyRequest: Encodable, Sendable {
    public let code: String
    public init(code: String) { self.code = code }
}

/// Server response for the discount apply call.
public struct InvoiceDiscountApplyResponse: Decodable, Sendable {
    public let code: String
    public let discountCents: Int
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case code, message
        case discountCents = "discount_cents"
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class InvoiceDiscountInputViewModel {

    public var codeInput: String = "" {
        didSet {
            codeInput = codeInput.uppercased()
            if case .error = state { state = .idle }
        }
    }

    public private(set) var state: InvoiceDiscountState = .idle

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let invoiceId: Int64

    public init(api: APIClient, invoiceId: Int64) {
        self.api = api
        self.invoiceId = invoiceId
    }

    public var canApply: Bool {
        !codeInput.trimmingCharacters(in: .whitespaces).isEmpty
            && !state.isLoading
            && state.appliedCode == nil
    }

    public var isApplied: Bool { state.appliedCode != nil }

    public func apply() async {
        let trimmed = codeInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            state = .error("Enter a discount code.")
            return
        }
        state = .loading
        let req = InvoiceDiscountApplyRequest(code: trimmed)
        do {
            let resp = try await api.post(
                "/api/v1/invoices/\(invoiceId)/apply-discount",
                body: req,
                as: InvoiceDiscountApplyResponse.self
            )
            state = .applied(
                code: resp.code,
                discountCents: resp.discountCents,
                message: resp.message
            )
            BrandHaptics.success()
        } catch let appError as AppError {
            state = .error(appError.errorDescription ?? appError.localizedDescription)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    public func remove() {
        codeInput = ""
        state = .idle
    }
}

// MARK: - Sheet

public struct InvoiceDiscountInputSheet: View {
    @State private var vm: InvoiceDiscountInputViewModel
    @Environment(\.dismiss) private var dismiss
    private let onApplied: (Int) -> Void  // discount cents

    public init(api: APIClient, invoiceId: Int64, onApplied: @escaping (Int) -> Void) {
        _vm = State(wrappedValue: InvoiceDiscountInputViewModel(api: api, invoiceId: invoiceId))
        self.onApplied = onApplied
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: BrandSpacing.lg) {
                Spacer()

                VStack(spacing: BrandSpacing.base) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)

                    Text("Enter Discount Code")
                        .font(.brandTitleLarge())
                        .foregroundStyle(.bizarreOnSurface)

                    Text("Enter a promotional code to apply a discount to this invoice.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BrandSpacing.lg)
                }

                HStack(spacing: BrandSpacing.sm) {
                    TextField("CODE", text: $vm.codeInput)
                        .textCase(.uppercase)
                        .autocorrectionDisabled()
                        .font(.brandMono(size: 20))
                        .multilineTextAlignment(.center)
                        .padding(BrandSpacing.base)
                        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(borderColor, lineWidth: 1.5)
                        )
                        .accessibilityLabel("Discount code input field")
                        .disabled(vm.isApplied)

                    if vm.isApplied {
                        Button {
                            vm.remove()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .font(.system(size: 24))
                        }
                        .accessibilityLabel("Remove discount code")
                    }
                }
                .padding(.horizontal, BrandSpacing.lg)

                // State feedback
                stateView

                Button(vm.isApplied ? "Applied!" : "Apply Code") {
                    Task { await vm.apply() }
                }
                .buttonStyle(.borderedProminent)
                .tint(vm.isApplied ? .bizarreSuccess : .bizarreOrange)
                .disabled(!vm.canApply)
                .accessibilityLabel(vm.isApplied ? "Discount applied" : "Apply discount code")

                Spacer()
            }
            .padding(BrandSpacing.base)
            .navigationTitle("Discount Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isApplied {
                        Button("Done") {
                            onApplied(vm.state.discountCents)
                            dismiss()
                        }
                        .accessibilityLabel("Confirm discount and close")
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var borderColor: Color {
        switch vm.state {
        case .applied:   return .bizarreSuccess
        case .error:     return .bizarreError
        default:         return Color.bizarreOutline.opacity(0.6)
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch vm.state {
        case .loading:
            ProgressView()
        case .applied(let code, let cents, let msg):
            VStack(spacing: BrandSpacing.xs) {
                Label("\(code) applied — \(formatMoney(cents)) off", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.bizarreSuccess)
                    .font(.brandBodyMedium())
                    .accessibilityLabel("Discount code \(code) applied, saving \(formatMoney(cents))")
                if let m = msg {
                    Text(m)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        case .error(let msg):
            Text(msg)
                .foregroundStyle(.bizarreError)
                .font(.brandBodyMedium())
                .multilineTextAlignment(.center)
                .accessibilityLabel("Error: \(msg)")
        case .idle:
            EmptyView()
        }
    }
}

private func formatMoney(_ cents: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(cents)"
}
#endif
