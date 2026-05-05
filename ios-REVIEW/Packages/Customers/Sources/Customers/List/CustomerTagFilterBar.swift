#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - §5.7 Tag tap → filter customer list

/// Horizontal chip bar displayed below the list toolbar when a tag filter is active.
/// Tapping the chip clears the tag filter. Also exposes a helper that sets a tag
/// filter from a tag chip tap anywhere in the customer list or detail.
public struct CustomerTagFilterBar: View {
    public let tag: String
    public var onClear: () -> Void

    public init(tag: String, onClear: @escaping () -> Void) {
        self.tag = tag
        self.onClear = onClear
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: "tag.fill")
                .font(.system(size: 12))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text(tag)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
            Button {
                onClear()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel("Clear tag filter \(tag)")
            Spacer(minLength: 0)
            Text("Tag filter active")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .background(Color.bizarreOrange.opacity(0.08))
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.bizarreOrange.opacity(0.2))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Filtering by tag: \(tag). Tap X to clear.")
    }
}
#endif
