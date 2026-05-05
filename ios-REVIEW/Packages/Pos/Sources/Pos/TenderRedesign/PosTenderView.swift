/// PosTenderView.swift — §16.23
///
/// Redesign-wave tender screen.
///
/// Layout:
///   - Hero balance card (TOTAL DUE / REMAINING + animated progress bar).
///   - Applied tenders section (success-tinted rows, ✕ to void).
///   - 2×2 tender grid (Card reader primary, others standard).
///   - Bottom CTA bar: disabled while remaining > 0; "Complete sale" when done.
///
/// Glass budget: 1 (bottom CTA bar when `isComplete`).
/// Haptics: `.success` when remaining hits 0; `.warning` on void.
///
/// ⚠ BlockChyp actual SDK calls live in Hardware module (Agent 2).
/// This view wires the UX shell; tile taps are forwarded via callbacks.

#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - PosTenderView

public struct PosTenderView: View {

    @Bindable var vm: PosTenderViewModel

    // Callbacks for tile taps — Hardware module (Agent 2) implements.
    public var onCardReaderTap: (() -> Void)?
    public var onTapToPayTap: (() -> Void)?
    public var onAchCheckTap: (() -> Void)?
    public var onParkCartTap: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        vm: PosTenderViewModel,
        onCardReaderTap: (() -> Void)? = nil,
        onTapToPayTap: (() -> Void)? = nil,
        onAchCheckTap: (() -> Void)? = nil,
        onParkCartTap: (() -> Void)? = nil
    ) {
        self.vm = vm
        self.onCardReaderTap = onCardReaderTap
        self.onTapToPayTap = onTapToPayTap
        self.onAchCheckTap = onAchCheckTap
        self.onParkCartTap = onParkCartTap
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color.bizarreSurfaceBase.ignoresSafeArea()

            ScrollView {
                VStack(spacing: BrandSpacing.lg) {
                    heroCard
                    if !vm.appliedTenders.isEmpty {
                        appliedTendersSection
                    }
                    tenderGrid
                    // Spacer for sticky bottom bar
                    Spacer().frame(height: 80)
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.top, BrandSpacing.lg)
            }

            // Sticky bottom CTA bar
            bottomBar
        }
        .navigationTitle("Tender")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(spacing: BrandSpacing.md) {
            HStack(alignment: .top) {
                // Left: TOTAL DUE
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOTAL DUE")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                        .tracking(1)
                    Text(CartMath.formatCents(vm.totalCents))
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Color.bizarreOnSurface)
                        .monospacedDigit()
                }

                Spacer()

                // Right: REMAINING
                VStack(alignment: .trailing, spacing: 4) {
                    Text("REMAINING")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                        .tracking(1)
                    Text(CartMath.formatCents(vm.remainingCents))
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(vm.isComplete ? Color.bizarreSuccess : Color.bizarreOrange)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .spring(duration: DesignTokens.Motion.smooth), value: vm.remainingCents)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Total due \(CartMath.formatCents(vm.totalCents)), remaining \(CartMath.formatCents(vm.remainingCents))")

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.bizarreSurface2)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(vm.isComplete ? Color.bizarreSuccess : Color.bizarreOrange)
                        .frame(width: geo.size.width * vm.progressFraction, height: 6)
                        .animation(reduceMotion ? nil : .spring(duration: DesignTokens.Motion.smooth), value: vm.progressFraction)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)

            HStack {
                if vm.paidCents > 0 {
                    Label("Paid \(CartMath.formatCents(vm.paidCents))", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.bizarreSuccess)
                }
                Spacer()
                if vm.progressFraction > 0 && !vm.isComplete {
                    Text("\(Int(vm.progressFraction * 100))%")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                }
            }
        }
        .padding(BrandSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(Color.bizarreSurface1)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                        .strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Applied tenders

    private var appliedTendersSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Label("PAID · \(vm.appliedTenders.count)", systemImage: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.bizarreSuccess)
                .tracking(1)

            ForEach(vm.appliedTenders) { tender in
                appliedTenderRow(tender)
            }
        }
    }

    private func appliedTenderRow(_ tender: AppliedTenderEntry) -> some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.bizarreSuccess)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text(tender.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.bizarreOnSurface)
                if let detail = tender.detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                }
            }

            Spacer()

            Text(CartMath.formatCents(tender.amountCents))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.bizarreOnSurface)
                .monospacedDigit()

            Button {
                vm.removeTender(id: tender.id)
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(tender.label) tender")
        }
        .padding(BrandSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(Color.bizarreSuccess.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .strokeBorder(Color.bizarreSuccess.opacity(0.25), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Tender grid (2×2)

    private var tenderGrid: some View {
        let columns = [GridItem(.flexible(), spacing: BrandSpacing.sm), GridItem(.flexible(), spacing: BrandSpacing.sm)]
        return LazyVGrid(columns: columns, spacing: BrandSpacing.sm) {
            ForEach(TenderGridTile.allCases) { tile in
                tenderTile(tile)
            }
        }
    }

    private func tenderTile(_ tile: TenderGridTile) -> some View {
        let isLoading = vm.loadingTile == tile
        let isDisabled = vm.isComplete

        return Button {
            guard !isDisabled else { return }
            BrandHaptics.tapMedium()
            tileAction(tile)
        } label: {
            VStack(spacing: BrandSpacing.sm) {
                if isLoading {
                    ProgressView()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: tile.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(tile.isPrimary ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                }
                Text(tile.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isDisabled ? Color.bizarreOnSurfaceMuted : Color.bizarreOnSurface)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 80)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .fill(Color.bizarreSurface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                            .strokeBorder(
                                tile.isPrimary ? Color.bizarreOrange.opacity(0.5) : Color.bizarreOutline.opacity(0.4),
                                lineWidth: tile.isPrimary ? 1 : 0.5
                            )
                    )
            )
            .opacity(isDisabled ? 0.4 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .hoverEffect(.highlight)
        .accessibilityLabel("\(tile.label) tender")
        .accessibilityHint(isDisabled ? "Payment complete" : "Double-tap to select")
    }

    private func tileAction(_ tile: TenderGridTile) {
        switch tile {
        case .cardReader: onCardReaderTap?()
        case .tapToPay: onTapToPayTap?()
        case .achCheck: onAchCheckTap?()
        case .parkCart: onParkCartTap?()
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                Task { await vm.completeSale() }
            } label: {
                Group {
                    if vm.isCompletingSale {
                        ProgressView()
                            .tint(Color.bizarreOnSurface)
                    } else if vm.isComplete {
                        Text("Complete sale")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.bizarreOnSurface)
                    } else {
                        Text("Remaining \(CartMath.formatCents(vm.remainingCents)) — add payment to finish")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background {
                    if vm.isComplete {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                    .fill(Color.bizarreOrange)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .fill(Color.bizarreSurface2)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!vm.isComplete || vm.isCompletingSale)
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.md)
        }
        .background(Color.bizarreSurfaceBase)
        .accessibilityIdentifier("pos.tender.completeSaleButton")
    }
}
#endif
