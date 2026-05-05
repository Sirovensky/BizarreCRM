import SwiftUI
import DesignSystem
import Networking

// MARK: - MembershipRedeemViewModel

/// §38.4 — VM for the loyalty points redemption sheet.
///
/// Server route: `POST /membership/:id/points/redeem`
/// The server endpoint returns 501 until the points ledger ships.
/// The VM handles 501 by transitioning to `.notYetAvailable`.
///
/// Callers supply `availablePoints` from the current `LoyaltyBalance`
/// so the UI can enforce the cap client-side before hitting the network.
@MainActor
@Observable
public final class MembershipRedeemViewModel {

    public enum State: Equatable, Sendable {
        case idle
        case redeeming
        case redeemed(Int, remainingPoints: Int?)
        case notYetAvailable
        case failed(String)
    }

    public private(set) var state: State = .idle
    public var pointsToRedeem: Int = 0
    /// Points available to redeem (populated by the caller from `LoyaltyBalance`).
    public let availablePoints: Int

    private let api: any APIClient
    private let subscriptionId: Int

    public init(api: any APIClient, subscriptionId: Int, availablePoints: Int) {
        self.api = api
        self.subscriptionId = subscriptionId
        self.availablePoints = availablePoints
    }

    // MARK: - Validation

    public var isValid: Bool {
        pointsToRedeem > 0 && pointsToRedeem <= availablePoints
    }

    public var validationMessage: String? {
        if pointsToRedeem <= 0 { return "Enter points to redeem." }
        if pointsToRedeem > availablePoints { return "Not enough points (available: \(availablePoints))." }
        return nil
    }

    // MARK: - Redeem

    public func redeem() async {
        guard isValid else { return }
        state = .redeeming
        do {
            let result = try await api.redeemMembershipPoints(
                subscriptionId: subscriptionId,
                points: pointsToRedeem
            )
            state = .redeemed(pointsToRedeem, remainingPoints: result.remainingPoints)
        } catch let t as APITransportError {
            if case .httpStatus(let code, _) = t, code == 501 || code == 404 {
                state = .notYetAvailable
            } else {
                state = .failed(t.localizedDescription)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - MembershipRedeemSheet

/// §38.4 — POS sheet for redeeming loyalty points from a membership.
///
/// Flow:
///   1. Staff enters a point amount (capped at `availablePoints`).
///   2. Tap "Redeem" → `POST /membership/:id/points/redeem`.
///   3. On 501: show "coming soon" state (server not yet wired).
///   4. On success: show confirmation with remaining balance.
///
/// iPhone: `.presentationDetents([.medium])` bottom sheet.
/// iPad: inherits `.formSheet` sizing from NavigationStack.
///
/// Usage:
/// ```swift
/// .sheet(isPresented: $showRedeem) {
///     MembershipRedeemSheet(
///         api: api,
///         subscriptionId: sub.id,
///         availablePoints: balance.points,
///         onRedeemed: { redeemed in cart.applyPointsRedemption(redeemed) }
///     )
/// }
/// ```
public struct MembershipRedeemSheet: View {

    @State private var vm: MembershipRedeemViewModel
    @Environment(\.dismiss) private var dismiss
    private let onRedeemed: ((Int) -> Void)?

    public init(
        api: any APIClient,
        subscriptionId: Int,
        availablePoints: Int,
        onRedeemed: ((Int) -> Void)? = nil
    ) {
        _vm = State(wrappedValue: MembershipRedeemViewModel(
            api: api,
            subscriptionId: subscriptionId,
            availablePoints: availablePoints
        ))
        self.onRedeemed = onRedeemed
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Redeem Points")
                #if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarItems }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .idle, .failed:
            redeemForm
        case .redeeming:
            redeemingView
        case .redeemed(let pts, let remaining):
            redeemedConfirmation(pts, remaining: remaining)
        case .notYetAvailable:
            notYetAvailableView
        }
    }

    // MARK: - Redeem form

    private var redeemForm: some View {
        Form {
            balanceSection
            entrySection
            if case .failed(let msg) = vm.state {
                Section {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.bizarreError)
                        .font(.brandBodyMedium())
                }
            }
        }
    }

    private var balanceSection: some View {
        Section {
            HStack {
                Text("Available Points")
                    .font(.brandBodyMedium())
                Spacer()
                Text(vm.availablePoints.formatted(.number))
                    .font(.brandMono(size: 18))
                    .foregroundStyle(.bizarreOrange)
            }
        }
    }

    private var entrySection: some View {
        Section("Points to Redeem") {
            #if canImport(UIKit)
            TextField("0", value: $vm.pointsToRedeem, format: .number)
                .keyboardType(.numberPad)
                .font(.brandMono(size: 24))
                .multilineTextAlignment(.center)
                .accessibilityLabel("Enter points to redeem")
            #else
            TextField("0", value: $vm.pointsToRedeem, format: .number)
                .font(.brandMono(size: 24))
                .multilineTextAlignment(.center)
                .accessibilityLabel("Enter points to redeem")
            #endif
            if let msg = vm.validationMessage {
                Text(msg)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
                    .accessibilityLabel(msg)
            }
        }
        .listSectionSpacing(.compact)
    }

    // MARK: - Redeeming progress

    private var redeemingView: some View {
        VStack(spacing: BrandSpacing.xl) {
            ProgressView()
                .scaleEffect(1.4)
                .accessibilityLabel("Redeeming points")
            Text("Redeeming \(vm.pointsToRedeem) points…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Redeemed confirmation

    private func redeemedConfirmation(_ pts: Int, remaining: Int?) -> some View {
        VStack(spacing: BrandSpacing.xl) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)

            VStack(spacing: BrandSpacing.sm) {
                Text("\(pts) Points Redeemed!")
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)

                if let r = remaining {
                    Text("Remaining balance: \(r.formatted(.number)) pts")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            Button("Done") {
                onRedeemed?(pts)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .accessibilityLabel("Dismiss and confirm points redemption")
        }
        .padding(BrandSpacing.xl)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Not yet available

    private var notYetAvailableView: some View {
        VStack(spacing: BrandSpacing.xl) {
            Image(systemName: "clock.badge")
                .font(.system(size: 56))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            VStack(spacing: BrandSpacing.sm) {
                Text("Coming Soon")
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Points redemption isn't available yet. Check back after the next server update.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }

            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
                .accessibilityLabel("Close redemption sheet")
        }
        .padding(BrandSpacing.xl)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityLabel("Cancel points redemption")
        }
        ToolbarItem(placement: .confirmationAction) {
            if case .redeeming = vm.state {
                ProgressView()
            } else if case .redeemed = vm.state {
                EmptyView()
            } else if case .notYetAvailable = vm.state {
                EmptyView()
            } else {
                Button("Redeem") {
                    Task { await vm.redeem() }
                }
                .disabled(!vm.isValid || vm.state == .redeeming)
                .accessibilityLabel("Confirm points redemption")
            }
        }
    }
}
