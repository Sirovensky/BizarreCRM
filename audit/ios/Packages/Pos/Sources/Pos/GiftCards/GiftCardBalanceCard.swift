#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §40 — Compact balance card displayed in gift-card lookup results,
/// redeem sheet header, and store-credit context.
///
/// Shows code (masked), current balance, status badge, and optional expiry.
/// Uses Liquid Glass chrome so it reads as a distinct "card" widget on both
/// iPhone and iPad.
///
/// Width adapts to its container — on iPhone it fills the form column; on
/// iPad the caller may place it in a fixed-width detail column.
public struct GiftCardBalanceCard: View {

    // MARK: - Data

    let code: String
    let balanceCents: Int
    let isActive: Bool
    let expiresAt: String?
    /// When true the balance label is rendered larger (POS redeem header).
    let prominent: Bool

    public init(
        code: String,
        balanceCents: Int,
        isActive: Bool,
        expiresAt: String? = nil,
        prominent: Bool = false
    ) {
        self.code = code
        self.balanceCents = balanceCents
        self.isActive = isActive
        self.expiresAt = expiresAt
        self.prominent = prominent
    }

    /// Convenience initialiser from the `GiftCard` model.
    public init(card: GiftCard, prominent: Bool = false) {
        self.init(
            code: card.code,
            balanceCents: card.balanceCents,
            isActive: card.active,
            expiresAt: card.expiresAt,
            prominent: prominent
        )
    }

    // MARK: - Body

    public var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.base) {
            // Card icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.bizarreOrange.opacity(0.15) : Color.bizarreOnSurface.opacity(0.08))
                    .frame(width: 44, height: 44)
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(isActive ? .bizarreOrange : .bizarreOnSurfaceMuted)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.sm) {
                    Text(maskedCode)
                        .font(.brandBodyMedium())
                        .monospaced()
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    statusBadge
                }

                Text(CartMath.formatCents(balanceCents))
                    .font(prominent ? .brandTitleLarge() : .brandTitleMedium())
                    .monospacedDigit()
                    .foregroundStyle(balanceCents > 0 ? .bizarreOnSurface : .bizarreOnSurfaceMuted)

                if let expiresAt, !expiresAt.isEmpty {
                    Text("Expires \(formattedExpiry(expiresAt))")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .padding(BrandSpacing.base)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Sub-views

    private var statusBadge: some View {
        Text(isActive ? "Active" : "Inactive")
            .font(.brandLabelSmall())
            .foregroundStyle(isActive ? .bizarreSuccess : .bizarreOnSurfaceMuted)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .background(
                Capsule()
                    .fill(isActive
                          ? Color.bizarreSuccess.opacity(0.12)
                          : Color.bizarreOnSurface.opacity(0.08))
            )
    }

    // MARK: - Helpers

    /// Shows the last 4 characters of the code; masks the rest.
    private var maskedCode: String {
        guard code.count > 4 else { return code }
        let suffix = code.suffix(4)
        return "••••\(suffix)"
    }

    private func formattedExpiry(_ raw: String) -> String {
        // Attempt ISO-8601 date parsing for a friendlier display.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                let display = DateFormatter()
                display.dateStyle = .medium
                display.timeStyle = .none
                return display.string(from: date)
            }
        }
        return raw
    }

    private var accessibilityDescription: String {
        var parts = [
            "Gift card ending \(code.suffix(4))",
            "Balance \(CartMath.formatCents(balanceCents))",
            isActive ? "Active" : "Inactive",
        ]
        if let expiresAt, !expiresAt.isEmpty {
            parts.append("Expires \(formattedExpiry(expiresAt))")
        }
        return parts.joined(separator: ". ")
    }
}
#endif
