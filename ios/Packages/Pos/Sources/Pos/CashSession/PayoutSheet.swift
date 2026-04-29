#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §39.5 — Payout sheet.
///
/// Records a cash payout from the drawer for business expenses (e.g., supply
/// run, petty-cash reimbursement). Distinct from a "cash drop" (which moves
/// money to the safe without an expense reason). The payout is posted via
/// `POST /pos/cash-out` with type=payout so it appears as its own line on
/// the Z-report.
///
/// Role gate: manager PIN required for payouts above `kPayoutManagerPinThresholdCents` ($50).
@MainActor
public struct PayoutSheet: View {

    // MARK: - Constants
    public static let kPayoutManagerPinThresholdCents = 5_000  // $50

    // MARK: - Callbacks
    /// Called when the payout is confirmed.
    /// - Parameters:
    ///   - amountCents: Amount paid out.
    ///   - reason: Combined reason/vendor/approver text.
    public let onConfirm: (_ amountCents: Int, _ reason: String) -> Void

    // MARK: - State
    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String = ""
    @State private var vendor: String = ""
    @State private var notes: String = ""
    @State private var approverName: String = ""
    @State private var isSubmitting: Bool = false
    @State private var showManagerPin: Bool = false
    @State private var managerApproved: Bool = false
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

    private var requiresManagerPin: Bool {
        amountCents >= Self.kPayoutManagerPinThresholdCents
    }

    private var canSubmit: Bool {
        amountCents > 0 &&
        !vendor.trimmingCharacters(in: .whitespaces).isEmpty &&
        (!requiresManagerPin || managerApproved) &&
        !isSubmitting
    }

    private var combinedReason: String {
        var parts = ["Payout", vendor.trimmingCharacters(in: .whitespaces)]
        let n = notes.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { parts.append(n) }
        let a = approverName.trimmingCharacters(in: .whitespaces)
        if !a.isEmpty { parts.append("Approved by: \(a)") }
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
                            .accessibilityLabel("Payout amount in dollars")
                            .accessibilityIdentifier("payout.amount")
                    }
                    if amountCents > 0 {
                        Text("\(CartMath.formatCents(amountCents)) will be paid from the drawer")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                } header: {
                    Text("Payout amount")
                }

                // Vendor / payee
                Section {
                    TextField("e.g. Office Depot, utility bill", text: $vendor)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Vendor or payee name")
                        .accessibilityIdentifier("payout.vendor")
                } header: {
                    Text("Vendor / payee (required)")
                }

                // Notes
                Section {
                    TextField("Optional additional notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityLabel("Payout notes")
                        .accessibilityIdentifier("payout.notes")
                } header: {
                    Text("Notes")
                }

                // Manager PIN gate
                if requiresManagerPin {
                    Section {
                        HStack(spacing: BrandSpacing.sm) {
                            Image(systemName: managerApproved
                                  ? "checkmark.shield.fill"
                                  : "lock.shield.fill")
                                .foregroundStyle(managerApproved ? .bizarreSuccess : .bizarreWarning)
                            Text(managerApproved
                                 ? "Manager approved"
                                 : "Manager PIN required for payouts ≥ $50")
                                .font(.brandBodyMedium())
                                .foregroundStyle(managerApproved ? .bizarreSuccess : .bizarreWarning)
                            Spacer()
                            if !managerApproved {
                                Button("Enter PIN") { showManagerPin = true }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .tint(.bizarreWarning)
                                    .accessibilityIdentifier("payout.enterPin")
                            }
                        }
                    }
                }

                // Approver name (optional, for paper trail)
                Section {
                    TextField("Manager name or initials", text: $approverName)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Approver name or initials")
                        .accessibilityIdentifier("payout.approver")
                } header: {
                    Text("Approver name (optional)")
                } footer: {
                    Text("Recorded on the payout line in the Z-report.")
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
            .navigationTitle("Payout")
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
                            .accessibilityIdentifier("payout.record")
                    }
                }
            }
            .sheet(isPresented: $showManagerPin) {
                ManagerPinSheet(
                    reason: "Payout of \(CartMath.formatCents(amountCents)) requires manager approval",
                    onApproved: { _ in
                        managerApproved = true
                        showManagerPin = false
                        AppLog.pos.info("Payout: manager PIN approved for \(amountCents)c")
                    },
                    onCancelled: { showManagerPin = false }
                )
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
        AppLog.pos.info("Payout: \(amountCents)c vendor=\(vendor)")
        onConfirm(amountCents, combinedReason)
        dismiss()
    }
}

// MARK: - Preview

#Preview("Payout sheet") {
    PayoutSheet { amount, reason in
        print("Payout: \(amount)c reason=\(reason)")
    }
    .preferredColorScheme(.dark)
}
#endif
