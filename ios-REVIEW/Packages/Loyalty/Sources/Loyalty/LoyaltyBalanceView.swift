import SwiftUI
import DesignSystem
import Networking
#if canImport(PassKit)
import PassKit
#endif

/// §38 — Loyalty balance card shown on CustomerDetailView.
///
/// Layout:
///   - Glass card header with tier badge (Bronze / Silver / Gold / Platinum).
///   - Large monospaced point total (Reduce Motion aware).
///   - Lifetime spend + member-since footnote.
///   - "Add to Apple Wallet" button (PassKit style when available).
///
/// State machine mirrors `LoyaltyBalanceViewModel.State`:
///   - loading   → `ProgressView`
///   - loaded    → full card
///   - comingSoon → placeholder pill
///   - failed    → error row with retry
///
/// DO NOT add the Wallet entitlement — that is a separate Apple developer
/// step owned by the merchant. The button compiles regardless; the server
/// must sign the pass with the correct merchant identifier before the sheet
/// will actually succeed at runtime.
public struct LoyaltyBalanceView: View {
    @State private var vm: LoyaltyBalanceViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let customerId: Int64

    public init(api: APIClient, customerId: Int64) {
        _vm = State(wrappedValue: LoyaltyBalanceViewModel(api: api))
        self.customerId = customerId
    }

    public var body: some View {
        Group {
            switch vm.state {
            case .loading:
                loadingView
            case .loaded:
                if let balance = vm.balance {
                    balanceCard(balance)
                }
            case .comingSoon:
                comingSoonView
            case .failed(let msg):
                failedView(msg)
            }
        }
        .task { await vm.loadBalance(customerId: customerId) }
    }

    // MARK: - Loading

    private var loadingView: some View {
        HStack {
            ProgressView()
                .accessibilityLabel("Loading loyalty balance")
            Text("Loading loyalty…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.base)
    }

    // MARK: - Loaded card

    @ViewBuilder
    private func balanceCard(_ balance: LoyaltyBalance) -> some View {
        let tier = LoyaltyTier.parse(balance.tier)

        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // Glass header with tier badge — glass on chrome only.
            tierHeader(tier)
                .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))

            // Points + spend body
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                pointsRow(balance.points)
                spendRow(balance.lifetimeSpendCents, memberSince: balance.memberSince)
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.sm)

            // "Add to Apple Wallet" button
            walletButton(balance: balance)
                .padding(.horizontal, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.base)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(Color.bizarreSurface1)
        )
        .shadow(
            color: Color.black.opacity(DesignTokens.Shadows.sm.opacityLight),
            radius: DesignTokens.Shadows.sm.blur,
            y: DesignTokens.Shadows.sm.y
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cardAccessibilityLabel(balance, tier: tier))
    }

    private func tierHeader(_ tier: LoyaltyTier) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: tier.systemSymbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tier.displayColor)
                .accessibilityHidden(true)

            Text(tier.displayName)
                .font(.brandTitleMedium())
                .foregroundStyle(tier.displayColor)

            Spacer()

            // Tier badge pill
            Text("LOYALTY")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xxs)
                .background(
                    Capsule().fill(Color.bizarreSurface2)
                )
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.md)
    }

    private func pointsRow(_ points: Int) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.xs) {
                Text(points.formatted(.number))
                    .font(.brandMono(size: 36))
                    .foregroundStyle(.bizarreOnSurface)
                    .animation(
                        reduceMotion ? .none : BrandMotion.statusChange,
                        value: points
                    )
                    .accessibilityLabel("\(points) loyalty points")

                Text("pts")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            // Copy chip — lets staff paste the balance into comms or POS notes.
            PointsBalanceCopyChip(points: points)
        }
        .padding(.top, BrandSpacing.sm)
    }

    private func spendRow(_ lifetimeSpendCents: Int, memberSince: String) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            let dollars = Double(lifetimeSpendCents) / 100.0
            Text("Lifetime spend: \(dollars, format: .currency(code: "USD"))")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            Text("Member since \(formattedDate(memberSince))")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    @ViewBuilder
    private func walletButton(balance: LoyaltyBalance) -> some View {
#if canImport(PassKit) && canImport(UIKit)
        if PKAddPassesViewController.canAddPasses() {
            Button {
                Task { await handleAddToWallet(balance: balance) }
            } label: {
                // Approximate the PKAddPassButton appearance using
                // system chrome — actual PKAddPassButton requires UIKit
                // integration which belongs in the UIKit host layer.
                Label("Add to Apple Wallet", systemImage: "wallet.pass")
                    .font(.brandTitleSmall())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black)
            .accessibilityLabel("Add loyalty card to Apple Wallet")
            .accessibilityHint("Downloads and presents the Wallet pass for this customer")
        }
#else
        EmptyView()
#endif
    }

    // MARK: - Coming soon

    private var comingSoonView: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "clock")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("Loyalty coming soon")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.base)
        .accessibilityLabel("Loyalty balance not yet available")
    }

    // MARK: - Failed

    private func failedView(_ message: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Couldn't load loyalty")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text(message)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Button("Retry") {
                Task { await vm.loadBalance(customerId: customerId) }
            }
            .font(.brandLabelLarge())
            .foregroundStyle(.bizarreOrange)
            .accessibilityLabel("Retry loading loyalty balance")
        }
        .padding(BrandSpacing.base)
    }

    // MARK: - Wallet action

    private func handleAddToWallet(balance: LoyaltyBalance) async {
        await vm.downloadPass(customerId: balance.customerId)
#if canImport(PassKit) && canImport(UIKit)
        if let data = vm.passData {
            do {
                try LoyaltyPassPresenter().present(passData: data)
            } catch {
                // Present error inline; do not re-set vm.state to avoid
                // wiping the loaded card away.
            }
        }
#endif
    }

    // MARK: - Helpers

    private func formattedDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        if let date = formatter.date(from: iso) {
            let out = DateFormatter()
            out.dateStyle = .medium
            out.timeStyle = .none
            return out.string(from: date)
        }
        return iso
    }

    private func cardAccessibilityLabel(_ balance: LoyaltyBalance, tier: LoyaltyTier) -> String {
        let dollars = Double(balance.lifetimeSpendCents) / 100.0
        let spend = String(format: "%.2f", dollars)
        return "\(tier.displayName) loyalty member. \(balance.points) points. " +
               "Lifetime spend $\(spend). Member since \(formattedDate(balance.memberSince))."
    }
}

// MARK: - Points balance copy chip

/// Compact tappable chip that copies the formatted points balance to the clipboard.
///
/// Tapping briefly shows a "Copied!" confirmation then resets.
private struct PointsBalanceCopyChip: View {
    let points: Int

    @State private var copied = false

    var body: some View {
        Button {
            copyToPasteboard()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .medium))
                    .accessibilityHidden(true)
                Text(copied ? "Copied!" : "\(points.formatted(.number)) pts")
                    .font(.brandMono(size: 11))
                    .monospacedDigit()
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, 3)
            .foregroundStyle(copied ? .bizarreSuccess : .bizarreOrange)
            .background(
                (copied ? Color.bizarreSuccess : Color.bizarreOrange).opacity(0.12),
                in: Capsule()
            )
            .animation(.easeInOut(duration: 0.15), value: copied)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Points balance copied" : "Copy points balance: \(points) points")
        .accessibilityHint(copied ? "" : "Double-tap to copy to clipboard")
    }

    private func copyToPasteboard() {
        let text = "\(points) pts"
#if canImport(UIKit)
        UIPasteboard.general.string = text
#elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#endif
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
