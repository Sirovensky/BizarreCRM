#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16.5 — Tender method selection sheet. Shown when the cashier taps
/// "Charge" on a non-fully-tendered cart.
///
/// Layout:
/// - Glass navigation bar (per CLAUDE.md chrome rule).
/// - "Total due" header.
/// - 2×2 grid of `TenderChip` tiles.
/// - Unavailable-method warning banner.
/// - "Continue with [method]" primary action — disabled for hardware-gated methods.
///
/// Only `.cash` is actionable without a paired terminal. Others render
/// with a muted style and show a descriptive banner when selected.
public struct PosTenderSelectSheet: View {
    public let totalCents: Int
    public let onSelectCash: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: TenderKind = .cash

    public init(totalCents: Int, onSelectCash: @escaping () -> Void) {
        self.totalCents = totalCents
        self.onSelectCash = onSelectCash
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                scrollContent
            }
            .navigationTitle("Select payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var scrollContent: some View {
        VStack(spacing: BrandSpacing.lg) {
            totalHeader
                .padding(.top, BrandSpacing.lg)

            tenderGrid
                .padding(.horizontal, BrandSpacing.base)

            if let banner = selected.hardwareRequiredMessage {
                unavailableBanner(message: banner)
                    .padding(.horizontal, BrandSpacing.base)
            }

            continueButton
                .padding(.horizontal, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.lg)
        }
    }

    private var totalHeader: some View {
        VStack(spacing: BrandSpacing.xxs) {
            Text("Total due")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(CartMath.formatCents(totalCents))
                .font(.brandHeadlineLarge())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .accessibilityIdentifier("pos.tenderSelect.total")
        }
    }

    private var tenderGrid: some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: BrandSpacing.sm) {
            ForEach(TenderKind.allCases, id: \.self) { kind in
                TenderChip(
                    kind: kind,
                    isSelected: selected == kind,
                    onTap: { selected = kind }
                )
            }
        }
    }

    @ViewBuilder
    private func unavailableBanner(message: String) -> some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreWarning)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BrandSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreWarning.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("pos.tenderSelect.unavailableBanner")
    }

    private var continueButton: some View {
        Button {
            switch selected {
            case .cash:
                dismiss()
                onSelectCash()
            case .card, .giftCard, .storeCredit:
                break   // disabled; button shouldn't be tappable
            }
        } label: {
            Text("Continue with \(selected.displayName)")
                .font(.brandTitleMedium())
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.md)
                .foregroundStyle(selected.isAvailableWithoutHardware ? .black : .bizarreOnSurfaceMuted)
        }
        .buttonStyle(.borderedProminent)
        .tint(selected.isAvailableWithoutHardware ? .bizarreOrange : Color.bizarreSurface1)
        .disabled(!selected.isAvailableWithoutHardware)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityIdentifier("pos.tenderSelect.continueButton")
    }
}

// MARK: - TenderChip

private struct TenderChip: View {
    let kind: TenderKind
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(iconColor)
                Text(kind.displayName)
                    .font(.brandLabelLarge())
                    .foregroundStyle(labelColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(kind.isAvailableWithoutHardware ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(kind.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("pos.tenderChip.\(kind.rawValue)")
    }

    @ViewBuilder
    private var background: some View {
        if isSelected {
            Color.bizarreOrange.opacity(0.15)
        } else {
            Color.bizarreSurface1
        }
    }

    private var borderColor: Color {
        isSelected ? .bizarreOrange : .bizarreOutline
    }

    private var iconColor: Color {
        isSelected ? .bizarreOrange : .bizarreOnSurfaceMuted
    }

    private var labelColor: Color {
        isSelected ? .bizarreOnSurface : .bizarreOnSurfaceMuted
    }
}

#Preview {
    PosTenderSelectSheet(totalCents: 12_109, onSelectCash: {})
        .preferredColorScheme(.dark)
}
#endif
