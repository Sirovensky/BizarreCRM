#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §5.2 Health Score Explanation Sheet

/// Modal sheet shown when the user taps the health score ring.
/// Displays the 0–100 score, colour tier, per-pillar breakdown (if available),
/// the server-assigned label, and a "Recalculate" button.
public struct CustomerHealthExplainerSheet: View {
    let detail: CustomerDetail
    let analytics: CustomerAnalytics?
    let api: APIClient

    @State private var isRecalculating = false
    @State private var recalcError: String?
    @State private var recalcDone = false
    @Environment(\.dismiss) private var dismiss

    private var health: CustomerHealthScoreResult {
        CustomerHealthScoreResult.compute(detail: detail)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.lg) {
                        // Large ring
                        ZStack {
                            Circle().stroke(ringColor.opacity(0.15), lineWidth: 10)
                            Circle()
                                .trim(from: 0, to: CGFloat(health.value) / 100)
                                .stroke(ringColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.easeOut(duration: DesignTokens.Motion.smooth), value: health.value)
                            VStack(spacing: 2) {
                                Text("\(health.value)")
                                    .font(.system(size: 40, weight: .bold, design: .rounded))
                                    .foregroundStyle(ringColor)
                                    .monospacedDigit()
                                Text("of 100")
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                        }
                        .frame(width: 140, height: 140)
                        .accessibilityLabel("Health score \(health.value) of 100")

                        // Tier label
                        Text(tierLabel)
                            .font(.brandHeadlineMedium())
                            .foregroundStyle(ringColor)

                        // Server label badge
                        if let label = health.label {
                            Text(label.displayTitle)
                                .font(.brandLabelLarge())
                                .foregroundStyle(.bizarreOnSurface)
                                .padding(.horizontal, BrandSpacing.md)
                                .padding(.vertical, BrandSpacing.xs)
                                .background(Color.bizarreSurface2, in: Capsule())
                        }

                        // RFM Breakdown
                        if let components = health.components {
                            rfmSection(components)
                        } else {
                            pillarsPlaceholder
                        }

                        // Recommendation
                        if let rec = health.recommendation {
                            HStack(spacing: BrandSpacing.sm) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundStyle(.bizarreWarning)
                                    .accessibilityHidden(true)
                                Text(rec)
                                    .font(.brandBodyMedium())
                                    .foregroundStyle(.bizarreOnSurface)
                            }
                            .padding(BrandSpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.bizarreWarning.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                        }

                        // Recalculate CTA
                        recalcSection

                        Spacer(minLength: BrandSpacing.lg)
                    }
                    .padding(BrandSpacing.lg)
                }
            }
            .navigationTitle("Health Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Dismiss health score sheet")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Sub-views

    private func rfmSection(_ c: HealthScoreComponents) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Score Breakdown")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            pillarRow("Recency", pts: c.recencyPoints, max: 40,
                      hint: "Points based on when the customer last visited.")
            pillarRow("Frequency", pts: c.frequencyPoints, max: 30,
                      hint: "Points based on how often they visit.")
            pillarRow("Monetary", pts: c.monetaryPoints, max: 30,
                      hint: "Points based on total lifetime spend.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func pillarRow(_ label: String, pts: Int, max: Int, hint: String) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            HStack {
                Text(label).font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text("\(pts)/\(max)")
                    .font(.brandMono(size: 13))
                    .foregroundStyle(ringColor)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.bizarreSurface2).frame(height: 6)
                    Capsule().fill(ringColor)
                        .frame(width: geo.size.width * CGFloat(pts) / CGFloat(max), height: 6)
                        .animation(.easeOut(duration: DesignTokens.Motion.smooth), value: pts)
                }
            }
            .frame(height: 6)
            Text(hint).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(pts) of \(max) points. \(hint)")
    }

    private var pillarsPlaceholder: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Tap Recalculate to see score breakdown.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(BrandSpacing.base)
        .frame(maxWidth: .infinity)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
    }

    private var recalcSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            if recalcDone {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.bizarreSuccess)
                    Text("Score updated.").font(.brandBodyMedium()).foregroundStyle(.bizarreSuccess)
                }
            }
            if let err = recalcError {
                Text(err).font(.brandLabelSmall()).foregroundStyle(.bizarreError).multilineTextAlignment(.center)
            }
            Button {
                Task { await recalculate() }
            } label: {
                Group {
                    if isRecalculating {
                        ProgressView().tint(.white)
                    } else {
                        Label("Recalculate", systemImage: "arrow.clockwise")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .disabled(isRecalculating)
            .accessibilityLabel("Recalculate health score")
        }
    }

    // MARK: Helpers

    private var ringColor: Color {
        switch health.tier {
        case .green:  return .bizarreSuccess
        case .yellow: return .bizarreWarning
        case .red:    return .bizarreError
        }
    }

    private var tierLabel: String {
        switch health.tier {
        case .green:  return "Healthy"
        case .yellow: return "At Risk"
        case .red:    return "Critical"
        }
    }

    private func recalculate() async {
        isRecalculating = true
        recalcError = nil
        recalcDone = false
        defer { isRecalculating = false }
        do {
            _ = try await api.recalculateCustomerHealthScore(customerId: detail.id)
            recalcDone = true
        } catch {
            recalcError = error.localizedDescription
        }
    }
}

