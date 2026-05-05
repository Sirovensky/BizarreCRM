#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §D — Cash amount entry view.
///
/// Renders the full mockup 5b (iPhone) / 4b (iPad) cash numpad screen:
///   1. Selected-method confirmation strip (gradient icon + "Cash payment" +
///      due subtitle + "Active" success chip).
///   2. "Cash received" section label.
///   3. Two-column glass panel: Received | Change.
///   4. "Quick amount" section label.
///   5. Horizontally-scrolling quick-amount chip row.
///   6. 3×4 numpad (`.` decimal, `0`, `⌫` error-coloured).
///   7. Sticky footer: "Split tender" + "Add tip" aux buttons + "Confirm cash"
///      gradient CTA.
///
/// Numpad built with `Grid` + `GridRow` (not `LazyVGrid`) for uniform column
/// alignment. Min key height: 56 pt iPhone / 72 pt iPad.
public struct PosCashAmountView: View {

    /// Amount due for this leg (cents).
    public let dueCents: Int

    /// Called when the cashier confirms the amount.
    /// `receivedCents` is the amount entered (≥ dueCents).
    public let onConfirm: (_ receivedCents: Int) -> Void

    /// Called if the cashier cancels and goes back to method picker.
    public let onCancel: () -> Void

    @State private var digits: String = ""
    /// §16.6 — tracks whether change was already positive so we only fire the
    /// "change due" haptic + pop animation once when the threshold is first crossed.
    @State private var changePopScale: CGFloat = 1.0
    @State private var didCrossChangeDue: Bool = false
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
            ScrollView {
                VStack(spacing: 0) {
                    methodStrip
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.top, BrandSpacing.sm)

                    sectionLabel("Cash received")

                    glassPanel
                        .padding(.horizontal, BrandSpacing.base)

                    sectionLabel("Quick amount")

                    quickChipStrip
                        .padding(.bottom, BrandSpacing.xxs)

                    numpad
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.bottom, BrandSpacing.sm)
                }
            }

            confirmFooter
        }
        .background(theme.bg.ignoresSafeArea())
    }

    // MARK: - Method confirmation strip

    /// Selected-method strip: gradient 34×34 icon tile, title + subtitle, Active chip.
    private var methodStrip: some View {
        HStack(spacing: 10) {
            // Gradient icon tile
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [theme.primaryBright, theme.primary],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 34, height: 34)
                    .shadow(color: theme.primary.opacity(0.22), radius: 5, x: 0, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.bizarreOnSurface.opacity(0.6), lineWidth: 0.5)
                            .blendMode(.overlay)
                    )
                Text("💵")
                    .font(.system(size: 17))
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Cash payment")
                    .font(.brandLabelLarge())
                    .fontWeight(.bold)
                    .foregroundStyle(theme.primary)
                Text("Due: \(CartMath.formatCents(dueCents)) · enter amount received below")
                    .font(.brandLabelSmall())
                    .foregroundStyle(theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Active chip
            Text("Active")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.onPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(theme.success, in: Capsule())
                .accessibilityLabel("Status: Active")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(theme.primary.opacity(0.25), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cash payment selected. Due: \(CartMath.formatCents(dueCents)). Active.")
        .accessibilityIdentifier("pos.cashAmountV2.methodStrip")
    }

    // MARK: - Section label

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(theme.muted2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, BrandSpacing.base)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    // MARK: - Glass panel

    /// Two-column layout: Received (left) | Change (right), matching mockup 5b/4b.
    private var glassPanel: some View {
        HStack(spacing: 0) {
            // Received column
            VStack(spacing: BrandSpacing.xxs) {
                Text("Received")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.muted)

                receivedAmountText()
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: false))
                    .animation(reduceMotion ? .none : .spring(duration: 0.2), value: receivedCents)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Amount received: \(receivedCents == 0 ? "none" : CartMath.formatCents(receivedCents))")

            Rectangle()
                .fill(theme.outline)
                .frame(width: 1, height: 48)

            // Change column
            VStack(spacing: BrandSpacing.xxs) {
                Text("Change")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.muted)
                Text(receivedCents >= dueCents ? CartMath.formatCents(changeCents) : "—")
                    .font(.custom("BarlowCondensed-Bold", size: 30, relativeTo: .title))
                    .foregroundStyle(
                        receivedCents >= dueCents ? theme.success : theme.muted
                    )
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: false))
                    // §16.6 — pop scale animation when change becomes positive.
                    .scaleEffect(changePopScale)
                    .animation(reduceMotion ? .none : .spring(duration: 0.2), value: changeCents)
                    .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.55), value: changePopScale)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Change due: \(receivedCents >= dueCents ? CartMath.formatCents(changeCents) : "none")")
            .accessibilityIdentifier("pos.cashAmountV2.change")
            // §16.6 — fire haptic + scale pop when received amount first reaches due.
            .onChange(of: canConfirm) { _, nowCanConfirm in
                if nowCanConfirm && !didCrossChangeDue {
                    didCrossChangeDue = true
                    BrandHaptics.success()
                    if !reduceMotion {
                        changePopScale = 1.18
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 160_000_000)
                            changePopScale = 1.0
                        }
                    }
                } else if !nowCanConfirm {
                    // Reset so re-entry can trigger haptic again.
                    didCrossChangeDue = false
                }
            }
        }
        .padding(.vertical, BrandSpacing.md)
        .padding(.horizontal, BrandSpacing.base)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("pos.cashAmountV2.glassPanel")
    }

    /// Received amount styled with muted cents portion (e.g. "$300" + muted ".00").
    /// Uses SwiftUI Text-concatenation (+) so both branches return `Text` — no @ViewBuilder.
    private func receivedAmountText() -> Text {
        if receivedCents == 0 {
            return Text("—")
                .font(.custom("BarlowCondensed-Bold", size: 40, relativeTo: .largeTitle))
                .foregroundColor(theme.muted)
        }
        let formatted = CartMath.formatCents(receivedCents)
        if let dotRange = formatted.range(of: ".") {
            let whole = String(formatted[formatted.startIndex ..< dotRange.lowerBound])
            let cents = String(formatted[dotRange.lowerBound...])
            return Text(whole)
                .font(.custom("BarlowCondensed-Bold", size: 40, relativeTo: .largeTitle))
                .foregroundColor(theme.on)
            + Text(cents)
                .font(.custom("BarlowCondensed-Medium", size: 40, relativeTo: .largeTitle))
                .foregroundColor(theme.muted)
        }
        return Text(formatted)
            .font(.custom("BarlowCondensed-Bold", size: 40, relativeTo: .largeTitle))
            .foregroundColor(theme.on)
    }

    // MARK: - Quick chip strip

    /// Round-up presets above the due amount.
    /// Matches mockup 5b/4b: "Exact · $275 · $280 · $300 · $320"
    /// (next whole-dollar + $5 round-up increments around the due amount).
    private var quickAmountPresets: [(label: String, cents: Int)] {
        let exact = dueCents
        let nextDollar = ((dueCents + 99) / 100) * 100
        let presets: [Int] = [
            nextDollar,
            roundUpTo(dueCents, multiple: 500),
            roundUpTo(dueCents, multiple: 1000),
            roundUpTo(dueCents, multiple: 2000),
        ]
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
            HStack(spacing: 6) {
                ForEach(quickAmountPresets, id: \.cents) { preset in
                    quickChip(label: preset.label, selected: receivedCents == preset.cents) {
                        digits = "\(preset.cents / 100)"
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, 2)
        }
        .accessibilityLabel("Quick amount presets")
    }

    private func quickChip(label: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.custom("BarlowCondensed-Bold", size: 17, relativeTo: .body))
                .tracking(-0.1)
                .foregroundStyle(selected ? theme.primary : theme.on)
                .frame(minWidth: 68)
                .padding(.horizontal, 6)
                .padding(.vertical, 11)
                .background(
                    Capsule()
                        .fill(
                            selected
                            ? AnyShapeStyle(theme.primary.opacity(0.06))
                            : AnyShapeStyle(Color.bizarreOnSurface.opacity(0.04))
                        )
                )
                .overlay(
                    Capsule().strokeBorder(
                        selected ? theme.primary.opacity(0.40) : Color.bizarreOnSurface.opacity(0.11),
                        lineWidth: 1
                    )
                )
                .shadow(
                    color: selected ? theme.primary.opacity(0.06) : .clear,
                    radius: 6, x: 0, y: 4
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

        return Grid(horizontalSpacing: 8, verticalSpacing: 8) {
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
                .font(.custom("BarlowCondensed-Bold", size: 26, relativeTo: .title))
                .tracking(-0.1)
                .foregroundStyle(theme.on)
                .frame(maxWidth: .infinity)
                .frame(minHeight: minHeight)
                .background(numKeyBackground)
                .overlay(numKeyBorder)
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
                .font(.custom("BarlowCondensed-Bold", size: 26, relativeTo: .title))
                .foregroundStyle(theme.muted)
                .frame(maxWidth: .infinity)
                .frame(minHeight: minHeight)
                .background(numKeyBackground)
                .overlay(numKeyBorder)
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
            Text("⌫")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(theme.error)
                .frame(maxWidth: .infinity)
                .frame(minHeight: minHeight)
                .background(numKeyBackground)
                .overlay(numKeyBorder)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("Delete")
        .accessibilityIdentifier("pos.cashAmountV2.key.delete")
    }

    private var numKeyBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.bizarreOnSurface.opacity(0.055))
            .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 4)
    }

    private var numKeyBorder: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.bizarreOnSurface.opacity(0.13), lineWidth: 1)
    }

    // MARK: - Confirm footer

    /// Sticky footer: aux buttons row + gradient CTA — matches mockup `tender-safearea`.
    private var confirmFooter: some View {
        VStack(spacing: 0) {
            Divider()
                .background(theme.outline)

            VStack(spacing: 8) {
                // Aux row
                HStack(spacing: 10) {
                    auxButton("+ Split tender") {
                        onCancel()
                    }
                    auxButton("Add tip") {
                        // Tip is handled globally by PosTenderAmountBar when present.
                        // Here a no-op matches the mockup presence of the button.
                    }
                }

                // Primary CTA
                Button {
                    guard canConfirm else { return }
                    // §16.6 — tactile confirm so cashier feels the sale land.
                    BrandHaptics.success()
                    onConfirm(receivedCents)
                } label: {
                    HStack(spacing: 10) {
                        Text("Confirm cash")
                            .font(.system(size: 17, weight: .heavy))
                            .tracking(-0.01 * 17)

                        Text(CartMath.formatCents(dueCents))
                            .font(.custom("BarlowCondensed-Bold", size: 22, relativeTo: .title))
                            .monospacedDigit()

                        Text("›")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .background(confirmBackground)
                    .overlay(confirmBorder)
                    .opacity(canConfirm ? 1.0 : 0.45)
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .disabled(!canConfirm)
                .accessibilityLabel("Confirm cash payment of \(CartMath.formatCents(dueCents))")
                .accessibilityHint(canConfirm ? "Finalise cash tender" : "Enter an amount equal to or greater than the due amount")
                .accessibilityIdentifier("pos.cashAmountV2.confirm")
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.top, BrandSpacing.sm)
            .padding(.bottom, BrandSpacing.lg)
            .background(.ultraThinMaterial)
        }
    }

    private func auxButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme.on)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(theme.surfaceElev, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(theme.outline, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }

    private var confirmBackground: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(
                LinearGradient(
                    colors: [theme.primaryBright, theme.primary],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: theme.primary.opacity(0.12), radius: 10, x: 0, y: 8)
    }

    private var confirmBorder: some View {
        RoundedRectangle(cornerRadius: 18)
            .strokeBorder(Color.bizarreOnSurface.opacity(0.30), lineWidth: 1)
    }

    // MARK: - Digit management

    private func appendDigits(_ s: String) {
        let maxLen = 10
        guard digits.count + s.count <= maxLen else { return }
        if s == "." && digits.contains(".") { return }
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
        if digits == "0" { digits = "" }
    }
}
#endif
