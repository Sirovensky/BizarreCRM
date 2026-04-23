import SwiftUI
import Core
import DesignSystem

// MARK: - ImportEntityPickerView

/// Wizard step 2: choose the CRM entity type to import into.
/// Supports Customers, Inventory, and Tickets.
public struct ImportEntityPickerView: View {
    @Binding var selectedEntity: ImportEntityType
    let onContinue: () -> Void

    public init(selectedEntity: Binding<ImportEntityType>, onContinue: @escaping () -> Void) {
        self._selectedEntity = selectedEntity
        self.onContinue = onContinue
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                header

                LazyVGrid(columns: gridColumns, spacing: DesignTokens.Spacing.lg) {
                    ForEach(ImportEntityType.allCases, id: \.self) { entity in
                        EntityTile(
                            entity: entity,
                            isSelected: selectedEntity == entity,
                            onTap: { selectedEntity = entity }
                        )
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)

                continueButton
                    .padding(.horizontal, DesignTokens.Spacing.lg)
            }
            .padding(.top, DesignTokens.Spacing.xxl)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private var gridColumns: [GridItem] {
        // iPad: 3 columns. iPhone: 2 columns (entity count is 3, so 2-col wraps cleanly).
        if Platform.isCompact {
            return [GridItem(.flexible()), GridItem(.flexible())]
        } else {
            return [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Select Entity Type")
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
            Text("What type of records are you importing?")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .accessibilityAddTraits(.isHeader)
    }

    private var continueButton: some View {
        Button("Continue") { onContinue() }
            .buttonStyle(.brandGlassProminent)
            .tint(.bizarreOrange)
            .accessibilityIdentifier("import.entity.continue")
            .accessibilityLabel("Continue to upload \(selectedEntity.displayName)")
    }
}

// MARK: - EntityTile

private struct EntityTile: View {
    let entity: ImportEntityType
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: entity.systemImage)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text(entity.displayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 110)
            .padding(DesignTokens.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .fill(isSelected ? Color.bizarreOrange.opacity(0.12) : Color.bizarreSurface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                            .strokeBorder(
                                isSelected ? Color.bizarreOrange : Color.clear,
                                lineWidth: 2
                            )
                    )
            )
            .scaleEffect(isSelected && !reduceMotion ? 1.02 : 1.0)
            .animation(
                reduceMotion ? .none : .spring(response: DesignTokens.Motion.snappy, dampingFraction: 0.8),
                value: isSelected
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entity.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("import.entity.\(entity.rawValue)")
        #if canImport(UIKit)
        .hoverEffect(.highlight)
        #endif
    }
}
