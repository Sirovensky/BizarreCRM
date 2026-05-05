#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosManualKeyedCardSheet (§16.6)

/// Role-gated instruction sheet for manual-keyed card entry.
///
/// **PCI model (SAQ-A posture) — §16.6:**
/// We do NOT build our own TextFields capturing PAN / expiry / CVV.
/// That would push the app into SAQ-D scope and is a non-starter.
///
/// **Preferred path:** Cashier hands the physical terminal to the customer;
/// customer keys card on the terminal PIN pad (or taps / inserts). The
/// BlockChyp SDK call uses `allowManualKey: true`; terminal UI prompts for
/// keyed entry. Raw digits never leave the terminal.
///
/// **Cardholder-not-present path** (phone orders, back-office): BlockChyp
/// "virtual-terminal" / tokenization — BlockChyp's own secure keyed-entry
/// sheet tokenizes inside the SDK process; we receive `{ token, last4, brand }`.
/// Still no PAN on our disk or server.
///
/// **This sheet's role:**
/// 1. Gate on manager PIN (role required).
/// 2. Display clear PCI instructions to the cashier.
/// 3. Confirm the tender method and invoke the BlockChyp terminal charge
///    (delegation to `SignatureRouter` / BlockChyp flow — not implemented
///    here per §16.5 HIGH RISK stop).
///
/// When BlockChyp §16.5 is approved and implemented, wire `onProceed` to
/// `BlockChypTerminalService.chargeWithManualKey(amountCents:idempotencyKey:)`.
@MainActor
public struct PosManualKeyedCardSheet: View {

    // MARK: - Inputs

    public let amountCents: Int
    /// Called when the manager approves and the cashier is ready to proceed
    /// to the BlockChyp terminal flow. Parameter: approved manager ID.
    public let onProceed: (Int64) -> Void
    public let onCancel: () -> Void

    // MARK: - State

    @Environment(\.dismiss) private var dismiss
    @State private var showManagerPin = false
    @State private var managerApprovedId: Int64?

    // MARK: - Init

    public init(
        amountCents: Int,
        onProceed: @escaping (Int64) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.amountCents = amountCents
        self.onProceed = onProceed
        self.onCancel = onCancel
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Form {
                pciPolicySection
                instructionsSection
                offlinePolicySection
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Manual Card Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .frame(idealWidth: Platform.isCompact ? nil : 540)
        .sheet(isPresented: $showManagerPin) {
            ManagerPinSheet(
                reason: "Manual keyed card entry requires manager approval. Amount: \(CartMath.formatCents(amountCents)).",
                onApproved: { approvedId in
                    managerApprovedId = approvedId
                },
                onCancelled: { }
            )
        }
    }

    // MARK: - Sections

    private var pciPolicySection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("PCI scope — manager required")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Manual keyed entry requires a manager PIN. Raw card numbers (PAN) are never typed into this app — they are entered on the BlockChyp terminal or via BlockChyp's tokenization flow only.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(Color.bizarrePrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("pos.manualCard.pciWarning")
        }
    }

    private var instructionsSection: some View {
        Section("How to proceed") {
            manualKeyedStep(
                number: "1",
                icon: "terminal",
                title: "Hand terminal to customer",
                detail: "Ask customer to type their card number, expiry, and CVV on the BlockChyp terminal PIN pad."
            )
            manualKeyedStep(
                number: "2",
                icon: "touchid",
                title: "Customer completes entry on terminal",
                detail: "BlockChyp tokenizes the card inside the terminal. Raw digits never reach this device."
            )
            manualKeyedStep(
                number: "3",
                icon: "checkmark.seal.fill",
                title: "App receives token + last 4",
                detail: "On approval, the app records only the opaque token, last 4 digits, card brand, and auth code. No PAN stored."
            )
        }
    }

    private var offlinePolicySection: some View {
        Section("Offline policy") {
            Label {
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("Manual keyed entry requires internet")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("BlockChyp must reach its servers to tokenize the card number. If the device is offline, this option is unavailable — use cash or check instead.")
                        .font(.brandBodySmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            } icon: {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.bizarreWarning)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("pos.manualCard.offlinePolicy")
        }
    }

    // MARK: - Step row helper

    private func manualKeyedStep(
        number: String,
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.bizarrePrimary.opacity(0.15))
                    .frame(width: 32, height: 32)
                Text(number)
                    .font(.brandTitleSmall())
                    .foregroundStyle(Color.bizarrePrimary)
            }
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Label(title, systemImage: icon)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text(detail)
                    .font(.brandBodySmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(title). \(detail)")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                onCancel()
                dismiss()
            }
            .accessibilityIdentifier("pos.manualCard.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            if let approvedId = managerApprovedId {
                Button("Proceed") {
                    onProceed(approvedId)
                    dismiss()
                }
                .fontWeight(.semibold)
                .accessibilityIdentifier("pos.manualCard.proceed")
            } else {
                Button {
                    showManagerPin = true
                } label: {
                    Label("Manager PIN", systemImage: "lock")
                }
                .accessibilityIdentifier("pos.manualCard.requirePin")
            }
        }
    }
}
#endif
