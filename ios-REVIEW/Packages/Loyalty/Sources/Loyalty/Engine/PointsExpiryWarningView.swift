import SwiftUI
import DesignSystem

// MARK: - §38 Points expiry warning

/// An inline warning banner shown when a customer has points expiring soon.
///
/// - Shows nothing when `expiringSoonPoints` is 0 or `expiryDate` is nil.
/// - Turns urgent (red) when expiry is ≤ 7 days away; amber otherwise.
/// - Tappable to dismiss (one-session suppression only; persists per view lifecycle).
///
/// Intended placement: below `LoyaltyPointsLedgerView` on the customer detail screen,
/// or inside any context where expiring points need surfacing.
///
/// Example:
/// ```swift
/// PointsExpiryWarningView(
///     expiringSoonPoints: ledger.expiringSoon,
///     expiryDate: viewModel.nearestExpiryDate
/// )
/// ```
public struct PointsExpiryWarningView: View {

    // MARK: - Inputs

    let expiringSoonPoints: Int
    let expiryDate: Date?

    // MARK: - Local state

    @State private var dismissed = false
    private let today: Date

    // MARK: - Init

    public init(
        expiringSoonPoints: Int,
        expiryDate: Date?,
        today: Date = .now
    ) {
        self.expiringSoonPoints = expiringSoonPoints
        self.expiryDate = expiryDate
        self.today = today
    }

    // MARK: - Derived

    /// Days remaining until `expiryDate`. `nil` when date is absent.
    private var daysRemaining: Int? {
        guard let expiry = expiryDate else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: today, to: expiry).day
    }

    /// Treat as urgent (≤ 7 days).
    private var isUrgent: Bool {
        guard let days = daysRemaining else { return false }
        return days <= 7
    }

    private var accentColor: Color { isUrgent ? .bizarreError : .bizarreWarning }

    private var shouldShow: Bool {
        !dismissed && expiringSoonPoints > 0 && expiryDate != nil
    }

    // MARK: - Body

    public var body: some View {
        if shouldShow {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: isUrgent ? "exclamationmark.triangle.fill" : "clock.badge.exclamationmark.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(headlineText)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)

                    if let days = daysRemaining {
                        Text(sublineText(daysRemaining: days))
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }

                Spacer()

                Button {
                    withAnimation(BrandMotion.statusChange) { dismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(BrandSpacing.xs)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss expiry warning")
            }
            .padding(BrandSpacing.base)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(accentColor.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(accentColor.opacity(0.35), lineWidth: 1)
                    )
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(fullAccessibilityLabel)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Copy helpers

    private var headlineText: String {
        "\(expiringSoonPoints.formatted(.number)) pts expiring soon"
    }

    private func sublineText(daysRemaining: Int) -> String {
        switch daysRemaining {
        case 0:  return "Points expire today — redeem now!"
        case 1:  return "Points expire tomorrow. Use them before they're gone."
        default: return "Points expire in \(daysRemaining) days. Don't let them go to waste."
        }
    }

    private var fullAccessibilityLabel: String {
        guard let days = daysRemaining else {
            return "\(expiringSoonPoints) points are expiring soon"
        }
        return "\(expiringSoonPoints) points expiring in \(days) \(days == 1 ? "day" : "days"). \(sublineText(daysRemaining: days))"
    }
}
