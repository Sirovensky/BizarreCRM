#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §6.10 Variant Selector View (POS cart)

/// Shown at POS cart when the picked item has variants.
/// Grid of color swatches + size buttons with A11y support.
public struct VariantSelectorView: View {
    let variants: [InventoryVariant]
    let onSelect: (InventoryVariant) -> Void

    @State private var selectedId: Int64?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(variants: [InventoryVariant], onSelect: @escaping (InventoryVariant) -> Void) {
        self.variants = variants
        self.onSelect = onSelect
        _selectedId = State(wrappedValue: variants.first?.id)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            axisSection(forAttribute: "color", title: "Color", isSwatchStyle: true)
            axisSection(forAttribute: "size", title: "Size", isSwatchStyle: false)
            axisSection(forAttribute: "storage", title: "Storage", isSwatchStyle: false)

            if let selected = variants.first(where: { $0.id == selectedId }) {
                selectedInfo(selected)
            }
        }
        .padding(BrandSpacing.md)
    }

    // MARK: Axis row

    @ViewBuilder
    private func axisSection(forAttribute key: String, title: String, isSwatchStyle: Bool) -> some View {
        let values = VariantStockAggregator.distinctValues(variants: variants, forAttribute: key)
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text(title)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)

                if isSwatchStyle {
                    colorSwatches(values: values, key: key)
                } else {
                    pillButtons(values: values, key: key)
                }
            }
        }
    }

    // MARK: Color swatches

    private func colorSwatches(values: [String], key: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                ForEach(values, id: \.self) { value in
                    let isSelected = selectedVariant(forKey: key, value: value)?.id == selectedId
                    let inStock = selectedVariant(forKey: key, value: value)?.stock ?? 0 > 0

                    Circle()
                        .fill(colorFromName(value))
                        .frame(width: 36, height: 36)
                        .overlay {
                            if isSelected {
                                Circle()
                                    .stroke(Color.bizarreOrange, lineWidth: 3)
                            }
                        }
                        .opacity(inStock ? 1.0 : 0.4)
                        .scaleEffect(isSelected ? 1.1 : 1.0)
                        .animation(reduceMotion ? nil : .spring(response: 0.25), value: isSelected)
                        .onTapGesture { select(key: key, value: value) }
                        .accessibilityLabel("\(value)\(isSelected ? ", selected" : "")\(!inStock ? ", out of stock" : "")")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Pill buttons

    private func pillButtons(values: [String], key: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.xs) {
                ForEach(values, id: \.self) { value in
                    let isSelected = selectedVariant(forKey: key, value: value)?.id == selectedId
                    let inStock = (selectedVariant(forKey: key, value: value)?.stock ?? 0) > 0

                    Text(value)
                        .font(.brandBodyMedium())
                        .foregroundStyle(isSelected ? .white : .bizarreOnSurface)
                        .padding(.horizontal, BrandSpacing.sm)
                        .padding(.vertical, BrandSpacing.xs)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? Color.bizarreOrange : Color.bizarreSurface1)
                        }
                        .opacity(inStock ? 1.0 : 0.4)
                        .scaleEffect(isSelected ? 1.05 : 1.0)
                        .animation(reduceMotion ? nil : .spring(response: 0.25), value: isSelected)
                        .onTapGesture { select(key: key, value: value) }
                        .accessibilityLabel("\(value)\(isSelected ? ", selected" : "")\(!inStock ? ", out of stock" : "")")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Selected info

    private func selectedInfo(_ variant: InventoryVariant) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(variant.displayLabel)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text("SKU: \(variant.sku)")
                    .font(.brandMono(size: 11))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .textSelection(.enabled)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                Text(variant.retailCents.formattedAsCurrency)
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOrange)
                    .monospacedDigit()
                Text("In stock: \(variant.stock)")
                    .font(.brandLabelLarge())
                    .foregroundStyle(variant.stock > 0 ? .bizarreSuccess : .bizarreError)
            }
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Selected: \(variant.displayLabel), \(variant.retailCents.formattedAsCurrency), \(variant.stock) in stock")
    }

    // MARK: Helpers

    private func selectedVariant(forKey key: String, value: String) -> InventoryVariant? {
        // If current selection has this key/value, show it; else first match
        if let current = variants.first(where: { $0.id == selectedId }),
           current.attributes[key] == value {
            return current
        }
        return variants.first(where: { $0.attributes[key] == value })
    }

    private func select(key: String, value: String) {
        // Find a variant matching all currently-selected attributes plus the new one
        let currentAttrs: [String: String] = variants.first(where: { $0.id == selectedId })?.attributes ?? [:]
        var targetAttrs = currentAttrs
        targetAttrs[key] = value

        if let match = variants.first(where: { v in
            targetAttrs.allSatisfy { k, val in v.attributes[k] == val }
        }) {
            selectedId = match.id
            onSelect(match)
        } else if let partial = variants.first(where: { $0.attributes[key] == value }) {
            selectedId = partial.id
            onSelect(partial)
        }
    }

    private func colorFromName(_ name: String) -> Color {
        switch name.lowercased() {
        case "red":    return .red
        case "blue":   return .blue
        case "green":  return .green
        case "black":  return .black
        case "white":  return Color(white: 0.9)
        case "gold":   return Color(red: 0.83, green: 0.68, blue: 0.21)
        case "silver": return Color(white: 0.75)
        case "purple": return .purple
        case "yellow": return .yellow
        case "pink":   return .pink
        default:
            // Deterministic color from hash
            var hash = 5381
            for c in name.unicodeScalars { hash = ((hash << 5) &+ hash) &+ Int(c.value) }
            let h = Double(abs(hash) % 360) / 360.0
            return Color(hue: h, saturation: 0.7, brightness: 0.8)
        }
    }
}

// MARK: - Money formatting helper

private extension Int {
    var formattedAsCurrency: String {
        let dollars = Double(self) / 100.0
        return String(format: "$%.2f", dollars)
    }
}
#endif
