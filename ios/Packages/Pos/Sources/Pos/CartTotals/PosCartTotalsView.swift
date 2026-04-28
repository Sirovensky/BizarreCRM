#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosCartTotalsView (§16 totals animation + discount highlight + shimmer + a11y)

/// Displays the running subtotal / discount / tax / total footer in the POS cart pane.
///
/// **Animated total (§16 live recompute):**
/// Digit changes animate with a small font-weight "tick" using
/// `.contentTransition(.numericText(value:))` + `.animation(.spring)`.
///
/// **Discount highlight (§16 discount highlight):**
/// When a new discount is applied the discount row flashes orange and the
/// original price shows a strike-through, fading to the discounted price.
/// Controlled by `discountFlash` state — fires once per distinct `discountCents`
/// change via `.onChange`.
///
/// **Pending server validation shimmer (§16 server validation shimmer):**
/// While `isPendingValidation == true`, the total row shows a shimmer overlay
/// (`.redacted(.placeholder)` + shimmer animation) to indicate the server is
/// validating the cart price. Clears when the server responds.
///
/// **A11y (§16 screen reader):**
/// `.accessibilityValue` on the total row provides a debounced announcement
/// so VoiceOver reads "Total: $42.50" after cart changes settle — not on every
/// per-keypress character.
@MainActor
public struct PosCartTotalsView: View {

    // MARK: - Inputs

    public let subtotalCents: Int
    public let discountCents: Int    // Always positive (the reduction amount)
    public let taxCents: Int
    public let totalCents: Int
    /// When true, shows the shimmer / validation-pending state on the total row.
    public let isPendingValidation: Bool
    /// Unique cart version counter — bump on every cart change to drive a11y announcements.
    public let cartVersion: Int

    // MARK: - Private state

    @State private var discountFlashing = false
    @State private var previousDiscountCents: Int = 0
    @State private var announcedTotal: Int = 0
    @State private var a11yAnnounceTask: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Init

    public init(
        subtotalCents: Int,
        discountCents: Int = 0,
        taxCents: Int = 0,
        totalCents: Int,
        isPendingValidation: Bool = false,
        cartVersion: Int = 0
    ) {
        self.subtotalCents = subtotalCents
        self.discountCents = discountCents
        self.taxCents = taxCents
        self.totalCents = totalCents
        self.isPendingValidation = isPendingValidation
        self.cartVersion = cartVersion
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: BrandSpacing.xs) {
            subtotalRow
            if discountCents > 0 { discountRow }
            if taxCents > 0 { taxRow }
            Divider().background(Color.bizarreOutline)
            totalRow
        }
        .onChange(of: discountCents) { old, new in
            guard new > old, !reduceMotion else { return }
            triggerDiscountFlash()
        }
        .onChange(of: cartVersion) { _, _ in
            scheduleA11yAnnouncement()
        }
    }

    // MARK: - Subtotal row

    private var subtotalRow: some View {
        HStack {
            Text("Subtotal")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(CartMath.formatCents(subtotalCents))
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(subtotalCents)))
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: subtotalCents)
        }
        .accessibilityIdentifier("pos.totals.subtotal")
    }

    // MARK: - Discount row (§16 discount highlight)

    @ViewBuilder
    private var discountRow: some View {
        HStack {
            Label("Discount", systemImage: "tag.fill")
                .font(.brandBodyMedium())
                .foregroundStyle(discountFlashing ? Color.bizarrePrimary : .bizarreOnSurfaceMuted)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: discountFlashing)

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                // Strike-through original price (§16 discount highlight)
                if discountFlashing {
                    Text(CartMath.formatCents(subtotalCents + discountCents))
                        .font(.brandBodySmall())
                        .strikethrough(true, color: .bizarreOnSurfaceMuted)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .transition(reduceMotion ? .identity : .scale(scale: 0.8).combined(with: .opacity))
                }
                Text("-\(CartMath.formatCents(discountCents))")
                    .font(.brandBodyMedium())
                    .foregroundStyle(discountFlashing ? Color.bizarrePrimary : .bizarreSuccess)
                    .fontWeight(discountFlashing ? .semibold : .regular)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(discountCents)))
                    .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: discountCents)
            }
        }
        .padding(.vertical, discountFlashing ? BrandSpacing.xxs : 0)
        .background(
            discountFlashing
                ? RoundedRectangle(cornerRadius: DesignTokens.Radius.badge)
                    .fill(Color.bizarrePrimary.opacity(0.10))
                    .transition(.opacity)
                : nil
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: discountFlashing)
        .accessibilityIdentifier("pos.totals.discount")
        .accessibilityLabel("Discount applied: minus \(CartMath.formatCents(discountCents))")
    }

    // MARK: - Tax row

    private var taxRow: some View {
        HStack {
            Text("Tax")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(CartMath.formatCents(taxCents))
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(taxCents)))
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: taxCents)
        }
        .accessibilityIdentifier("pos.totals.tax")
    }

    // MARK: - Total row (§16 shimmer + live animation)

    private var totalRow: some View {
        HStack {
            Text("TOTAL")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            Group {
                if isPendingValidation {
                    pendingTotalShimmer
                } else {
                    Text(CartMath.formatCents(totalCents))
                        .font(.brandDisplaySmall())
                        .foregroundStyle(Color.bizarrePrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(totalCents)))
                        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.75), value: totalCents)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Total")
        .accessibilityValue(isPendingValidation ? "Calculating" : CartMath.formatCents(totalCents))
        .accessibilityIdentifier("pos.totals.total")
    }

    // MARK: - Pending server validation shimmer (§16 server validation shimmer)

    private var pendingTotalShimmer: some View {
        Text(CartMath.formatCents(totalCents))
            .font(.brandDisplaySmall())
            .foregroundStyle(Color.bizarrePrimary.opacity(0.4))
            .monospacedDigit()
            .redacted(reason: .placeholder)
            .shimmering()
            .accessibilityHidden(true)
    }

    // MARK: - Discount flash logic

    private func triggerDiscountFlash() {
        discountFlashing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.4)) {
                discountFlashing = false
            }
        }
    }

    // MARK: - A11y announcement (§16 debounced screen reader)

    /// Debounces VoiceOver total announcements: waits 600ms after the last
    /// cart change before posting an accessibility notification.
    private func scheduleA11yAnnouncement() {
        a11yAnnounceTask?.cancel()
        a11yAnnounceTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, totalCents != announcedTotal else { return }
            announcedTotal = totalCents
            // Post an accessibility announcement so VoiceOver reads the new total.
            UIAccessibility.post(
                notification: .announcement,
                argument: "Total updated: \(CartMath.formatCents(totalCents))"
            )
        }
    }
}

// MARK: - Shimmer modifier

/// Applies a moving highlight gradient to simulate a loading shimmer.
private struct ShimmeringModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        .clear,
                        Color.white.opacity(0.4),
                        .clear
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 300 - 150)
                .animation(
                    .linear(duration: 1.0).repeatForever(autoreverses: false),
                    value: phase
                )
            )
            .clipped()
            .onAppear { phase = 1 }
    }
}

private extension View {
    func shimmering() -> some View {
        modifier(ShimmeringModifier())
    }
}

// MARK: - Preview

#Preview("Cart totals — animated") {
    @Previewable @State var discount = 0
    @Previewable @State var version = 0

    VStack {
        PosCartTotalsView(
            subtotalCents: 4999,
            discountCents: discount,
            taxCents: 412,
            totalCents: 4999 - discount + 412,
            isPendingValidation: false,
            cartVersion: version
        )
        .padding()

        Button("Apply $5 discount") {
            discount = 500
            version += 1
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
#endif
