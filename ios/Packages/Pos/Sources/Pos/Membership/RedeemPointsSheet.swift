// MARK: - Module placement guard
// ─────────────────────────────────────────────────────────────────────────────
// Loyalty surfaces are CHECKOUT-ONLY.
// This sheet is presented ONLY from the tender-method-picker screen, via the
// "REDEEM PTS" button on `MembershipBenefitBanner`.
// DO NOT present from: Cart, Catalog, Customer gate, Inspector, or Receipt.
// See LoyaltyTier.swift for the full restriction note.
// ─────────────────────────────────────────────────────────────────────────────

#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core
import Networking

/// Mid-tender sheet that lets the cashier apply loyalty points as a discount.
///
/// Presented with `.presentationDetents([.medium])`.
/// Validates:
///  - `requestedPoints > 0`
///  - `requestedPoints ≤ vm.account.pointsBalance`
///  - equivalent discount `≤ cartSubtotalCents`
///
/// On confirm: calls `vm.redeem(points:)` and dismisses.
/// On server 501 (points ledger not yet deployed): shows a "coming soon" banner
/// and dismisses without applying.
public struct RedeemPointsSheet: View {

    @Bindable var vm: MembershipViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// In-progress invoice id for the audit log (nil if not yet created).
    let invoiceId: Int64?

    @State private var pointsInput: String = ""
    @State private var validationError: String? = nil
    @State private var isApplying: Bool = false
    @State private var comingSoonVisible: Bool = false

