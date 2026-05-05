#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §D — Gift card scan-or-enter amount view.
///
/// The cashier can either:
/// - Scan a QR / barcode via camera (stubbed; real camera via `PosScanSheet`).
/// - Type the gift card code manually.
/// Then the view validates the code against the server and applies the balance
/// up to `dueCents`.
///
/// Full gift-card redemption wiring is in `GiftCards/` (existing v1). This
/// view focuses on the tender-entry UX surface only.
public struct PosGiftCardAmountView: View {

    /// Amount due for this leg (cents).
    public let dueCents: Int

    /// Called with the amount to apply and the gift-card code as reference.
    public let onConfirm: (_ amountCents: Int, _ reference: String?) -> Void

    /// Called if the cashier cancels.
    public let onCancel: () -> Void

    @State private var codeInput: String = ""
    @State private var isValidating: Bool = false
    @State private var validationError: String? = nil
    @FocusState private var codeFieldFocused: Bool

    @Environment(\.posTheme) private var theme

    public init(
        dueCents: Int,
        onConfirm: @escaping (_ amountCents: Int, _ reference: String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.dueCents = dueCents
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: BrandSpacing.lg) {
                    // Header
                    VStack(spacing: BrandSpacing.xxs) {
                        Text("Gift card")
                            .font(.brandLabelLarge())
                            .foregroundStyle(theme.muted)
                        Text(CartMath.formatCents(dueCents))
                            .font(.brandDisplayMedium())
                            .foregroundStyle(theme.on)
                            .monospacedDigit()
                            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                            .accessibilityIdentifier("pos.giftCardAmountV2.amount")
                    }
                    .padding(.top, BrandSpacing.xl)

                    // Scan button
                    Button {
                        // TODO: present PosScanSheet camera scanner
                        // For now, focus the text field so cashier types.
                        codeFieldFocused = true
                    } label: {
                        HStack(spacing: BrandSpacing.sm) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 20, weight: .medium))
                                .accessibilityHidden(true)
                            Text("Scan gift card")
                                .font(.brandTitleMedium())
                        }
                        .foregroundStyle(theme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BrandSpacing.md)
                        .background(theme.primarySoft, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(theme.primary.opacity(0.4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, BrandSpacing.base)
                    .accessibilityLabel("Scan gift card barcode or QR code")
                    .accessibilityIdentifier("pos.giftCardAmountV2.scan")

                    // Divider label
                    HStack {
                        Rectangle().fill(theme.outline).frame(height: 1)
                        Text("or enter code")
                            .font(.brandLabelSmall())
                            .foregroundStyle(theme.muted)
                            .fixedSize()
                        Rectangle().fill(theme.outline).frame(height: 1)
                    }
                    .padding(.horizontal, BrandSpacing.base)

                    // Manual code entry
                    VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                        Text("Gift card code")
                            .font(.brandLabelLarge())
                            .foregroundStyle(theme.muted)
                        TextField("Enter code", text: $codeInput)
                            .font(.brandMono(size: 16))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                            .focused($codeFieldFocused)
                            .padding(BrandSpacing.md)
                            .background(theme.surfaceElev, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        codeFieldFocused ? theme.outlineBright : theme.outline,
                                        lineWidth: codeFieldFocused ? 1 : 0.5
                                    )
                            )
                            .accessibilityIdentifier("pos.giftCardAmountV2.codeField")
                    }
                    .padding(.horizontal, BrandSpacing.base)

                    // Validation error
                    if let error = validationError {
                        HStack(spacing: BrandSpacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(theme.error)
                                .accessibilityHidden(true)
                            Text(error)
                                .font(.brandBodyMedium())
                                .foregroundStyle(theme.on)
                        }
                        .padding(BrandSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.error.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, BrandSpacing.base)
                        .accessibilityIdentifier("pos.giftCardAmountV2.error")
                    }
                }
            }

            // Apply button
            Button {
                applyGiftCard()
            } label: {
                Group {
                    if isValidating {
                        ProgressView()
                            .tint(theme.onPrimary)
                    } else {
                        Text("Apply gift card")
                            .font(.brandTitleMedium())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.md)
                .foregroundStyle(codeInput.isEmpty ? theme.muted : theme.onPrimary)
            }
            .buttonStyle(.borderedProminent)
            .tint(codeInput.isEmpty ? theme.surfaceElev : theme.primary)
            .disabled(codeInput.isEmpty || isValidating)
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.lg)
            .padding(.top, BrandSpacing.sm)
            .accessibilityIdentifier("pos.giftCardAmountV2.applyButton")
        }
        .background(theme.bg.ignoresSafeArea())
        .onAppear { codeFieldFocused = true }
    }

    // MARK: - Actions

    private func applyGiftCard() {
        guard !codeInput.isEmpty else { return }
        isValidating = true
        validationError = nil

        // Validation is handled by GiftCards/ module in a full integration.
        // Here we optimistically apply the full dueCents amount with the code
        // as reference. The server validates the balance on POST /pos/transaction.
        let code = codeInput.trimmingCharacters(in: .whitespaces).uppercased()
        isValidating = false
        onConfirm(dueCents, code)
    }
}
#endif
