#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16 Customer-Facing Display — full-screen layout for the secondary
/// iPad / external HDMI screen that shows the live cart to the customer.
///
/// Layout zones:
/// - **Header** (Liquid Glass): merchant logo / brand name.
/// - **Content**: idle screen or scrollable cart lines.
/// - **Footer** (Liquid Glass): subtotal / tax / tip / total summary, huge type.
///
/// Accessibility: VoiceOver reads out the item count and grand total so an
/// operator can verify what the customer sees hands-free.
/// Reduce Motion: scale transitions are replaced by opacity fades.
///
/// This view is hosted in the `"cfd"` `WindowGroup` in `BizarreCRMApp.swift`
/// (advisory-lock zone — see agent-ownership.md). Do NOT call it from the
/// main POS scene.
public struct CFDView: View {

    private let bridge: CFDBridge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(bridge: CFDBridge = .shared) {
        self.bridge = bridge
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color.bizarreSurfaceBase.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .zIndex(1)

                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
                    .zIndex(1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityCartSummary)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Spacer()
            Text("BizarreCRM")
                .font(.brandDisplayMedium())
                .foregroundStyle(.bizarreOrange)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .padding(.vertical, BrandSpacing.lg)
        .background(
            Rectangle()
                .brandGlass(.regular, in: Rectangle())
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        if bridge.isActive {
            cartLines
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        } else {
            CFDIdleView()
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.02)))
        }
    }

    private var cartLines: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(bridge.items) { line in
                    CFDLineRow(line: line)
                        .padding(.horizontal, BrandSpacing.xl)
                        .padding(.vertical, BrandSpacing.sm)
                }
            }
            .padding(.vertical, BrandSpacing.md)
        }
        .accessibilityIdentifier("cfd.cartLines")
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: BrandSpacing.sm) {
            Divider()
                .background(Color.bizarreOutline.opacity(0.3))

            HStack(spacing: BrandSpacing.xl) {
                totalsColumn(label: "Subtotal", cents: bridge.subtotalCents)
                if bridge.taxCents > 0 {
                    totalsColumn(label: "Tax", cents: bridge.taxCents)
                }
                if bridge.tipCents > 0 {
                    totalsColumn(label: "Tip", cents: bridge.tipCents)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                    Text("TOTAL")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(CartMath.formatCents(bridge.totalCents))
                        .font(.brandDisplayLarge())
                        .foregroundStyle(.bizarreOrange)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(bridge.totalCents)))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: bridge.totalCents)
                }
            }
            .padding(.horizontal, BrandSpacing.xl)
            .padding(.vertical, BrandSpacing.lg)

            if bridge.isActive {
                Text("Please wait for your cashier")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(.bottom, BrandSpacing.md)
                    .accessibilityIdentifier("cfd.waitMessage")
            }
        }
        .background(
            Rectangle()
                .brandGlass(.regular, in: Rectangle())
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func totalsColumn(label: String, cents: Int) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(CartMath.formatCents(cents))
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(cents)))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: cents)
        }
    }

    // MARK: - Accessibility helpers

    private var accessibilityCartSummary: String {
        if bridge.isActive {
            return "\(bridge.items.count) item\(bridge.items.count == 1 ? "" : "s"), total \(CartMath.formatCents(bridge.totalCents))"
        } else {
            return "Customer display idle"
        }
    }
}

// MARK: - CFDLineRow

private struct CFDLineRow: View {
    let line: CFDCartLine

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Text("\(line.quantity)×")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(minWidth: 32, alignment: .trailing)
                .accessibilityHidden(true)

            Text(line.name)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(CartMath.formatCents(line.lineTotalCents))
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(line.quantity) \(line.name), \(CartMath.formatCents(line.lineTotalCents))")
    }
}
#endif
