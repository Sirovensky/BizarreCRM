#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Persistence

/// §16.11 — Manager PIN approval sheet.
///
/// Presented whenever a cashier action exceeds a tenant-configured threshold
/// (discount ceiling, price override, void, no-sale drawer open).
///
/// PIN verification delegates to `PINStore.shared` — the same 4–6 digit PIN
/// used for the cashier unlock flow.  A dedicated `ManagerPINStore` with an
/// enrolled-manager scope is a planned follow-up (see inline TODO).
///
/// ## Follow-up
/// - Replace `PINStore.shared` with a `ManagerPINStore` that stores a
///   separately-enrolled manager PIN so cashiers and managers can have
///   different credentials.  The `onApproved` callback already passes
///   `managerId` so the audit layer needs no change.
///
/// ## Layout
/// Both iPhone (compact) and iPad (regular) get `.medium` + `.large`
/// presentation detents.  The keypad input uses `.monospacedDigit()` and
/// `.privacySensitive()` so it masks on screenshots.
public struct ManagerPinSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Describes why manager approval is needed. Rendered as a prominent
    /// header so the manager knows what they are approving before typing.
    public let reason: String

    /// Called when the PIN is verified successfully. Passes 0 as `managerId`
    /// — placeholder until a real manager-identity store ships (see above).
    public let onApproved: @MainActor (Int64) -> Void

    /// Called when the cashier cancels without approval.
    public let onCancelled: @MainActor () -> Void

    @State private var pinInput: String = ""
    @State private var errorMessage: String? = nil
    @State private var isVerifying: Bool = false
    @FocusState private var isPinFocused: Bool

    // Dot row length mirrors enrolled PIN length (or falls back to 4).
    @MainActor
    private var pinLength: Int { PINStore.shared.enrolledLength ?? 4 }

    public init(
        reason: String,
        onApproved: @escaping @MainActor (Int64) -> Void,
        onCancelled: @escaping @MainActor () -> Void
    ) {
        self.reason = reason
        self.onApproved = onApproved
        self.onCancelled = onCancelled
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.xl) {
                    reasonHeader
                    dotRow
                    pinField
                    if let err = errorMessage {
                        errorBanner(err)
                    }
                    Spacer()
                }
                .padding(.top, BrandSpacing.lg)
                .padding(.horizontal, BrandSpacing.base)
            }
            .navigationTitle("Manager approval")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancelled()
                        dismiss()
                    }
                    .accessibilityIdentifier("pos.managerPin.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Verify") { attemptVerify() }
                        .fontWeight(.semibold)
                        .disabled(!canVerify)
                        .accessibilityIdentifier("pos.managerPin.verify")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { isPinFocused = true }
    }

    // MARK: - Sub-views

    private var reasonHeader: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text(reason)
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("pos.managerPin.reason")
            Text("Enter manager PIN to approve")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
    }

    /// Visual dot row — filled circles for typed characters, empty for remaining.
    private var dotRow: some View {
        HStack(spacing: BrandSpacing.md) {
            ForEach(0..<pinLength, id: \.self) { index in
                Circle()
                    .fill(index < pinInput.count ? Color.bizarreOrange : Color.bizarreSurface1)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle().strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 1)
                    )
                    .animation(.easeInOut(duration: 0.1), value: pinInput.count)
            }
        }
        .accessibilityHidden(true)
    }

    /// Hidden numeric text field — the dot row provides visual feedback.
    /// `.privacySensitive()` suppresses the value in screenshots / AX logs.
    private var pinField: some View {
        TextField("PIN", text: $pinInput)
            .keyboardType(.numberPad)
            .font(.brandHeadlineMedium().monospacedDigit())
            .foregroundStyle(.clear)          // visually hidden; dots represent it
            .accentColor(.clear)
            .privacySensitive()
            .focused($isPinFocused)
            .onChange(of: pinInput) { _, new in
                // Strip non-digits and cap at 6 characters.
                let digits = String(new.filter { $0.isNumber }.prefix(6))
                if digits != new { pinInput = digits }
                errorMessage = nil
                // Auto-verify once all digits are typed.
                if digits.count == pinLength { attemptVerify() }
            }
            .accessibilityLabel("Manager PIN")
            .accessibilityIdentifier("pos.managerPin.input")
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreError)
        }
        .padding(.horizontal, BrandSpacing.base)
        .accessibilityIdentifier("pos.managerPin.error")
    }

    // MARK: - Logic

    @MainActor
    private var canVerify: Bool {
        let len = pinLength
        return pinInput.count >= 4 && pinInput.count <= len && !isVerifying
    }

    @MainActor
    private func attemptVerify() {
        guard !pinInput.isEmpty else { return }
        isVerifying = true
        errorMessage = nil

        let result = PINStore.shared.verify(pin: pinInput)
        isVerifying = false

        switch result {
        case .ok:
            BrandHaptics.success()
            // managerId = 0 placeholder. Replace with the real enrolled manager id
            // when ManagerPINStore ships.
            let approvedManagerId: Int64 = 0
            onApproved(approvedManagerId)
            dismiss()

        case .wrong(let remaining):
            BrandHaptics.error()
            pinInput = ""
            isPinFocused = true
            errorMessage = remaining > 0
                ? "Incorrect PIN — \(remaining) attempt\(remaining == 1 ? "" : "s") left before lockout."
                : "Incorrect PIN."

        case .lockedOut(let until):
            BrandHaptics.error()
            pinInput = ""
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            let whenStr = formatter.localizedString(for: until, relativeTo: Date())
            errorMessage = "Locked out — try again \(whenStr)."

        case .revoked:
            BrandHaptics.error()
            pinInput = ""
            errorMessage = "PIN revoked — full re-authentication required."
        }
    }
}
#endif
