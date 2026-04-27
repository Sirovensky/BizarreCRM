import SwiftUI
import DesignSystem
import Networking

// MARK: - §38.5 Punch Card

/// Model for a single punch card program per service type.
///
/// Stored server-side; iOS displays and triggers redemption at POS.
/// The `totalPunches` is the reward threshold (e.g. 5 = 5th service free,
/// 10 = 10th wash free). Count auto-increments on eligible service completion.
public struct PunchCard: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let customerId: String
    /// Human-readable service type name (e.g. "Oil Change", "Car Wash").
    public let serviceTypeName: String
    /// SF Symbol for the service type.
    public let serviceTypeSymbol: String
    /// Total punches required to earn the free service.
    public let totalPunches: Int
    /// Current punch count (server-managed; iOS read-only).
    public let currentPunches: Int
    /// Whether the reward is currently redeemable (last punch = free service).
    public let isRedeemable: Bool
    /// Optional expiry; nil = no expiry.
    public let expiresAt: Date?

    public init(
        id: String,
        customerId: String,
        serviceTypeName: String,
        serviceTypeSymbol: String = "wrench.and.screwdriver.fill",
        totalPunches: Int,
        currentPunches: Int,
        isRedeemable: Bool = false,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.customerId = customerId
        self.serviceTypeName = serviceTypeName
        self.serviceTypeSymbol = serviceTypeSymbol
        self.totalPunches = totalPunches
        self.currentPunches = currentPunches
        self.isRedeemable = isRedeemable
        self.expiresAt = expiresAt
    }

    /// Progress fraction 0–1.
    public var progress: Double {
        guard totalPunches > 0 else { return 0 }
        return min(1.0, Double(currentPunches) / Double(totalPunches))
    }

    enum CodingKeys: String, CodingKey {
        case id, note
        case customerId        = "customer_id"
        case serviceTypeName   = "service_type_name"
        case serviceTypeSymbol = "service_type_symbol"
        case totalPunches      = "total_punches"
        case currentPunches    = "current_punches"
        case isRedeemable      = "is_redeemable"
        case expiresAt         = "expires_at"
    }
}

// MARK: - PunchCardView

/// Visual punch card row shown in customer detail → Loyalty section.
///
/// Displays filled / empty punch circles and a "Redeem" button when complete.
/// Progress icons: filled stamp = punched; empty circle = remaining.
public struct PunchCardView: View {
    public let card: PunchCard
    public var onRedeem: () -> Void

    public init(card: PunchCard, onRedeem: @escaping () -> Void = {}) {
        self.card = card
        self.onRedeem = onRedeem
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // Header
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: card.serviceTypeSymbol)
                    .foregroundStyle(.bizarreOrange)
                    .font(.system(size: 16))
                    .accessibilityHidden(true)
                Text(card.serviceTypeName)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer(minLength: 0)
                if card.isRedeemable {
                    redeemBadge
                }
            }

            // Punch grid
            punchGrid

            // Progress label
            HStack {
                Text("\(card.currentPunches) of \(card.totalPunches) punches")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer(minLength: 0)
                if let expiresAt = card.expiresAt {
                    Text("Expires \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            // Redeem button (only when redeemable)
            if card.isRedeemable {
                Button(action: onRedeem) {
                    Label("Apply Free Service", systemImage: "gift.fill")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(BrandSpacing.sm)
                        .background(Color.bizarreOrange, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Redeem free \(card.serviceTypeName) service")
                .accessibilityIdentifier("loyalty.punchCard.redeem.\(card.id)")
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(
                    card.isRedeemable ? Color.bizarreOrange.opacity(0.5) : Color.bizarreOutline.opacity(0.4),
                    lineWidth: card.isRedeemable ? 1.5 : 0.5
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(card.serviceTypeName) punch card. \(card.currentPunches) of \(card.totalPunches) punches.")
    }

    // MARK: - Punch grid

    private var punchGrid: some View {
        let cols = min(card.totalPunches, 10) // max 10 per row; wrap if more
        let rows = Int(ceil(Double(card.totalPunches) / Double(cols)))
        let columns = Array(repeating: GridItem(.flexible(), spacing: BrandSpacing.xs), count: cols)
        return LazyVGrid(columns: columns, spacing: BrandSpacing.xs) {
            ForEach(0..<card.totalPunches, id: \.self) { index in
                punchCircle(filled: index < card.currentPunches, isLast: index == card.totalPunches - 1)
            }
        }
        .accessibilityHidden(true) // summary label on parent covers this
        // suppress unused warning
        .onChange(of: rows) { _, _ in }
    }

    private func punchCircle(filled: Bool, isLast: Bool) -> some View {
        ZStack {
            Circle()
                .fill(filled ? Color.bizarreOrange : Color.bizarreSurface2)
                .frame(width: 28, height: 28)
            if filled {
                Image(systemName: isLast ? "star.fill" : "checkmark")
                    .font(.system(size: isLast ? 14 : 11, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 28, height: 28)
            }
        }
    }

    private var redeemBadge: some View {
        Text("Ready!")
            .font(.brandLabelSmall())
            .foregroundStyle(.white)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, 2)
            .background(Color.bizarreOrange, in: Capsule())
            .accessibilityLabel("Punch card complete — ready to redeem")
    }
}

// MARK: - CustomerPunchCardsSection

/// Section card for customer detail showing all punch cards for that customer.
/// Used in the Loyalty tab of customer detail.
public struct CustomerPunchCardsSection: View {
    public let cards: [PunchCard]
    public var onRedeem: (PunchCard) -> Void

    public init(cards: [PunchCard], onRedeem: @escaping (PunchCard) -> Void = { _ in }) {
        self.cards = cards
        self.onRedeem = onRedeem
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            HStack {
                Text("PUNCH CARDS")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .tracking(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }

            if cards.isEmpty {
                Text("No punch cards yet.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                ForEach(cards) { card in
                    PunchCardView(card: card) {
                        onRedeem(card)
                    }
                }
            }
        }
    }
}
