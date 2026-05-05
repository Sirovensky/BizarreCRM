import SwiftUI
import Charts
import DesignSystem

// MARK: - SLABreachSummary
//
// §15.3 — SLA breach count.
// Derived from GET /api/v1/reports/tickets with sla_summary breakdown.

public struct SLABreachSummary: Decodable, Sendable {
    /// Total tickets in the period.
    public let totalTickets: Int
    /// Number of tickets that breached SLA.
    public let breachedCount: Int
    /// Number of tickets at risk of breaching (within 20% of threshold).
    public let atRiskCount: Int
    /// Most common breach reason.
    public let topBreachReason: String?

    public var breachRate: Double {
        guard totalTickets > 0 else { return 0 }
        return Double(breachedCount) / Double(totalTickets) * 100.0
    }

    enum CodingKeys: String, CodingKey {
        case totalTickets   = "total_tickets"
        case breachedCount  = "sla_breached"
        case atRiskCount    = "sla_at_risk"
        case topBreachReason = "top_breach_reason"
    }

    public init(totalTickets: Int, breachedCount: Int,
                atRiskCount: Int, topBreachReason: String? = nil) {
        self.totalTickets = totalTickets
        self.breachedCount = breachedCount
        self.atRiskCount = atRiskCount
        self.topBreachReason = topBreachReason
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.totalTickets = (try? c.decode(Int.self, forKey: .totalTickets)) ?? 0
        self.breachedCount = (try? c.decode(Int.self, forKey: .breachedCount)) ?? 0
        self.atRiskCount = (try? c.decode(Int.self, forKey: .atRiskCount)) ?? 0
        self.topBreachReason = try? c.decode(String.self, forKey: .topBreachReason)
    }
}

// MARK: - SLABreachCard

public struct SLABreachCard: View {
    public let summary: SLABreachSummary?

    public init(summary: SLABreachSummary?) {
        self.summary = summary
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            if let s = summary {
                content(s)
            } else {
                skeletonState
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("SLA Breaches")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Content

    private func content(_ s: SLABreachSummary) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            // Primary KPI: breach count + rate
            HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(s.breachedCount)")
                            .font(.brandHeadlineLarge())
                            .foregroundStyle(s.breachedCount > 0 ? Color.bizarreError : Color.bizarreSuccess)
                            .monospacedDigit()
                        Text("breached")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    Text(String(format: "%.1f%% breach rate", s.breachRate))
                        .font(.brandLabelLarge())
                        .foregroundStyle(s.breachRate > 10 ? Color.bizarreError : Color.bizarreWarning)
                }
                Spacer()
                // At-risk chip
                if s.atRiskCount > 0 {
                    VStack(spacing: 2) {
                        Text("\(s.atRiskCount)")
                            .font(.brandTitleLarge())
                            .foregroundStyle(.bizarreWarning)
                            .monospacedDigit()
                        Text("at risk")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .padding(BrandSpacing.sm)
                    .background(Color.bizarreWarning.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(s.breachedCount) SLA breaches (\(String(format: "%.1f", s.breachRate))% breach rate). \(s.atRiskCount) at risk."
            )

            // Progress bar: compliance rate
            VStack(alignment: .leading, spacing: 4) {
                Text("Compliance")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                let compliance = max(0, 100.0 - s.breachRate)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.bizarreOutline.opacity(0.3))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(compliance >= 90 ? Color.bizarreSuccess : Color.bizarreWarning)
                            .frame(
                                width: geo.size.width * CGFloat(compliance / 100.0),
                                height: 8
                            )
                    }
                }
                .frame(height: 8)
                .accessibilityLabel(
                    String(format: "SLA compliance: %.1f%%", compliance)
                )
                Text(String(format: "%.1f%% compliant", compliance))
                    .font(.brandLabelSmall())
                    .foregroundStyle(compliance >= 90 ? Color.bizarreSuccess : Color.bizarreWarning)
            }

            // Top breach reason
            if let reason = s.topBreachReason {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("Top reason: \(reason)")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel("Top breach reason: \(reason)")
            }
        }
    }

    // MARK: - Skeleton (data unavailable)

    private var skeletonState: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(Color.bizarreSurface2)
                    .frame(height: 20)
            }
        }
        .accessibilityLabel("SLA breach data loading")
    }
}
