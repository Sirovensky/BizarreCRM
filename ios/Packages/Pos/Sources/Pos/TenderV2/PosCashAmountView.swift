#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §D — Cash amount entry view.
///
/// - Numpad built with `Grid` + `GridRow` (not `LazyVGrid`) for uniform
///   column alignment. Min key height: 56pt iPhone / 72pt iPad.
/// - Quick-amount chip strip above the numpad: Exact / +$5 / +$10 / +$20 / custom.
/// - Received/change glass panel at the top showing live arithmetic.
/// - Barlow Condensed digits throughout.
public struct PosCashAmountView: View {

    /// Amount due for this leg (cents).
    public let dueCents: Int

    /// Called when the cashier confirms the amount.
    /// `receivedCents` is the amount entered (≥ dueCents).
    public let onConfirm: (_ receivedCents: Int) -> Void

    /// Called if the cashier cancels and goes back to method picker.
    public let onCancel: () -> Void

    @State private var digits: String = ""
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.posTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        dueCents: Int,
        onConfirm: @escaping (_ receivedCents: Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.dueCents = dueCents
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    // MARK: - Computed

    /// Received amount in cents from the `digits` string.
    private var receivedCents: Int {
        guard !digits.isEmpty, let value = Int(digits) else { return 0 }
        return value  // digits are stored as cents (no decimal UI)
    }

    private var changeCents: Int {
        max(0, receivedCents - dueCents)
    }

    private var canConfirm: Bool {
        receivedCents >= dueCents
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            glassPanel
                .padding(.horizontal, BrandSpacing.base)
                .padding(.top, BrandSpacing.lg)

            quickChipStrip
                .padding(.horizontal, BrandSpacing.base)
                .padding(.top, BrandSpacing.md)

            Spacer(minLength: BrandSpacing.md)

            numpad
                .padding(.horizontal, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.md)
        }
        .background(theme.bg.ignoresSafeArea())
    }

    // MARK: - Glass panel

    private var glassPanel: some View {
        VStack(spacing: BrandSpacing.sm) {
            // Due row
            HStack {
                Text("Cash due")
                    .font(.brandLabelLarge())
                    .foregroundStyle(theme.muted)
                Spacer()
                Text(CartMath.formatCents(dueCents))
                    .font(.brandBodyLarge())
                    .foregroundStyle(theme.on)
                    .monospacedDigit()
            }

            Divider()
                .background(theme.outline)

            // Received row — hero amount
            HStack(alignment: .firstTextBaseline) {
                Text("Received")
                    .font(.brandLabelLarge())
                    .foregroundStyle(theme.muted)
                Spacer()
                Text(receivedCents == 0 ? "—" : CartMath.formatCents(receivedCents))
                    .font(.brandDisplayMedium())
                    .foregroundStyle(receivedCents == 0 ? theme.muted : theme.on)
                    .monospacedDigit()
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(reduceMotion ? .none : .spring(duration: 0.2), value: receivedCents)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Amount received: \(receivedCents == 0 ? "none" : CartMath.formatCents(receivedCents))")

            // Change row (visible when received >= due)
            if receivedCents >= dueCents {
                Divider()
                    .background(theme.outline)
                HStack {
                    Text("Change due")
                        .font(.brandLabelLarge())
                        .foregroundStyle(theme.muted)
                    Spacer()
                    Text(CartMath.formatCents(changeCents))
                        .font(.brandHeadlineMedium())
                        .foregroundStyle(changeCents > 0 ? theme.primary : theme.muted)
                        .monospacedDigit()
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .contentTransition(.numericText(countsDown: false))
                        .animation(reduceMotion ? .none : .spring(duration: 0.2), value: changeCents)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Change due: \(CartMath.formatCents(changeCents))")
                .accessibilityIdentifier("pos.cashAmountV2.change")
            }
        }
        .padding(BrandSpacing.base)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("pos.cashAmountV2.glassPanel")
    }

    // MARK: - Quick chip strip

    private var quickChipStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                quickChip(label: "Exact") {
                    digits = "\(dueCents)"
                }
                quickChip(label: "+$5") {
                    digits = "\(dueCents + 500)"
                }
                quickChip(label: "+$10") {
                    digits = "\(dueCents + 1000)"
                }
                quickChip(label: "+$20") {
                    digits = "\(dueCents + 2000)"
                }
                // Custom: clear back to 0 so cashier types freely
                quickChip(label: "Custom") {
                    digits = ""
                }
            }
            .padding(.horizontal, 1)
        }
        .accessibilityLabel("Quick amount presets")
    }

    private func quickChip(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(theme.on)
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)
                .background(theme.surfaceElev, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.outline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("Quick amount: \(label)")
        .accessibilityIdentifier("pos.cashAmountV2.chip.\(label)")
    }

    // MARK: - Numpad

    private var numpad: some View {
        let minKeyHeight: CGFloat = (sizeClass == .regular) ? 72 : 56

        return Grid(horizontalSpacing: BrandSpacing.sm, verticalSpacing: BrandSpacing.sm) {
            GridRow {
                numpadKey("1", minHeight: minKeyHeight)
                numpadKey("2", minHeight: minKeyHeight)
                numpadKey("3", minHeight: minKeyHeight)
            }
            GridRow {
                numpadKey("4", minHeight: minKeyHeight)
                numpadKey("5", minHeight: minKeyHeight)
                numpadKey("6", minHeight: minKeyHeight)
            }
            GridRow {
                numpadKey("7", minHeight: minKeyHeight)
                numpadKey("8", minHeight: minKeyHeight)
                numpadKey("9", minHeight: minKeyHeight)
            }
            GridRow {
                numpadKey("00", minHeight: minKeyHeight)
                numpadKey("0", minHeight: minKeyHeight)
                numpadDeleteKey(minHeight: minKeyHeight)
            }
        }
        .accessibilityLabel("Cash amount numpad")
        .accessibilityIdentifier("pos.cashAmountV2.numpad")
    }

    private func numpadKey(_ label: String, minHeight: CGFloat) -> some View {
        Button {
            appendDigits(label)
        } label: {
            Text(label)
                .font(.custom("BarlowCondensed-SemiBold", size: 28, relativeTo: .title))
                .foregroundStyle(theme.on)
                .frame(maxWidth: .infinity)
                .frame(minHeight: minHeight)
                .background(theme.surfaceElev, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(theme.outline, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(label)
        .accessibilityIdentifier("pos.cashAmountV2.key.\(label)")
    }

    private func numpadDeleteKey(minHeight: CGFloat) -> some View {
        Button {
            deleteDigit()
        } label: {
            Image(systemName: "delete.backward")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(theme.muted)
                .frame(maxWidth: .infinity)
                .frame(minHeight: minHeight)
                .background(theme.surfaceElev, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(theme.outline, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("Delete")
        .accessibilityIdentifier("pos.cashAmountV2.key.delete")
    }

    // MARK: - Digit management

    private func appendDigits(_ s: String) {
        // Cap at 9 digits to prevent overflow ($9,999,999.99)
        guard digits.count + s.count <= 9 else { return }
        // Strip leading zeros
        let combined = digits + s
        digits = combined == "0" ? "0" : String(Int(combined) ?? 0)
        if digits == "0" { digits = "" }
    }

    private func deleteDigit() {
        guard !digits.isEmpty else { return }
        digits.removeLast()
    }
}
#endif
