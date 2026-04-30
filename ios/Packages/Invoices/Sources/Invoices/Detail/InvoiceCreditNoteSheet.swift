#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §7.2 Credit note from invoice detail
// Endpoint: POST /api/v1/invoices/:id/credit-note  { amount, reason }

@MainActor
@Observable
final class InvoiceCreditNoteViewModel {
    var amountString: String = ""
    var amountCents: Int = 0
    var reason: String = ""

    enum State: Sendable, Equatable {
        case idle, submitting, success(referenceNumber: String?), failed(String)
    }
    var state: State = .idle

    @ObservationIgnored private let api: APIClient
    let invoiceId: Int64
    /// Maximum creditable = amount paid on the invoice (cents)
    let maxCents: Int

    init(api: APIClient, invoiceId: Int64, maxCents: Int) {
        self.api = api
        self.invoiceId = invoiceId
        self.maxCents = maxCents
        self.amountCents = maxCents
        self.amountString = String(format: "%.2f", Double(maxCents) / 100.0)
    }

    var isValid: Bool {
        amountCents > 0
            && amountCents <= maxCents
            && !reason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func updateAmount(from s: String) {
        amountString = s
        if let d = Double(s.filter { $0.isNumber || $0 == "." }) {
            amountCents = Int((d * 100).rounded())
        }
    }

    func submit() async {
        guard isValid, case .idle = state else { return }
        state = .submitting
        do {
            let amount = Double(amountCents) / 100.0
            let resp = try await api.issueInvoiceCreditNote(invoiceId: invoiceId, amount: amount, reason: reason)
            state = .success(referenceNumber: resp.referenceNumber)
            BrandHaptics.success()
        } catch {
            AppLog.ui.error("Issue credit note failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    func reset() {
        if case .failed = state { state = .idle }
    }
}

// MARK: - Sheet

public struct InvoiceCreditNoteSheet: View {
    @State private var vm: InvoiceCreditNoteViewModel
    let onDone: () -> Void

    public init(api: APIClient, invoiceId: Int64, maxCents: Int, onDone: @escaping () -> Void) {
        _vm = State(wrappedValue: InvoiceCreditNoteViewModel(api: api, invoiceId: invoiceId, maxCents: maxCents))
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.base) {
                        if case .success(let ref) = vm.state {
                            successView(ref: ref)
                        } else {
                            formView
                        }
                    }
                    .padding(BrandSpacing.base)
                }
            }
            .navigationTitle("Issue Credit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDone() }
                }
                if case .success = vm.state {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { onDone() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Form

    private var formView: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.base) {
            // Amount
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Amount")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                TextField("0.00", text: Binding(
                    get: { vm.amountString },
                    set: { vm.updateAmount(from: $0) }
                ))
                .keyboardType(.decimalPad)
                .font(.brandTitleMedium())
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Credit note amount in dollars")

                Text("Max: \(formatMoney(Double(vm.maxCents) / 100.0))")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            // Reason
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Reason")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                TextField("Enter reason for credit note", text: $vm.reason, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(BrandSpacing.sm)
                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Reason for credit note")
            }

            // Error
            if case .failed(let msg) = vm.state {
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .multilineTextAlignment(.center)
            }

            // Submit
            Button {
                Task { await vm.submit() }
            } label: {
                Group {
                    if case .submitting = vm.state {
                        ProgressView().tint(.black)
                    } else {
                        Text("Issue Credit Note")
                    }
                }
                .font(.brandBodyLarge().bold())
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(BrandSpacing.sm)
                .background(vm.isValid ? Color.bizarreOrange : Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 10))
            }
            .disabled(!vm.isValid || (vm.state == .submitting))
            .accessibilityLabel("Issue credit note")
        }
    }

    // MARK: - Success

    private func successView(ref: String?) -> some View {
        VStack(spacing: BrandSpacing.base) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
            Text("Credit Note Issued")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            if let ref {
                Text(ref)
                    .font(.brandMono(size: 18))
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                    .accessibilityLabel("Reference number \(ref)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(BrandSpacing.xxl)
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}
#endif
