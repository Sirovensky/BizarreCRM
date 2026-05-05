#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16.16 — 3-tile quick-sale row rendered above the cart.
/// Each tile adds the configured SKU to the cart in one tap.
public struct QuickSaleButtonsView: View {
    let cart:    Cart
    let hotkeys: QuickSaleHotkeys
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(cart: Cart, hotkeys: QuickSaleHotkeys) {
        self.cart    = cart
        self.hotkeys = hotkeys
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            ForEach(0..<3, id: \.self) { idx in
                tile(for: hotkeys.slots[idx], index: idx)
            }
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .accessibilityIdentifier("quickSale.buttonRow")
    }

    @ViewBuilder
    private func tile(for hotkey: QuickSaleHotkey?, index: Int) -> some View {
        if let hotkey {
            Button {
                addToCart(hotkey)
            } label: {
                VStack(spacing: BrandSpacing.xxs) {
                    Text(hotkey.displayName)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    Text(CartMath.formatCents(hotkey.unitPriceCents))
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOrange)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, BrandSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .fill(Color.bizarreSurface1)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel("\(hotkey.displayName), \(CartMath.formatCents(hotkey.unitPriceCents))")
            .accessibilityHint("Double tap to add to cart")
            .accessibilityIdentifier("quickSale.tile.\(index)")
        } else {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                .fill(Color.bizarreSurface1.opacity(0.4))
                .frame(maxWidth: .infinity, minHeight: 48)
                .overlay(
                    Image(systemName: "plus")
                        .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.5))
                )
                .accessibilityHidden(true)
        }
    }

    private func addToCart(_ hotkey: QuickSaleHotkey) {
        let price = Decimal(hotkey.unitPriceCents) / 100
        let item  = CartItem(
            inventoryItemId: hotkey.inventoryId,
            name:            hotkey.displayName,
            sku:             hotkey.sku,
            unitPrice:       price
        )
        cart.add(item)
        BrandHaptics.tap()
    }
}
#endif
