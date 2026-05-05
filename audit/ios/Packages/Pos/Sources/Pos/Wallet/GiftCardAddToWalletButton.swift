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

/// §40 — "Add to Apple Wallet" button shown on the gift-card send
/// confirmation screen (post-sale / virtual card send flow).
///
/// **Wiring (add to GiftCardSendConfirmationView — do not touch that view):**
/// ```swift
/// GiftCardAddToWalletButton(
///     service: container.resolve(GiftCardWalletService.self),
///     giftCardId: sentCard.id
/// )
/// ```
public struct GiftCardAddToWalletButton: View {

    @State private var vm: GiftCardWalletButtonViewModel

    public init(
        service: (any GiftCardWalletServicing)? = nil,
        api: APIClient? = nil,
        giftCardId: String
    ) {
        let resolvedService: any GiftCardWalletServicing
        if let s = service {
            resolvedService = s
        } else if let a = api {
            resolvedService = GiftCardWalletService(api: a)
        } else {
            resolvedService = GiftCardWalletService(api: APIClientImpl())
        }
        _vm = State(
            wrappedValue: GiftCardWalletButtonViewModel(
                service: resolvedService,
                giftCardId: giftCardId
            )
        )
    }

    public var body: some View {
        walletContent
    }

    @ViewBuilder
    private var walletContent: some View {
        switch vm.state {
        case .idle, .ready, .addedToWallet:
            primaryButton
        case .fetching:
            fetchingIndicator
        case .failed(let msg):
            errorRow(msg)
        }
    }

    private var primaryButton: some View {
        Button {
            Task { await vm.addToWallet() }
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityHidden(true)
                Text(vm.state == .addedToWallet ? "Added to Wallet" : "Add Gift Card to Apple Wallet")
                    .font(.brandTitleSmall())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignTokens.Spacing.md)
        }
        .disabled(vm.state == .addedToWallet)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm), interactive: true)
        .accessibilityLabel(
            vm.state == .addedToWallet
                ? "Gift card added to Apple Wallet"
                : "Add gift card to Apple Wallet"
        )
        .accessibilityHint(
            vm.state == .addedToWallet
                ? "The gift card pass has been added to your Wallet"
                : "Downloads the gift card pass and opens Apple Wallet"
        )
    }

    private var fetchingIndicator: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ProgressView()
                .accessibilityLabel("Adding gift card to Wallet")
            Text("Adding to Wallet…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private func errorRow(_ message: String) -> some View {
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
                .accessibilityLabel("Retry adding gift card to Apple Wallet")
        }
        .padding(DesignTokens.Spacing.md)
    }
}

// MARK: - GiftCardWalletButtonViewModel

@MainActor
@Observable
final class GiftCardWalletButtonViewModel {

    enum ButtonState: Equatable {
        case idle
        case fetching
        case ready(URL)
        case addedToWallet
        case failed(String)

        static func == (lhs: ButtonState, rhs: ButtonState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle):                   return true
            case (.fetching, .fetching):           return true
            case (.ready(let a), .ready(let b)):   return a == b
            case (.addedToWallet, .addedToWallet): return true
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    private(set) var state: ButtonState = .idle
    private let service: any GiftCardWalletServicing
    private let giftCardId: String

    init(service: any GiftCardWalletServicing, giftCardId: String) {
        self.service = service
        self.giftCardId = giftCardId
    }

    func addToWallet() async {
        state = .fetching
        do {
            let url = try await service.fetchPass(giftCardId: giftCardId)
            state = .ready(url)
            try await service.addToWallet(from: url)
            state = .addedToWallet
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func reset() {
        state = .idle
    }
}

#else

/// macOS stub — Apple Wallet is unavailable on macOS.
public struct GiftCardAddToWalletButton: View {
    public init(api: APIClient? = nil, giftCardId: String) {}
    public var body: some View { EmptyView() }
}

#endif // canImport(PassKit) && canImport(UIKit)