    public init(vm: MembershipViewModel, invoiceId: Int64? = nil) {
        self.vm = vm
        self.invoiceId = invoiceId
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let account = vm.account {
                        accountSummary(account: account)
                        pointsEntry(account: account)
                        discountPreview
                        if let error = validationError {
                            errorBanner(message: error)
                        }
                        if comingSoonVisible {
                            comingSoonBanner
                        }
                    } else {
                        noAccountPlaceholder
                    }
                }
                .padding(20)
            }
            .navigationTitle("Redeem Points")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        BrandHaptics.tap()
                        dismiss()
                    }
                    .accessibilityLabel("Cancel redemption")
                }
                ToolbarItem(placement: .confirmationAction) {
                    confirmButton
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Pre-fill with the maximum redeemable amount for convenience.
            if vm.maxRedeemablePoints > 0 {
                pointsInput = "\(vm.maxRedeemablePoints)"
            }
        }
    }

    // MARK: - Account summary card

    private func accountSummary(account: LoyaltyAccount) -> some View {
        HStack(spacing: 12) {
            Text("★")
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(account.tier.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(account.tier.displayName.uppercased()) MEMBER")
                    .font(.brandLabelLarge().bold())
                    .foregroundStyle(primaryColor)
                Text("\(account.pointsBalance) pts available · max \(CartMath.formatCents(vm.pointsToCents(vm.maxRedeemablePoints))) redeemable")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(primaryColor.opacity(colorScheme == .dark ? 0.08 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(primaryColor.opacity(0.25), lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(account.tier.displayName) member with \(account.pointsBalance) points available.")
    }

    // MARK: - Points entry

    private func pointsEntry(account: LoyaltyAccount) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Points to redeem")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)

            HStack(spacing: 10) {
                TextField("0", text: $pointsInput)
                    .keyboardType(.numberPad)
                    .font(.brandHeadlineLarge().monospacedDigit())
                    .foregroundStyle(.bizarreOnSurface)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(
                                        validationError != nil
                                            ? Color.bizarreError.opacity(0.7)
                                            : Color.bizarreOutline.opacity(0.4),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .onChange(of: pointsInput) { _, _ in
                        validationError = nil
                        comingSoonVisible = false
                    }
                    .accessibilityLabel("Points to redeem. Maximum \(vm.maxRedeemablePoints).")

                // Max button
                Button("Max") {
                    pointsInput = "\(vm.maxRedeemablePoints)"
                    validationError = nil
                    BrandHaptics.tap()
                }
                .font(.brandLabelLarge().bold())
                .foregroundStyle(primaryColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(primaryColor.opacity(0.10))
                        .overlay(Capsule().strokeBorder(primaryColor.opacity(0.30), lineWidth: 0.5))
                )
                .buttonStyle(.borderless)
                .accessibilityLabel("Set to maximum redeemable points: \(vm.maxRedeemablePoints)")
            }

            Text("10 pts = $1.00 discount (max \(vm.maxRedeemablePoints) pts / \(CartMath.formatCents(vm.pointsToCents(vm.maxRedeemablePoints))))")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - Discount preview

    @ViewBuilder
    private var discountPreview: some View {
        if let pts = Int(pointsInput), pts > 0 {
            let cents = vm.pointsToCents(pts)
            HStack {
                Text("Discount applied")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text("− \(CartMath.formatCents(cents))")
                    .font(.brandBodyMedium().bold().monospacedDigit())
                    .foregroundStyle(.bizarreSuccess)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.bizarreSuccess.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.bizarreSuccess.opacity(0.25), lineWidth: 0.5)
                    )
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Discount: \(CartMath.formatCents(cents))")
        }
    }

    // MARK: - Error banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreError)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.bizarreError.opacity(0.08))
        )
        .accessibilityLabel("Error: \(message)")
    }

    // MARK: - Coming-soon banner

    private var comingSoonBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.fill")
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)
            Text("Points redemption is coming soon — the server endpoint is not yet live.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreWarning)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.bizarreWarning.opacity(0.08))
        )
    }

    // MARK: - No-account placeholder

    private var noAccountPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No loyalty account found.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Confirm button

    private var confirmButton: some View {
        Group {
            if isApplying {
                ProgressView()
                    .controlSize(.small)
                    .tint(primaryColor)
            } else {
                Button("Apply") {
                    applyRedemption()
                }
                .font(.brandLabelLarge().bold())
                .foregroundStyle(primaryColor)
                .disabled(parsedPoints <= 0)
                .accessibilityLabel("Apply point redemption.")
                .accessibilityHint("Applies the entered points as a discount.")
            }
        }
    }

    // MARK: - Apply logic

    private var parsedPoints: Int { Int(pointsInput) ?? 0 }

    private func applyRedemption() {
        let pts = parsedPoints
        guard pts > 0 else {
            validationError = "Enter a number of points greater than zero."
            return
        }
        guard let account = vm.account else { return }

        // Client-side validation before the network call
        if pts > account.pointsBalance {
            validationError = "You only have \(account.pointsBalance) pts available."
            BrandHaptics.error()
            return
        }
        let discountCents = vm.pointsToCents(pts)
        if discountCents > vm.cartSubtotalCents {
            validationError = "Discount (\(CartMath.formatCents(discountCents))) exceeds cart total (\(CartMath.formatCents(vm.cartSubtotalCents)))."
            BrandHaptics.error()
            return
        }

        isApplying = true
        Task {
            defer { isApplying = false }
            do {
                try await vm.redeem(points: pts, invoiceId: invoiceId)
                BrandHaptics.success()
                dismiss()
            } catch LoyaltyRedemptionError.insufficientPoints(let available, _) {
                validationError = "Only \(available) pts available."
                BrandHaptics.error()
            } catch LoyaltyRedemptionError.exceedsCartTotal(let discount, let total) {
                validationError = "Discount \(CartMath.formatCents(discount)) exceeds cart \(CartMath.formatCents(total))."
                BrandHaptics.error()
            } catch LoyaltyRedemptionError.invalidPointsAmount {
                validationError = "Invalid points amount."
                BrandHaptics.error()
            } catch let err as APITransportError {
                if case .httpStatus(501, _) = err {
                    // Server endpoint not yet deployed
                    comingSoonVisible = true
                } else {
                    AppLog.pos.error("RedeemPointsSheet: network error \(err)")
                    validationError = "Redemption failed. Try again."
                    BrandHaptics.error()
                }
            } catch {
                AppLog.pos.error("RedeemPointsSheet: unexpected error \(error)")
                validationError = "Redemption failed. Try again."
                BrandHaptics.error()
            }
        }
    }

    // MARK: - Colors

    private var primaryColor: Color {
        colorScheme == .dark
            ? Color(red: 0.992, green: 0.933, blue: 0.816)   // #fdeed0 cream
            : .bizarreOrange
    }
}
#endif
