import SwiftUI
import DesignSystem
import Networking
#if canImport(PassKit)
import PassKit
#endif
#if canImport(UIKit)
import UIKit
#endif

#if canImport(PassKit) && canImport(UIKit)

/// §38 — "Add to Apple Wallet" card embedded in CustomerDetailView.
///
/// Shows:
///   - "Add to Apple Wallet" button if the pass is NOT in Wallet.
///   - "View in Wallet" button if the pass IS already in Wallet.
///   - A loading spinner while `.fetching`.
///   - An error row with retry on `.failed`.
///
/// **Wiring (add to CustomerDetailView, do not touch CustomerDetailView directly):**
/// ```swift
/// // In CustomerDetailView body:
/// LoyaltyMembershipCardView(
///     customerId: customer.id,
///     api: api,
///     passTypeIdentifier: "pass.com.bizarrecrm.loyalty",
///     serialNumber: customer.loyaltyPassSerial ?? ""
/// )
/// ```
///
/// A11y: The primary button has an explicit `.accessibilityLabel` that reads
/// "Add loyalty card to Apple Wallet" (requirement per task spec).
public struct LoyaltyMembershipCardView: View {

    @State private var vm: LoyaltyWalletViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let passTypeIdentifier: String
    private let serialNumber: String

    // MARK: - Init

    public init(
        service: (any LoyaltyWalletServicing)? = nil,
        customerId: String,
        passTypeIdentifier: String = "pass.com.bizarrecrm.loyalty",
        serialNumber: String = "",
        api: APIClient? = nil
    ) {
        self.passTypeIdentifier = passTypeIdentifier
        self.serialNumber = serialNumber
        let resolvedService: any LoyaltyWalletServicing
        if let s = service {
            resolvedService = s
        } else if let a = api {
            resolvedService = LoyaltyWalletService(api: a)
        } else {
            resolvedService = LoyaltyWalletService(api: APIClientImpl())
        }
        _vm = State(
            wrappedValue: LoyaltyWalletViewModel(
                service: resolvedService,
                customerId: customerId
            )
        )
    }

    // MARK: - Body

    public var body: some View {
        contentView
            .onAppear {
                vm.checkWalletStatus(
                    passTypeIdentifier: passTypeIdentifier,
                    serialNumber: serialNumber
                )
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch vm.state {
        case .idle, .ready, .addedToWallet:
            walletActionButton
        case .fetching:
            fetchingView
        case .failed(let msg):
            failedView(msg)
        }
    }

    // MARK: - Wallet button

    private var walletActionButton: some View {
        Group {
            if vm.isPassInWallet {
                viewInWalletButton
            } else {
                addToWalletButton
            }
        }
    }

    private var addToWalletButton: some View {
        Button {
            Task { await vm.addToWallet() }
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Add to Apple Wallet")
                    .font(.brandTitleSmall())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignTokens.Spacing.md)
        }
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm), interactive: true)
        .accessibilityLabel("Add loyalty card to Apple Wallet")
        .accessibilityHint("Downloads your loyalty pass and opens Apple Wallet")
    }

    private var viewInWalletButton: some View {
        Button {
            UIApplication.shared.open(URL(string: "shoebox://")!)
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "wallet.pass")
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityHidden(true)
                Text("View in Wallet")
                    .font(.brandTitleSmall())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignTokens.Spacing.md)
        }
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm), interactive: true)
        .accessibilityLabel("View loyalty card in Apple Wallet")
        .accessibilityHint("Opens Apple Wallet to your loyalty pass")
    }

    // MARK: - Fetching

    private var fetchingView: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ProgressView()
                .accessibilityLabel("Adding pass to Wallet")
            Text("Adding to Wallet…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    // MARK: - Failed

    private func failedView(_ message: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Wallet pass unavailable")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text(message)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Button("Retry") { vm.reset() }
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOrange)
                .accessibilityLabel("Retry adding loyalty card to Apple Wallet")
        }
        .padding(DesignTokens.Spacing.md)
    }
}

#else

/// macOS stub — Apple Wallet is unavailable on macOS.
public struct LoyaltyMembershipCardView: View {
    public init(
        customerId: String,
        passTypeIdentifier: String = "pass.com.bizarrecrm.loyalty",
        serialNumber: String = "",
        api: APIClient? = nil
    ) {}
    public var body: some View { EmptyView() }
}

#endif // canImport(PassKit) && canImport(UIKit)
