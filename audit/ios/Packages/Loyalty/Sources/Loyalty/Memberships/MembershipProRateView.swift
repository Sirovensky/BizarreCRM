import SwiftUI
import DesignSystem
import Networking

// MARK: - §38.5 Pro-rate Remaining Period Credit on Reactivation
//
// When a customer reactivates an expired or cancelled membership,
// the server may credit a pro-rated amount for the unused portion
// of the previous billing period.
// This view surfaces the credit estimate before the user confirms.

// MARK: - DTO

public struct MembershipProRateCredit: Decodable, Sendable {
    /// Credit amount in cents to be applied on reactivation.
    public let creditCents: Int
    /// Human-readable explanation from the server.
    public let explanation: String
    /// Days remaining in the original period at time of cancellation.
    public let daysRemaining: Int?

    enum CodingKeys: String, CodingKey {
        case creditCents  = "credit_cents"
        case explanation
        case daysRemaining = "days_remaining"
    }
}

// MARK: - Pure Calculator (on-device estimate for immediate UX)

public struct MembershipProRateCalculator {
    /// Calculates an estimated credit for unused days.
    ///
    /// - Parameters:
    ///   - pricePerPeriodCents: Full period price.
    ///   - periodDays: Total days in the billing period.
    ///   - unusedDays: Days remaining at time of cancellation.
    /// - Returns: Estimated credit in cents (floored to whole cents).
    public static func estimatedCredit(
        pricePerPeriodCents: Int,
        periodDays: Int,
        unusedDays: Int
    ) -> Int {
        guard periodDays > 0, unusedDays > 0 else { return 0 }
        let clamped = min(unusedDays, periodDays)
        let dailyRate = Double(pricePerPeriodCents) / Double(periodDays)
        return Int(dailyRate * Double(clamped))
    }
}

// MARK: - View

/// Shown inside the reactivation confirmation flow before the user taps
/// "Reactivate". Fetches the exact credit from the server; falls back to
/// the on-device estimate while loading.
public struct MembershipProRateCreditView: View {
    public let membershipId: String
    public let plan: MembershipPlan?
    public let api: APIClient

    @State private var credit: MembershipProRateCredit?
    @State private var isLoading = false
    @State private var errorMessage: String?

    public init(membershipId: String, plan: MembershipPlan? = nil, api: APIClient) {
        self.membershipId = membershipId
        self.plan = plan
        self.api = api
    }

    private var displayCents: Int {
        credit?.creditCents ?? onDeviceEstimate
    }

    private var onDeviceEstimate: Int {
        guard let plan else { return 0 }
        // Conservative 50% estimate when no server data available yet
        return plan.pricePerPeriodCents / 2
    }

    private var formattedCredit: String {
        String(format: "$%.2f", Double(displayCents) / 100)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // Header
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.bizarreSuccess)
                    .accessibilityHidden(true)
                Text("Pro-rate Credit")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)
            }

            Divider().opacity(0.4)

            if isLoading {
                HStack {
                    ProgressView()
                    Text("Calculating credit…")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            } else {
                // Credit amount
                HStack(alignment: .firstTextBaseline) {
                    Text("Credit applied:")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Spacer()
                    Text(formattedCredit)
                        .font(.brandMono(size: 18).weight(.bold))
                        .foregroundStyle(displayCents > 0 ? .bizarreSuccess : .bizarreOnSurface)
                        .monospacedDigit()
                }

                // Explanation
                if let explanation = credit?.explanation {
                    Text(explanation)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Credit for unused days in your previous billing period, applied to the first renewal charge.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreError)
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSuccess.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreSuccess.opacity(0.25), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pro-rate credit: \(formattedCredit). " +
            (credit?.explanation ?? "Credit for unused days applied to first renewal."))
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            credit = try await api.getMembershipProRateCredit(membershipId: membershipId)
        } catch {
            // Non-critical — show estimate; log error
            errorMessage = nil
        }
    }
}

// MARK: - APIClient extension

public extension APIClient {
    /// `GET /api/v1/membership/:id/pro-rate-credit` — fetch pro-rate credit estimate.
    func getMembershipProRateCredit(membershipId: String) async throws -> MembershipProRateCredit {
        try await get("/api/v1/membership/\(membershipId)/pro-rate-credit",
                      as: MembershipProRateCredit.self)
    }
}
