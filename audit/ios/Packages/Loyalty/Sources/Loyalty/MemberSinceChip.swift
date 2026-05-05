import SwiftUI
import DesignSystem

// MARK: - §38 Member-since chip

/// A compact inline chip that displays when a customer joined the loyalty programme.
///
/// Two size variants:
/// - `.compact` — "Member since Jan 2023" in a single-line pill. Used in list rows.
/// - `.card`    — Two-line version with a calendar icon and a "LOYALTY" label.
///               Used inside balance cards or customer detail headers.
///
/// The `memberSince` string is expected in ISO 8601 full-date format (`yyyy-MM-dd`);
/// malformed strings render the raw value as a safe fallback.
///
/// Example:
/// ```swift
/// MemberSinceChip(memberSince: "2023-01-15", size: .compact)
/// MemberSinceChip(memberSince: balance.memberSince, size: .card)
/// ```
public struct MemberSinceChip: View {

    // MARK: - Inputs

    let memberSince: String
    let size: ChipSize

    public enum ChipSize: Sendable { case compact, card }

    // MARK: - Init

    public init(memberSince: String, size: ChipSize = .compact) {
        self.memberSince = memberSince
        self.size = size
    }

    // MARK: - Derived

    private var formattedDate: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        guard let date = iso.date(from: memberSince) else { return memberSince }
        let df = DateFormatter()
        df.dateFormat = "MMM yyyy"
        return df.string(from: date)
    }

    private var yearsLabel: String? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        guard let date = iso.date(from: memberSince) else { return nil }
        let years = Calendar.current.dateComponents([.year], from: date, to: .now).year ?? 0
        guard years > 0 else { return nil }
        return "\(years) \(years == 1 ? "year" : "years")"
    }

    // MARK: - Body

    public var body: some View {
        switch size {
        case .compact:
            compactChip
        case .card:
            cardChip
        }
    }

    // MARK: - Compact variant

    private var compactChip: some View {
        Label("Member since \(formattedDate)", systemImage: "calendar.badge.checkmark")
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .background(.bizarreSurface2, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Card variant

    private var cardChip: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.bizarreTeal)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("LOYALTY")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)

                HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.xs) {
                    Text("Member since \(formattedDate)")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)

                    if let years = yearsLabel {
                        Text("· \(years)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(Color.bizarreTeal.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .stroke(Color.bizarreTeal.opacity(0.25), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        if let years = yearsLabel {
            return "Member since \(formattedDate). \(years) as a loyalty member."
        }
        return "Loyalty member since \(formattedDate)."
    }
}
