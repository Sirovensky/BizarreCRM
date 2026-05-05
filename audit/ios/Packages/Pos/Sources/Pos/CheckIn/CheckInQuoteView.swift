/// CheckInQuoteView.swift — §16.25.5
///
/// Step 5: Repair quote — parts/services list, deposit picker, pinned totals bar.
/// Parts reservation queued via sync queue when offline.
/// Spec: mockup frame "CI-5 · Quote · parts reserved · deposit".

#if canImport(UIKit)
import SwiftUI
import DesignSystem

struct CheckInQuoteView: View {
    @Bindable var draft: CheckInDraft

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: BrandSpacing.lg) {
                    // Repair lines
                    if draft.laborCents > 0 || draft.partsCents > 0 {
                        repairLines
                    } else {
                        emptyQuoteState
                    }

                    Divider().padding(.horizontal, BrandSpacing.base)

                    // Deposit picker
                    depositPickerSection
                }
                .padding(.vertical, BrandSpacing.md)
                .padding(.bottom, 160) // space for pinned totals bar
            }

            // Pinned totals bar
            totalBar
        }
    }

    // MARK: - Repair lines

    private var repairLines: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Repair lines")
                .font(.brandTitleMedium())
                .foregroundStyle(Color.bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.base)

            VStack(spacing: 0) {
                if draft.laborCents > 0 {
                    lineRow(name: "Labor", amountCents: draft.laborCents, statusIcon: "checkmark.circle.fill", statusColor: .bizarreSuccess, statusLabel: "Reserved")
                    Divider().padding(.leading, BrandSpacing.xl)
                }
                if draft.partsCents > 0 {
                    lineRow(name: "Parts", amountCents: draft.partsCents, statusIcon: "clock.fill", statusColor: .bizarreWarning, statusLabel: "Ordered")
                }
            }
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
            )
            .padding(.horizontal, BrandSpacing.base)
        }
    }

    private func lineRow(name: String, amountCents: Int, statusIcon: String, statusColor: Color, statusLabel: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.bizarreOnSurface)
                Label(statusLabel, systemImage: statusIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            Spacer()
            Text(CartMath.formatCents(amountCents))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.bizarreOrange)
                .monospacedDigit()
        }
        .padding(BrandSpacing.md)
    }

    // MARK: - Empty state

    private var emptyQuoteState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
            Text("No repair lines added yet")
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
            Text("Add parts and labor from the repair catalog to generate a quote.")
                .font(.system(size: 12))
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
        }
        .padding(BrandSpacing.xl)
    }

    // MARK: - Deposit picker

    private var depositPickerSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Deposit")
                .font(.brandTitleMedium())
                .foregroundStyle(Color.bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.base)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(DepositPreset.allCases, id: \.self) { preset in
                        Button {
                            BrandHaptics.tap()
                            draft.depositPreset = preset
                        } label: {
                            Text(preset.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(draft.depositPreset == preset ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted)
                                .padding(.horizontal, BrandSpacing.md)
                                .padding(.vertical, BrandSpacing.xs)
                                .background(draft.depositPreset == preset ? Color.bizarreOrange : Color.bizarreSurface2, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
            }

            if draft.depositCents > 0 {
                Text("\(CartMath.formatCents(draft.depositCents)) deposit applied · balance due on pickup: \(CartMath.formatCents(max(0, draft.subtotalCents - draft.depositCents)))")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .padding(.horizontal, BrandSpacing.base)
            }
        }
    }

    // MARK: - Pinned totals bar

    private var totalBar: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: BrandSpacing.sm) {
                totalsRow(label: "Subtotal", cents: draft.subtotalCents)
                if draft.depositCents > 0 {
                    HStack {
                        Text("Deposit today")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.bizarreOrange)
                        Spacer()
                        Text("− \(CartMath.formatCents(draft.depositCents))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.bizarreOrange)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, BrandSpacing.base)
                }
                Divider().padding(.horizontal, BrandSpacing.base)
                totalsRow(label: "Due on pickup", cents: max(0, draft.subtotalCents - draft.depositCents), bold: true)
            }
            .padding(.vertical, BrandSpacing.md)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Subtotal \(CartMath.formatCents(draft.subtotalCents)). Due on pickup \(CartMath.formatCents(max(0, draft.subtotalCents - draft.depositCents)))")
        }
        .background(Color.bizarreSurfaceBase)
    }

    private func totalsRow(label: String, cents: Int, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(bold ? .system(size: 15, weight: .bold) : .system(size: 13))
                .foregroundStyle(Color.bizarreOnSurface)
            Spacer()
            Text(CartMath.formatCents(cents))
                .font(bold ? .system(size: 15, weight: .bold) : .system(size: 13, weight: .semibold))
                .foregroundStyle(Color.bizarreOnSurface)
                .monospacedDigit()
        }
        .padding(.horizontal, BrandSpacing.base)
    }
}
#endif
