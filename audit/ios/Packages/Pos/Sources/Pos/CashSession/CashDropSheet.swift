#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §16.10 — Mid-shift "Cash Drop" sheet.
///
/// Allows a manager to remove excess cash from the drawer without closing
/// the shift. This is also known as a "safe drop" or "cash pull". The
/// action is logged via `POST /pos/cash-out` so it appears in the Z-report
/// cash-out section.
///
/// The cashier signature is captured as a typed name field (MVP).
/// An actual handwritten PKCanvasView signature is deferred to Phase 5.
///
/// Role gate: caller should present this sheet only for `pos.cash_drop`
/// role (checked at the call site via `ManagerPinSheet`).
@MainActor
public struct CashDropSheet: View {

    /// Called when the cash drop is recorded.
    /// - Parameters:
    ///   - amountCents: Amount pulled from the drawer.
    ///   - reason: Free-text reason / signature.
    public let onConfirm: (_ amountCents: Int, _ reason: String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String = ""
    @State private var reason: String = ""
    @State private var signature: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?
    @FocusState private var amountFocused: Bool

    public init(onConfirm: @escaping (_ amountCents: Int, _ reason: String) -> Void) {
        self.onConfirm = onConfirm
    }

    // MARK: - Computed

    private var amountCents: Int {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        if trimmed.contains(".") {
            guard let v = Double(trimmed), v >= 0 else { return 0 }
            return Int((v * 100).rounded())
        } else {
            guard let v = Int(trimmed), v >= 0 else { return 0 }
            return v * 100
        }
    }

    private var canSubmit: Bool {
        amountCents > 0 &&
        !signature.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var combinedReason: String {
        var parts = ["Cash drop"]
        let r = reason.trimmingCharacters(in: .whitespaces)
        let s = signature.trimmingCharacters(in: .whitespaces)
        if !r.isEmpty { parts.append(r) }
        if !s.isEmpty { parts.append("Signed: \(s)") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Form {
                Section("Amount to remove from drawer") {
                    HStack(spacing: BrandSpacing.sm) {
                        Text("$")
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .focused($amountFocused)
                            .accessibilityLabel("Drop amount in dollars")
                            .accessibilityIdentifier("pos.cashDrop.amount")
                    }
                    if amountCents > 0 {
                        Text(CartMath.formatCents(amountCents) + " will be removed from the drawer")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }

                Section {
                    TextField("e.g. excess to safe, manager override", text: $reason, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityLabel("Reason for cash drop")
                        .accessibilityIdentifier("pos.cashDrop.reason")
                } header: {
                    Text("Reason")
                }

                Section {
                    TextField("Cashier name or initials *", text: $signature)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Cashier signature — type name or initials")
                        .accessibilityIdentifier("pos.cashDrop.signature")
                } header: {
                    Text("Cashier signature (required)")
                } footer: {
                    Text("Full handwritten-signature capture lands in Phase 5.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Cash drop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Recording…" : "Record") {
                        Task { await commit() }
                    }
                    .disabled(!canSubmit || isSubmitting)
                    .accessibilityIdentifier("pos.cashDrop.record")
                }
            }
        }
        .onAppear { amountFocused = true }
    }

    // MARK: - Commit

    private func commit() async {
        guard canSubmit, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        BrandHaptics.success()
        AppLog.pos.info("Cash drop: \(amountCents)c reason=\(combinedReason)")
        onConfirm(amountCents, combinedReason)
        dismiss()
    }
}

// MARK: - Preview

#Preview("Cash drop") {
    CashDropSheet { amount, reason in
        print("Drop: \(amount)c reason=\(reason)")
    }
    .preferredColorScheme(.dark)
}
#endif
