#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// POS cart flow sheet — "Enter coupon code".
///
/// Presented via the "Add Coupon" button in `PosCartPanel`'s totals footer.
/// On successful apply, posts `POST /coupons/apply` via `CouponInputViewModel`
/// and calls `onApplied` with the resulting coupon + discount amount.
///
/// Design:
/// - Liquid Glass header/toolbar (chrome only).
/// - Reduce Motion: no keyframe bounce on chip appear.
/// - A11y: VoiceOver announces "Coupon applied, saving X dollars" on success.
public struct CouponInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var vm: CouponInputViewModel

    public let onApplied: @MainActor (CouponCode, Int) -> Void

    public init(
        vm: CouponInputViewModel,
        onApplied: @escaping @MainActor (CouponCode, Int) -> Void
    ) {
        _vm = State(initialValue: vm)
        self.onApplied = onApplied
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.xl) {
                    headerIcon
                    inputRow
                    stateView
                    Spacer()
                }
                .padding(.top, BrandSpacing.lg)
                .padding(.horizontal, BrandSpacing.base)
            }
            .navigationTitle("Enter Coupon Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("couponInput.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isApplied {
                        Button("Done") {
                            if let coupon = vm.state.appliedCoupon {
                                onApplied(coupon, vm.state.discountCents)
                            }
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("couponInput.done")
                    } else {
                        Button("Apply") {
                            Task { await vm.apply() }
                        }
                        .fontWeight(.semibold)
                        .disabled(!vm.canApply)
                        .accessibilityIdentifier("couponInput.apply")
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sub-views

    private var headerIcon: some View {
        Image(systemName: "tag.fill")
            .font(.system(size: 44, weight: .regular))
            .foregroundStyle(.bizarreOrange)
            .accessibilityHidden(true)
    }

    private var inputRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            TextField("e.g. SAVE20", text: $vm.codeInput)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.brandHeadlineMedium().monospacedDigit())
                .foregroundStyle(.bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.md)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: BrandRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: BrandRadius.md)
                        .strokeBorder(inputBorderColor, lineWidth: 1.5)
                )
                .disabled(vm.isApplied || vm.state.isLoading)
                .accessibilityLabel("Coupon code")
                .accessibilityIdentifier("couponInput.field")

            if vm.state.isLoading {
                ProgressView()
                    .accessibilityLabel("Validating coupon")
            }
        }
    }

    private var inputBorderColor: Color {
        switch vm.state {
        case .applied: return .bizarreSuccess
        case .error: return .bizarreError
        default: return Color.bizarreOutline.opacity(0.5)
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch vm.state {
        case .idle, .loading:
            EmptyView()

        case .applied(let coupon, let cents):
            appliedChip(coupon: coupon, discountCents: cents)
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                .animation(.spring(duration: 0.35), value: vm.isApplied)
                .accessibilityAnnouncement("Coupon applied, saving \(CartMath.formatCents(cents))")

        case .error(let message):
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .multilineTextAlignment(.center)
            }
            .accessibilityIdentifier("couponInput.error")
        }
    }

    private func appliedChip(coupon: CouponCode, discountCents: Int) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(coupon.code)
                    .font(.brandLabelLarge().monospacedDigit())
                    .foregroundStyle(.bizarreOnSurface)
                Text("\(coupon.ruleName) — saves \(CartMath.formatCents(discountCents))")
                    .font(.brandBodySmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Button {
                vm.remove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove coupon \(coupon.code)")
            .accessibilityIdentifier("couponInput.remove")
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSuccess.opacity(0.08), in: RoundedRectangle(cornerRadius: BrandRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.md)
                .strokeBorder(Color.bizarreSuccess.opacity(0.3), lineWidth: 1)
        )
        .accessibilityIdentifier("couponInput.appliedChip")
    }
}
#endif
