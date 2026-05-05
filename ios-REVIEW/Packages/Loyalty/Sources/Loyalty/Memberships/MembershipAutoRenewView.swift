import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §38.5 Auto-renew: card on file charged on renewal date
//
// Task L5285 — Auto-renew: if enrolled, card on file is charged on renewal date.
//
// The server cron job handles the actual charge (BlockChyp or Stripe).
// iOS surfaces:
//   • Current auto-renew status (on/off) with toggle
//   • Card on file summary (last 4, expiry, brand)
//   • Last charge result banner (success/fail)
//   • Upcoming renewal countdown with amount
//   • Staff can manually trigger a renewal attempt (manager-only)
//   • Charge result push notification acknowledgement

// MARK: - Card on file summary model

public struct CardOnFile: Decodable, Sendable {
    public let last4: String
    public let brand: String
    public let expMonth: Int
    public let expYear: Int
    public let isExpired: Bool

    enum CodingKeys: String, CodingKey {
        case last4
        case brand
        case expMonth  = "exp_month"
        case expYear   = "exp_year"
        case isExpired = "is_expired"
    }

    public var displayBrand: String {
        switch brand.lowercased() {
        case "visa":       return "Visa"
        case "mastercard": return "Mastercard"
        case "amex":       return "Amex"
        case "discover":   return "Discover"
        default:           return brand.capitalized
        }
    }

    public var expiryDisplay: String { "\(expMonth)/\(expYear % 100)" }

    public var brandIcon: String {
        switch brand.lowercased() {
        case "visa":       return "creditcard.fill"
        case "amex":       return "creditcard.fill"
        default:           return "creditcard"
        }
    }
}

// MARK: - Auto-renew charge result

public struct MembershipChargeResult: Decodable, Sendable {
    public let success: Bool
    public let amountCents: Int
    public let failureReason: String?
    public let chargedAt: String?

    enum CodingKeys: String, CodingKey {
        case success
        case amountCents   = "amount_cents"
        case failureReason = "failure_reason"
        case chargedAt     = "charged_at"
    }

    public var chargedDate: Date? {
        guard let s = chargedAt else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class MembershipAutoRenewViewModel {

    // MARK: State

    public var membership: Membership
    public var cardOnFile: CardOnFile? = nil
    public var lastChargeResult: MembershipChargeResult? = nil
    public var isLoading = false
    public var isTriggeringCharge = false
    public var autoRenewToggleLoading = false
    public var errorMessage: String? = nil
    public var chargeTriggeredToast = false

    // MARK: Dependencies

    @ObservationIgnored private let api: APIClient

    public init(membership: Membership, api: APIClient) {
        self.membership = membership
        self.api = api
    }

    // MARK: Load

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        async let cardTask    = fetchCard()
        async let chargeTask  = fetchLastCharge()
        (cardOnFile, lastChargeResult) = await (cardTask, chargeTask)
    }

    private func fetchCard() async -> CardOnFile? {
        try? await api.get(
            "/api/v1/memberships/\(membership.id)/card-on-file",
            as: CardOnFile.self
        )
    }

    private func fetchLastCharge() async -> MembershipChargeResult? {
        try? await api.get(
            "/api/v1/memberships/\(membership.id)/last-charge",
            as: MembershipChargeResult.self
        )
    }

    // MARK: Toggle auto-renew

    public func toggleAutoRenew() async {
        autoRenewToggleLoading = true
        errorMessage = nil
        defer { autoRenewToggleLoading = false }
        let newValue = !membership.autoRenew
        do {
            struct Body: Encodable { let auto_renew: Bool }
            _ = try await api.patch(
                "/api/v1/memberships/\(membership.id)",
                body: Body(auto_renew: newValue),
                as: EmptyResponse.self
            )
            membership = Membership(
                id: membership.id,
                customerId: membership.customerId,
                planId: membership.planId,
                status: membership.status,
                startDate: membership.startDate,
                endDate: membership.endDate,
                autoRenew: newValue,
                nextBillingAt: membership.nextBillingAt
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Manual trigger charge (manager-only)

    public func triggerRenewalCharge() async {
        isTriggeringCharge = true
        errorMessage = nil
        defer { isTriggeringCharge = false }
        do {
            try await api.post(
                "/api/v1/memberships/\(membership.id)/renew",
                body: AutoRenewEmptyBody(),
                as: EmptyResponse.self
            )
            chargeTriggeredToast = true
            // Reload to get updated charge result
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Main auto-renew view

public struct MembershipAutoRenewView: View {

    @State private var vm: MembershipAutoRenewViewModel
    private let isManager: Bool

    public init(membership: Membership, api: APIClient, isManager: Bool = false) {
        _vm = State(wrappedValue: MembershipAutoRenewViewModel(membership: membership, api: api))
        self.isManager = isManager
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.md) {

                // Auto-renew toggle section
                autoRenewSection

                // Card on file
                if let card = vm.cardOnFile {
                    cardOnFileSection(card)
                }

                // Last charge result
                if let result = vm.lastChargeResult {
                    lastChargeSection(result)
                }

                // Manual trigger (manager only)
                if isManager && vm.membership.autoRenew {
                    manualTriggerSection
                }

                // Error
                if let err = vm.errorMessage {
                    Text(err)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreError)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(BrandSpacing.sm)
                }
            }
            .padding(BrandSpacing.base)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Auto-Renew")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .overlay(alignment: .bottom) {
            if vm.chargeTriggeredToast {
                toastBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            withAnimation { vm.chargeTriggeredToast = false }
                        }
                    }
            }
        }
        .animation(.snappy, value: vm.chargeTriggeredToast)
    }

    // MARK: Sections

    private var autoRenewSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Label("Auto-renew", systemImage: "arrow.clockwise.circle.fill")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                if vm.autoRenewToggleLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Toggle("", isOn: .init(
                        get: { vm.membership.autoRenew },
                        set: { _ in Task { await vm.toggleAutoRenew() } }
                    ))
                    .tint(.bizarreSuccess)
                    .accessibilityLabel("Auto-renew membership")
                }
            }

