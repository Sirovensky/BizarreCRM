import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §38.5 Punch card redemption sheet
// Last punch = free next service, auto-applied discount at POS.
// Combo rule: no stacking with other discounts unless configured.

// MARK: - ViewModel

@MainActor
@Observable
public final class PunchCardRedemptionViewModel {
    public enum Phase: Sendable {
        case confirm
        case redeeming
        case success(redemptionCode: String)
        case failure(String)
    }

    public var phase: Phase = .confirm
    /// Whether to stack with existing discounts (tenant-configurable; off by default).
    public var allowStacking: Bool = false

    @ObservationIgnored private let api: APIClient
    public let card: PunchCard

    public init(api: APIClient, card: PunchCard) {
        self.api = api
        self.card = card
    }

    public func redeem() async {
        phase = .redeeming
        do {
            let result = try await api.redeemPunchCard(
                cardId: card.id,
                allowStacking: allowStacking
            )
            phase = .success(redemptionCode: result.redemptionCode)
        } catch {
            AppLog.ui.error("Punch card redemption failed: \(error.localizedDescription, privacy: .public)")
            phase = .failure(error.localizedDescription)
        }
    }
}

// MARK: - View

/// Sheet presented when a staff member taps "Redeem" on a completed punch card.
/// Confirms the free service, calls the redemption endpoint, shows confirmation.
public struct PunchCardRedemptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: PunchCardRedemptionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(api: APIClient, card: PunchCard) {
        _vm = State(wrappedValue: PunchCardRedemptionViewModel(api: api, card: card))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()

                switch vm.phase {
                case .confirm:
                    confirmContent
                case .redeeming:
                    redeemingContent
                case .success(let code):
                    successContent(code: code)
                case .failure(let msg):
                    failureContent(msg: msg)
                }
            }
            .navigationTitle("Redeem Free Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .redeeming = vm.phase {} else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Confirm

    private var confirmContent: some View {
        VStack(spacing: BrandSpacing.lg) {
            Spacer()

            // Card icon
            ZStack {
                Circle()
                    .fill(Color.bizarreOrangeContainer)
                    .frame(width: 80, height: 80)
                Image(systemName: vm.card.serviceTypeSymbol)
                    .font(.system(size: 32))
                    .foregroundStyle(.bizarreOnOrange)
            }
            .accessibilityHidden(true)

            VStack(spacing: BrandSpacing.sm) {
                Text("Free \(vm.card.serviceTypeName)")
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text("This customer completed \(vm.card.totalPunches) services and earned a free one.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }

            // Stacking toggle (visible only when tenant config might allow it)
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Toggle(isOn: $vm.allowStacking) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow stacking with other discounts")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Text("Off by default per tenant policy.")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                .tint(.bizarreOrange)
                .accessibilityLabel("Allow stacking punch card reward with other discounts")
            }
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))

            // CTA
            Button {
                Task { await vm.redeem() }
            } label: {
                Label("Apply Free Service", systemImage: "gift.fill")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .accessibilityIdentifier("loyalty.punchCard.confirmRedeem")

            Spacer()
        }
        .padding(.horizontal, BrandSpacing.lg)
    }

    // MARK: - Redeeming

    private var redeemingContent: some View {
        VStack(spacing: BrandSpacing.base) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(.bizarreOrange)
            Text("Applying redemption…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Applying punch card redemption")
    }

    // MARK: - Success

    private func successContent(code: String) -> some View {
        VStack(spacing: BrandSpacing.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.bizarreSuccess.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.bizarreSuccess)
                    .symbolEffect(.bounce, value: !reduceMotion)
            }
            .accessibilityHidden(true)

            VStack(spacing: BrandSpacing.sm) {
                Text("Service Applied!")
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)

                Text("Free \(vm.card.serviceTypeName) has been applied.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }

            // Redemption code (for receipt / audit)
            VStack(spacing: BrandSpacing.xs) {
                Text("Redemption code")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(code)
                    .font(.brandMono(size: 18))
                    .foregroundStyle(.bizarreOrange)
                    .textSelection(.enabled)
                    .accessibilityLabel("Redemption code: \(code)")
            }
            .padding(BrandSpacing.base)
            .frame(maxWidth: .infinity)
            .background(Color.bizarreOrange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOrange.opacity(0.25), lineWidth: 0.5))

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .font(.brandLabelLarge())
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("loyalty.punchCard.redemptionDone")

            Spacer()
        }
        .padding(.horizontal, BrandSpacing.lg)
    }

    // MARK: - Failure

    private func failureContent(msg: String) -> some View {
        VStack(spacing: BrandSpacing.lg) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)

            Text("Redemption Failed")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)

            HStack(spacing: BrandSpacing.sm) {
                Button("Try Again") {
                    vm.phase = .confirm
                }
                .buttonStyle(.bordered)
                .tint(.bizarreOrange)
                .accessibilityIdentifier("loyalty.punchCard.retryRedeem")

                Button("Cancel") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreError)
            }

            Spacer()
        }
        .padding(.horizontal, BrandSpacing.lg)
    }
}

// MARK: - Redemption response model

public struct PunchCardRedemptionResult: Decodable, Sendable {
    public let redemptionCode: String
    public let freeServiceApplied: Bool

    enum CodingKeys: String, CodingKey {
        case redemptionCode  = "redemption_code"
        case freeServiceApplied = "free_service_applied"
    }
}

private struct PunchCardRedemptionRequest: Encodable, Sendable {
    let cardId: String
    let allowStacking: Bool
    enum CodingKeys: String, CodingKey {
        case cardId        = "card_id"
        case allowStacking = "allow_stacking"
    }
}

// MARK: - Endpoint

extension APIClient {
    /// `POST /loyalty/punch-cards/:id/redeem` — apply the free service reward.
    public func redeemPunchCard(cardId: String, allowStacking: Bool) async throws -> PunchCardRedemptionResult {
        let body = PunchCardRedemptionRequest(cardId: cardId, allowStacking: allowStacking)
        return try await post("/loyalty/punch-cards/\(cardId)/redeem", body: body, as: PunchCardRedemptionResult.self)
    }
}
