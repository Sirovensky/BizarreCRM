import SwiftUI
import Core
import DesignSystem

// MARK: - ImportSourcePickerView

public struct ImportSourcePickerView: View {
    @Binding var selectedSource: ImportSource?
    let onContinue: () -> Void

    public init(selectedSource: Binding<ImportSource?>, onContinue: @escaping () -> Void) {
        self._selectedSource = selectedSource
        self.onContinue = onContinue
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                header

                LazyVGrid(
                    columns: columns,
                    spacing: DesignTokens.Spacing.lg
                ) {
                    ForEach(ImportSource.allCases, id: \.self) { source in
                        SourceTile(
                            source: source,
                            isSelected: selectedSource == source,
                            onTap: { selectedSource = source }
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

    private var columns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Choose Source")
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
            Text("Select the system you're importing from")
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
            .disabled(selectedSource == nil)
            .accessibilityIdentifier("import.source.continue")
            .accessibilityLabel(selectedSource == nil
                ? "Continue, disabled — select a source first"
                : "Continue to upload")
    }
}

// MARK: - SourceTile

private struct SourceTile: View {
    let source: ImportSource
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: source.systemImage)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text(source.displayName)
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
        .accessibilityLabel(source.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("import.source.\(source.rawValue)")
        #if canImport(UIKit)
        .hoverEffect(.highlight)
        #endif
    }
}
