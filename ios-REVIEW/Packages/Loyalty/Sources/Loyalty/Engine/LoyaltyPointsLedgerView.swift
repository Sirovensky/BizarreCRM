import SwiftUI
import DesignSystem
import Networking

// MARK: - LoyaltyPointsLedger (model)

/// §38 — Summary row shown in the ledger view.
public struct LoyaltyPointsLedger: Sendable {
    public let lifetimeEarned: Int
    public let lifetimeRedeemed: Int
    public let expiringSoon: Int        // points expiring within 30 days
    public let balance: Int

    public init(
        lifetimeEarned: Int,
        lifetimeRedeemed: Int,
        expiringSoon: Int = 0,
        balance: Int
    ) {
        self.lifetimeEarned = lifetimeEarned
        self.lifetimeRedeemed = lifetimeRedeemed
        self.expiringSoon = expiringSoon
        self.balance = balance
    }
}

// MARK: - LoyaltyPointsLedgerViewModel

@MainActor
@Observable
public final class LoyaltyPointsLedgerViewModel {

    public enum State: Equatable, Sendable {
        case loading
        case loaded
        case comingSoon
        case failed(String)
    }

    public private(set) var state: State = .loading
    public private(set) var ledger: LoyaltyPointsLedger?

    private let api: any APIClient
    private let customerId: Int64

    public init(api: any APIClient, customerId: Int64) {
        self.api = api
        self.customerId = customerId
    }

    public func load() async {
        state = .loading
        ledger = nil
        do {
            let balance = try await api.getLoyaltyBalance(customerId: customerId)
            // Server doesn't yet return redeemed / expiring-soon; derive from balance.
            let earned = balance.points
            ledger = LoyaltyPointsLedger(
                lifetimeEarned: earned,
                lifetimeRedeemed: 0,
                expiringSoon: 0,
                balance: earned
            )
            state = .loaded
        } catch let transport as APITransportError {
            if case .httpStatus(let code, _) = transport, code == 404 || code == 501 {
                state = .comingSoon
            } else {
                state = .failed(transport.localizedDescription)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - LoyaltyPointsLedgerView

/// §38 — Customer-facing ledger showing earned / redeemed / expiring-soon / balance.
///
/// iPhone: compact vertical card stack.
/// iPad: two-column LazyVGrid for wider layouts.
///
/// Accessibility:
/// - Each stat tile is a standalone `accessibilityElement` with a combined label.
/// - Reduce Motion: number counting animation is disabled.
public struct LoyaltyPointsLedgerView: View {

    @State private var vm: LoyaltyPointsLedgerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var hSizeClass

    public init(api: any APIClient, customerId: Int64) {
        _vm = State(wrappedValue: LoyaltyPointsLedgerViewModel(api: api, customerId: customerId))
    }

    public var body: some View {
        Group {
            switch vm.state {
            case .loading:
                loadingView
            case .loaded:
                if let ledger = vm.ledger {
                    ledgerContent(ledger)
                }
            case .comingSoon:
                comingSoonView
            case .failed(let msg):
                failedView(msg)
            }
        }
        .task { await vm.load() }
    }

    // MARK: - Ledger content

    @ViewBuilder
    private func ledgerContent(_ ledger: LoyaltyPointsLedger) -> some View {
        let tiles: [(String, Int, String, Color)] = [
            ("Earned", ledger.lifetimeEarned, "star.fill", .bizarreOrange),
            ("Redeemed", ledger.lifetimeRedeemed, "arrow.uturn.left.circle.fill", .bizarreTeal),
            ("Expiring Soon", ledger.expiringSoon, "clock.fill", .bizarreWarning),
            ("Balance", ledger.balance, "wallet.pass.fill", .bizarreSuccess)
        ]

        if hSizeClass == .regular {
            // iPad: 2-column grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: BrandSpacing.md) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    statTile(label: tile.0, value: tile.1, icon: tile.2, color: tile.3)
                }
            }
        } else {
            // iPhone: vertical stack
            VStack(spacing: BrandSpacing.sm) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    statTile(label: tile.0, value: tile.1, icon: tile.2, color: tile.3)
                }
            }
        }
    }

    private func statTile(label: String, value: Int, icon: String, color: Color) -> some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(value.formatted(.number))
                    .font(.brandMono(size: 24))
                    .foregroundStyle(.bizarreOnSurface)
                    .animation(reduceMotion ? .none : BrandMotion.statusChange, value: value)
            }

            Spacer()
        }
        .padding(BrandSpacing.base)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(Color.bizarreSurface1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) points")
    }

    // MARK: - States

    private var loadingView: some View {
        HStack(spacing: BrandSpacing.sm) {
            ProgressView().accessibilityLabel("Loading points ledger")
            Text("Loading points…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.base)
    }

    private var comingSoonView: some View {
        Label("Points ledger coming soon", systemImage: "clock")
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .padding(BrandSpacing.base)
            .accessibilityLabel("Points ledger not yet available")
    }

    private func failedView(_ message: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Couldn't load points ledger")
                    .font(.brandTitleSmall())
                Text(message)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Button("Retry") { Task { await vm.load() } }
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOrange)
                .accessibilityLabel("Retry loading points ledger")
        }
        .padding(BrandSpacing.base)
    }
}