// MARK: - §5.2 LTV Tier Explanation Sheet

public struct CustomerLTVExplainerSheet: View {
    let detail: CustomerDetail
    let analytics: CustomerAnalytics?
    @Environment(\.dismiss) private var dismiss

    private var ltvCents: Int {
        if let a = analytics, a.lifetimeValue > 0 { return Int(a.lifetimeValue * 100) }
        if let c = detail.ltvCents, c > 0 { return Int(c) }
        return 0
    }

    private var tier: LTVTier { LTVCalculator.tier(for: ltvCents) }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.lg) {
                        // Tier icon + name
                        VStack(spacing: BrandSpacing.sm) {
                            Image(systemName: tier.icon)
                                .font(.system(size: 52))
                                .foregroundStyle(tier.color)
                                .accessibilityHidden(true)
                            Text(tier.label)
                                .font(.brandHeadlineMedium())
                                .foregroundStyle(tier.color)
                            Text(formatted(ltvCents))
                                .font(.brandTitleLarge())
                                .foregroundStyle(.bizarreOnSurface)
                                .monospacedDigit()
                            Text("Lifetime Value")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Lifetime value \(formatted(ltvCents)), \(tier.label) tier")

                        // Tier thresholds
                        tierBreakdown

                        // Perks for current tier
                        perksSection
                    }
                    .padding(BrandSpacing.lg)
                }
            }
            .navigationTitle("Lifetime Value")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityLabel("Dismiss LTV sheet")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var tierBreakdown: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Tier Thresholds")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            ForEach(LTVTier.allCases, id: \.self) { t in
                HStack {
                    Image(systemName: t.icon)
                        .foregroundStyle(t.color)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(t.label)
                        .font(.brandBodyMedium())
                        .foregroundStyle(t == tier ? t.color : .bizarreOnSurface)
                    Spacer()
                    Text(formatted(t.minLifetimeSpendCents) + "+")
                        .font(.brandMono(size: 13))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                    if t == tier {
                        Image(systemName: "checkmark")
                            .foregroundStyle(t.color)
                            .font(.caption.weight(.bold))
                    }
                }
                .padding(.vertical, BrandSpacing.xs)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(t.label): \(formatted(t.minLifetimeSpendCents)) minimum\(t == tier ? ". Current tier." : "")")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private var perksSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Perks at \(tier.label)")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(tier.perksDescription)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(tier.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tier.color.opacity(0.25), lineWidth: 0.5))
    }

    private func formatted(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(cents / 100)"
    }
}
#endif
