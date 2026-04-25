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
    /// Supports decimal entry (e.g. "300.00" → 30000 cents).
    private var receivedCents: Int {
        guard !digits.isEmpty else { return 0 }
        if digits.contains(".") {
            guard let value = Double(digits) else { return 0 }
            return Int((value * 100).rounded())
        } else {
            guard let value = Int(digits) else { return 0 }
            return value * 100
        }
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

    /// Two-column layout: Received (left) | Change (right), matching mockup 5b/4b.
    private var glassPanel: some View {
        HStack(spacing: 0) {
            // Received column
            VStack(spacing: BrandSpacing.xxs) {
                Text("Received")
                    .font(.brandLabelSmall())
                    .foregroundStyle(theme.muted)
                    .tracking(0.6)
                    .textCase(.uppercase)
                Text(receivedCents == 0 ? "—" : CartMath.formatCents(receivedCents))
                    .font(.brandDisplayMedium())
                    .foregroundStyle(receivedCents == 0 ? theme.muted : theme.on)
                    .monospacedDigit()
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(reduceMotion ? .none : .spring(duration: 0.2), value: receivedCents)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Amount received: \(receivedCents == 0 ? "none" : CartMath.formatCents(receivedCents))")

            Divider()
                .frame(height: 48)
                .background(theme.outline)

            // Change column
            VStack(spacing: BrandSpacing.xxs) {
                Text("Change")
                    .font(.brandLabelSmall())
                    .foregroundStyle(theme.muted)
                    .tracking(0.6)
                    .textCase(.uppercase)
                Text(receivedCents >= dueCents ? CartMath.formatCents(changeCents) : "—")
                    .font(.brandDisplayMedium())
                    .foregroundStyle(
                        receivedCents >= dueCents && changeCents > 0
                            ? theme.primary
                            : theme.muted
                    )
                    .monospacedDigit()
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(reduceMotion ? .none : .spring(duration: 0.2), value: changeCents)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Change due: \(receivedCents >= dueCents ? CartMath.formatCents(changeCents) : "none")")
            .accessibilityIdentifier("pos.cashAmountV2.change")
        }
        .padding(.vertical, BrandSpacing.md)
        .padding(.horizontal, BrandSpacing.base)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("pos.cashAmountV2.glassPanel")
    }

    // MARK: - Quick chip strip

    /// Round-up presets above the due amount.
    /// Matches mockup 5b/4b: "Exact · $N · $N+5 · $N+10 · $N+20"
    /// where N values are the next whole-dollar round-up thresholds.
    private var quickAmountPresets: [(label: String, cents: Int)] {
        let exact = dueCents
        // Round up to the next dollar, then add $5 increments
        let nextDollar = ((dueCents + 99) / 100) * 100  // ceiling to whole dollars
        let presets: [Int] = [
            nextDollar,
            roundUpTo(dueCents, multiple: 500),   // next $5
            roundUpTo(dueCents, multiple: 1000),  // next $10
            roundUpTo(dueCents, multiple: 2000),  // next $20
        ]
        // Deduplicate & sort, skip values equal to exact
        var seen = Set<Int>()
        var result: [(String, Int)] = [("Exact", exact)]
        for cents in presets.sorted() {
            guard cents > exact, seen.insert(cents).inserted else { continue }
            result.append(("$\(cents / 100)", cents))
        }
        return result
    }

    private func roundUpTo(_ value: Int, multiple: Int) -> Int {
        let rem = value % multiple
        return rem == 0 ? value + multiple : value + (multiple - rem)
    }

    private var quickChipStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                ForEach(quickAmountPresets, id: \.cents) { preset in
                    quickChip(label: preset.label, selected: receivedCents == preset.cents) {
                        // Store as dollars string (e.g. "300" → interpreted as $300.00)
                        digits = "\(preset.cents / 100)"
                    }
                }
            }
            .padding(.horizontal, 1)
        }
        .accessibilityLabel("Quick amount presets")
    }

    private func quickChip(label: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(selected ? theme.onPrimary : theme.on)
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)
                .background(
                    selected ? theme.primary : theme.surfaceElev,
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        selected ? theme.primary : theme.outline,
                        lineWidth: selected ? 0 : 0.5
                    )
                )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("Quick amount: \(label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                numpadDecimalKey(minHeight: minKeyHeight)
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

    private func numpadDecimalKey(minHeight: CGFloat) -> some View {
        Button {
            appendDecimal()
        } label: {
            Text(".")
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
        .accessibilityLabel("Decimal point")
        .accessibilityIdentifier("pos.cashAmountV2.key.decimal")
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
        // Cap total length (e.g. "9999999.99" = 10 chars max)
        let maxLen = 10
        guard digits.count + s.count <= maxLen else { return }
        // Don't allow multiple decimal points
        if s == "." && digits.contains(".") { return }
        // Don't allow more than 2 decimal places
        if let dotIdx = digits.firstIndex(of: ".") {
            let decimals = digits.distance(from: digits.index(after: dotIdx), to: digits.endIndex)
            if decimals >= 2 { return }
        }
        if digits.isEmpty && s == "." {
            digits = "0."
        } else if digits == "0" && s != "." {
            digits = s
        } else {
            digits = digits + s
        }
    }

    private func appendDecimal() {
        if !digits.contains(".") {
            digits = digits.isEmpty ? "0." : digits + "."
        }
    }

    private func deleteDigit() {
        guard !digits.isEmpty else { return }
        digits.removeLast()
        // Clean up trailing "0." → ""
        if digits == "0" { digits = "" }
    }
}
#endif
