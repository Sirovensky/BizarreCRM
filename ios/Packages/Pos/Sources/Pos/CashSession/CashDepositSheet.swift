#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §39.5 — Cash deposit sheet.
///
/// Records a cash deposit into the drawer mid-shift (e.g., manager adds more
/// float after a busy period). Posted via `POST /pos/cash-in` so the Z-report
/// cash-in column stays accurate.
///
/// Role gate: caller should present via a `ManagerPinSheet` guard since
/// depositing cash into the drawer is a manager-level operation.
@MainActor
public struct CashDepositSheet: View {

    // MARK: - Callbacks
    /// Called when the deposit is confirmed.
    /// - Parameters:
    ///   - amountCents: Amount deposited.
    ///   - reason: Free-text reason / authorization note.
    public let onConfirm: (_ amountCents: Int, _ reason: String) -> Void

    // MARK: - State
    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String = ""
    @State private var source: String = ""
    @State private var notes: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?
    @FocusState private var amountFocused: Bool

    public init(onConfirm: @escaping (_ amountCents: Int, _ reason: String) -> Void) {
        self.onConfirm = onConfirm
    }

    // MARK: - Computed

    private var amountCents: Int {
        let t = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return 0 }
        if t.contains(".") {
            guard let v = Double(t), v >= 0 else { return 0 }
            return Int((v * 100).rounded())
        } else {
            guard let v = Int(t), v >= 0 else { return 0 }
            return v * 100
        }
    }

    private var canSubmit: Bool {
        amountCents > 0 && !isSubmitting
    }

    private var combinedReason: String {
        var parts = ["Cash deposit"]
        let s = source.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty { parts.append(s) }
        let n = notes.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { parts.append(n) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Form {
                // Amount
                Section {
                    HStack(spacing: BrandSpacing.sm) {
                        Text("$")
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .font(.brandHeadlineMedium())
                            .focused($amountFocused)
                            .accessibilityLabel("Deposit amount in dollars")
                            .accessibilityIdentifier("cashDeposit.amount")
                    }
                    if amountCents > 0 {
                        Text("\(CartMath.formatCents(amountCents)) will be added to the drawer")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreSuccess)
                    }
                } header: {
                    Text("Amount to deposit into drawer")
                }

                // Source
                Section {
                    TextField("e.g. Back-office safe, bank pickup", text: $source)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Source of funds")
                        .accessibilityIdentifier("cashDeposit.source")
                } header: {
                    Text("Source (optional)")
                }

                // Notes
                Section {
                    TextField("Authorization code, reference, or other notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityLabel("Deposit notes")
                        .accessibilityIdentifier("cashDeposit.notes")
                } header: {
                    Text("Notes")
                } footer: {
                    Text("This deposit appears as a cash-in entry on the Z-report.")
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
            .navigationTitle("Cash deposit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Record") { Task { await commit() } }
                            .disabled(!canSubmit)
                            .accessibilityIdentifier("cashDeposit.record")
                    }
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
        AppLog.pos.info("Cash deposit: \(amountCents)c source=\(source)")
        onConfirm(amountCents, combinedReason)
        dismiss()
    }
}

// MARK: - Preview

#Preview("Cash deposit") {
    CashDepositSheet { amount, reason in
        print("Deposit: \(amount)c reason=\(reason)")
    }
    .preferredColorScheme(.dark)
}
#endif
