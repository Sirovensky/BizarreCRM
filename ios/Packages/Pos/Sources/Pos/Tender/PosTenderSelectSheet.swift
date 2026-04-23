#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §16.6 — Tender-selection sheet presented when the cashier taps "Charge".
///
/// Displays four tender chips: Cash (functional), Card, Gift card, Store
/// credit. The three non-cash options show a "requires hardware paired"
/// banner and disable the "Continue" button so the cashier can't
/// accidentally advance without real payment confirmation.
///
/// Cash tapping → dismisses this sheet and presents `PosCashTenderSheet`.
///
/// Layout: glass toolbar header + four chips + subtitle row. Glass reserved
/// for the header toolbar only (per CLAUDE.md). Content rows are plain.
struct PosTenderSelectSheet: View {
    let totalCents: Int
    let onSelectCash: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selected: TenderKind = .cash

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    totalHeader
                    methodGrid
                    unavailableBanner
                    Spacer(minLength: 0)
                    continueButton
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.bottom, BrandSpacing.lg)
                }
            }
            .navigationTitle("Payment method")
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

    // MARK: - Total header

    private var totalHeader: some View {
        VStack(spacing: BrandSpacing.xxs) {
            Text("Total due")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(CartMath.formatCents(totalCents))
                .font(.brandHeadlineLarge())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .fontDesign(.rounded)
        }
        .padding(.top, BrandSpacing.md)
        .padding(.bottom, BrandSpacing.lg)
    }

    // MARK: - Method chips grid

    private var methodGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: BrandSpacing.sm) {
            ForEach(TenderKind.allCases, id: \.self) { kind in
                TenderChip(
                    kind: kind,
                    isSelected: selected == kind,
                    onTap: { selected = kind }
                )
            }
        }
        .padding(.horizontal, BrandSpacing.base)
    }

    // MARK: - Unavailable banner

    @ViewBuilder
    private var unavailableBanner: some View {
        if !selected.isAvailableWithoutHardware, let msg = selected.hardwareRequiredMessage {
            HStack(alignment: .top, spacing: BrandSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.bizarreWarning)
                    .font(.system(size: 16))
                    .accessibilityHidden(true)
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(BrandSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bizarreWarning.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.bizarreWarning.opacity(0.3), lineWidth: 0.5)
            )
            .padding(.horizontal, BrandSpacing.base)
            .padding(.top, BrandSpacing.md)
            .transition(.opacity)
            .accessibilityIdentifier("pos.tender.unavailableBanner")
        }
    }

    // MARK: - Continue button

    private var continueButton: some View {
        Button {
            if selected == .cash {
                dismiss()
                onSelectCash()
            }
            // Non-cash: button is disabled — tapping has no effect.
        } label: {
            Text("Continue with \(selected.displayName)")
                .font(.brandTitleMedium())
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.md)
                .foregroundStyle(.black)
        }
        .buttonStyle(.borderedProminent)
        .tint(selected.isAvailableWithoutHardware ? .bizarreOrange : .bizarreOnSurfaceMuted)
        .disabled(!selected.isAvailableWithoutHardware)
        .controlSize(.large)
        .accessibilityIdentifier("pos.tender.continueButton")
        .accessibilityLabel("Continue with \(selected.displayName)")
        .accessibilityHint(selected.isAvailableWithoutHardware ? "" : "Not available — \(selected.hardwareRequiredMessage ?? "")")
    }
}

// MARK: - Tender chip

/// Individual selectable tile for one payment method.
private struct TenderChip: View {
    let kind: TenderKind
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(isSelected ? .bizarreOrange : iconColor)
                    .accessibilityHidden(true)
                Text(kind.displayName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(isSelected ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
                if !kind.isAvailableWithoutHardware {
                    Text("Hardware required")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected
                          ? Color.bizarreOrange.opacity(0.10)
                          : Color.bizarreSurface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected ? Color.bizarreOrange : Color.bizarreOutline.opacity(0.4),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(
            kind.isAvailableWithoutHardware
                ? kind.displayName
                : "\(kind.displayName) — Hardware required"
        )
        .accessibilityIdentifier("pos.tender.chip.\(kind.rawValue)")
    }

    private var iconColor: Color {
        kind.isAvailableWithoutHardware ? .bizarreOnSurface : .bizarreOnSurfaceMuted
    }
}

#Preview("Tender Select") {
    PosTenderSelectSheet(totalCents: 4275, onSelectCash: {})
        .preferredColorScheme(.dark)
}
#endif