            // Next billing countdown
            if let nextBilling = vm.membership.nextBillingAt {
                nextBillingRow(nextBilling)
            }

            Text("When enabled, the card on file is automatically charged on the renewal date. Staff are notified of the outcome.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func nextBillingRow(_ date: Date) -> some View {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: Date(), to: date).day ?? 0
        let isUrgent = days >= 0 && days <= 3
        let fmt = DateFormatter(); fmt.dateStyle = .medium
        return HStack {
            Image(systemName: "calendar")
                .foregroundStyle(isUrgent ? .bizarreWarning : .bizarreOnSurfaceMuted)
                .font(.system(size: 14))
                .accessibilityHidden(true)
            if days == 0 {
                Text("Renewal today")
                    .font(.brandLabelLarge().weight(.semibold))
                    .foregroundStyle(.bizarreWarning)
            } else if days > 0 {
                Text("Renews in \(days) day\(days == 1 ? "" : "s") — \(fmt.string(from: date))")
                    .font(.brandLabelLarge())
                    .foregroundStyle(isUrgent ? .bizarreWarning : .bizarreOnSurface)
            } else {
                Text("Past renewal date — check billing status")
                    .font(.brandLabelLarge().weight(.semibold))
                    .foregroundStyle(.bizarreError)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next renewal: \(fmt.string(from: date))")
    }

    private func cardOnFileSection(_ card: CardOnFile) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Card on File")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: card.brandIcon)
                    .font(.system(size: 22))
                    .foregroundStyle(card.isExpired ? .bizarreError : .bizarreOnSurface)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(card.displayBrand) ···· \(card.last4)")
                        .font(.brandMono(size: 15).weight(.semibold))
                        .foregroundStyle(card.isExpired ? .bizarreError : .bizarreOnSurface)
                        .monospacedDigit()
                    HStack(spacing: 4) {
                        Text("Expires \(card.expiryDisplay)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(card.isExpired ? .bizarreError : .bizarreOnSurfaceMuted)
                        if card.isExpired {
                            Text("EXPIRED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.bizarreError, in: Capsule())
                        }
                    }
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(card.displayBrand) card ending \(card.last4), expires \(card.expiryDisplay)\(card.isExpired ? ". Card is expired." : "")")

            if card.isExpired {
                Text("Expired card — customer must update payment method before next renewal.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
                    .accessibilityLabel("Warning: expired card. Customer must update payment.")
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(
                card.isExpired ? Color.bizarreError.opacity(0.5) : Color.bizarreOutline.opacity(0.4),
                lineWidth: card.isExpired ? 1 : 0.5
            ))
    }

    private func lastChargeSection(_ result: MembershipChargeResult) -> some View {
        let bannerResult: AutoRenewResultBanner.Result
        if result.success, let date = result.chargedDate {
            bannerResult = .success(date: date, amountCents: result.amountCents)
        } else if !result.success {
            bannerResult = .failure(
                reason: result.failureReason ?? "Unknown error",
                date: result.chargedDate ?? Date()
            )
        } else {
            bannerResult = .pending
        }
        return VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Last Charge")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
            AutoRenewResultBanner(result: bannerResult)
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private var manualTriggerSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Manual Actions")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
            Button {
                Task { await vm.triggerRenewalCharge() }
            } label: {
                HStack {
                    if vm.isTriggeringCharge {
                        ProgressView().tint(.white).controlSize(.small)
                    }
                    Label("Trigger Renewal Now", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .disabled(vm.isTriggeringCharge)
            .accessibilityLabel("Trigger membership renewal charge now")
            .accessibilityHint("Manager action — charges the card on file immediately")

            Text("Triggers an immediate renewal charge using the card on file. Use only if the scheduled charge failed or was missed.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private var toastBanner: some View {
        Label("Renewal charge triggered", systemImage: "checkmark.circle.fill")
            .font(.brandLabelLarge().weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)
            .background(Color.bizarreSuccess, in: Capsule())
            .padding(.bottom, BrandSpacing.xl)
            .accessibilityLabel("Renewal charge triggered successfully")
    }
}

// MARK: - Helpers

private struct AutoRenewEmptyBody: Encodable {}
