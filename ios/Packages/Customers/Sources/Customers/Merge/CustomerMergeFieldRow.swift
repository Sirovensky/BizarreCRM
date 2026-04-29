#if canImport(UIKit)
import SwiftUI
import DesignSystem

// §5.5 — Per-field toggle row in the merge diff table.

struct CustomerMergeFieldRowView: View {
    let row: MergeFieldRow
    let onToggle: (MergeFieldWinner) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(row.label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            HStack(spacing: BrandSpacing.sm) {
                side(
                    label: "Keep",
                    value: row.primaryValue,
                    isSelected: row.winner == .primary,
                    side: .primary
                )
                side(
                    label: "Merge in",
                    value: row.secondaryValue,
                    isSelected: row.winner == .secondary,
                    side: .secondary
                )
            }
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func side(label: String, value: String, isSelected: Bool, side: MergeFieldWinner) -> some View {
        let displayValue = value.isEmpty ? "—" : value
        Button {
            onToggle(side)
        } label: {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(isSelected ? .bizarreOrange : .bizarreOnSurfaceMuted)
                Text(displayValue)
                    .font(.brandBodyMedium())
                    .foregroundStyle(isSelected ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BrandSpacing.sm)
            .background(
                isSelected ? Color.bizarreOrange.opacity(0.10) : Color.bizarreSurface2,
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
            )
            // §26.5 — Increase Contrast: thicker, opaque border on selected
            // cards; faint separator on deselected cards. SwiftUI re-renders
            // automatically when the user toggles "Increase Contrast".
            .selectedCardBorder(
                isSelected: isSelected,
                cornerRadius: DesignTokens.Radius.sm,
                selectedColor: .bizarreOrange
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.label) — \(label): \(displayValue)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
