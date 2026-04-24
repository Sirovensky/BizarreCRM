#if canImport(UIKit)
import SwiftUI
import Charts
import Core
import DesignSystem
import Networking

// MARK: - CustomerHealthView

/// Pluggable card/panel that surfaces CRM health score and LTV.
///
/// ## Layout
/// - **iPhone** (compact): compact card — score ring + LTV pill in a single row,
///   recommendation below, Liquid Glass chrome on the card background.
/// - **iPad** (regular): full-bleed panel — score ring left, LTV + label right,
///   RFM breakdown bar chart spanning the full width beneath both.
///
/// ## Usage
/// ```swift
/// CustomerHealthView(vm: CustomerHealthViewModel(repo: repo, customerId: id))
///     .task { await vm.load() }
/// ```
/// The view is intentionally **not** wired into `CustomerDetailView` automatically —
/// call sites opt in.
public struct CustomerHealthView: View {
    @State public var vm: CustomerHealthViewModel

    public init(vm: CustomerHealthViewModel) {
        _vm = State(wrappedValue: vm)
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneCard
            } else {
                iPadPanel
            }
        }
        .task { await vm.load() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Customer health and lifetime value")
    }

    // MARK: - iPhone compact card

    private var iPhoneCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(alignment: .center, spacing: BrandSpacing.md) {
                scoreRing(diameter: 56, fontSize: 18)
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    tierLabel
                    if let ltv = vm.snapshot?.ltv {
                        ltvPill(ltv: ltv)
                    }
                }
                Spacer()
                recalcButton(compact: true)
            }
            if let rec = vm.snapshot?.score.recommendation {
                recommendationRow(rec)
            }
            if let message = vm.recalcMessage {
                Text(message)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreSuccess)
                    .transition(.opacity)
            }
            errorRow
        }
        .padding(BrandSpacing.md)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .padding(.horizontal, BrandSpacing.md)
        .overlay(alignment: .topTrailing) {
            if vm.isLoading {
                ProgressView()
                    .padding(BrandSpacing.sm)
            }
        }
    }

    // MARK: - iPad full-bleed panel

    private var iPadPanel: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            HStack(alignment: .top, spacing: BrandSpacing.xl) {
                // Left: score ring + label
                VStack(alignment: .center, spacing: BrandSpacing.sm) {
                    scoreRing(diameter: 88, fontSize: 28)
                    tierLabel
                    if let label = vm.snapshot?.score.label {
                        Text(label.displayTitle)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                .frame(minWidth: 120)

                Divider()

                // Right: LTV + recommendation + recalc
                VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                    if let ltv = vm.snapshot?.ltv {
                        ltvBlock(ltv: ltv)
                    }
                    if let rec = vm.snapshot?.score.recommendation {
                        recommendationRow(rec)
                    }
                    recalcButton(compact: false)
                    if let message = vm.recalcMessage {
                        Text(message)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreSuccess)
                    }
                    errorRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if vm.isLoading {
                    ProgressView()
                }
            }

            // Full-bleed RFM chart (iPad only)
            if let components = vm.snapshot?.score.components {
                rfmChart(components: components)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(BrandSpacing.lg)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .padding(.horizontal, BrandSpacing.lg)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func scoreRing(diameter: CGFloat, fontSize: CGFloat) -> some View {
        let score     = vm.snapshot?.score.value ?? 0
        let tier      = vm.snapshot?.score.tier ?? .yellow
        let ringColor = color(for: tier)

        ZStack {
            Circle()
                .stroke(ringColor.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: DesignTokens.Motion.smooth), value: score)
            if vm.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                Text("\(score)")
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(ringColor)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel("Health score \(score) out of 100")
    }

    private var tierLabel: some View {
        let tier = vm.snapshot?.score.tier ?? .yellow
        return Text(tierDisplayLabel(tier))
            .font(.brandLabelLarge())
            .foregroundStyle(color(for: tier))
    }

    @ViewBuilder
    private func ltvPill(ltv: CustomerLTVResult) -> some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: ltv.tier.icon)
                .font(.system(size: 12))
                .foregroundStyle(ltv.tier.color)
            Text(ltv.formatted)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
            Text(ltv.tier.label)
                .font(.brandLabelSmall())
                .foregroundStyle(ltv.tier.color)
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .background(ltv.tier.color.opacity(0.12), in: Capsule())
        .accessibilityLabel("Lifetime value \(ltv.formatted), tier \(ltv.tier.label)")
    }

    @ViewBuilder
    private func ltvBlock(ltv: CustomerLTVResult) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text("Lifetime Value")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: ltv.tier.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(ltv.tier.color)
                Text(ltv.formatted)
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
            Text(ltv.tier.label)
                .font(.brandLabelLarge())
                .foregroundStyle(ltv.tier.color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lifetime value \(ltv.formatted). Tier \(ltv.tier.label).")
    }

    @ViewBuilder
    private func recommendationRow(_ text: String) -> some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12))
                .foregroundStyle(.bizarreWarning)
            Text(text)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityLabel("Recommendation: \(text)")
    }

    @ViewBuilder
    private func recalcButton(compact: Bool) -> some View {
        Button {
            Task { await vm.recalculate() }
        } label: {
            if vm.isRecalculating {
                ProgressView()
                    .scaleEffect(compact ? 0.7 : 0.8)
            } else {
                Label(compact ? "" : "Recalculate", systemImage: "arrow.clockwise")
                    .font(.brandLabelSmall())
            }
        }
        .buttonStyle(.brandGlassClear)
        .disabled(vm.isRecalculating || vm.isLoading)
        .accessibilityLabel("Recalculate health score")
    }

    @ViewBuilder
    private var errorRow: some View {
        if let err = vm.errorMessage {
            Text(err)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreError)
                .accessibilityLabel("Error: \(err)")
        }
    }

    // MARK: - RFM chart (iPad only)

    @ViewBuilder
    private func rfmChart(components: HealthScoreComponents) -> some View {
        let bars: [(label: String, value: Int)] = [
            ("Recency",   components.recencyPoints),
            ("Frequency", components.frequencyPoints),
            ("Monetary",  components.monetaryPoints),
        ]

        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Score Breakdown")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)

            Chart(bars, id: \.label) { bar in
                BarMark(
                    x: .value("Pillar", bar.label),
                    y: .value("Points", bar.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.bizarreOrange, Color.bizarreTeal],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .cornerRadius(DesignTokens.Radius.xs)
                .annotation(position: .top) {
                    Text("\(bar.value)")
                        .font(.caption2)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel("\(bar.label): \(bar.value) points")
            }
            .chartYScale(domain: 0...40)
            .chartYAxis {
                AxisMarks(values: [0, 10, 20, 30, 40]) { value in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 140)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("RFM score breakdown chart")
        }
    }

    // MARK: - Helpers

    private func color(for tier: CustomerHealthTier) -> Color {
        switch tier {
        case .green:  return .bizarreSuccess
        case .yellow: return .bizarreWarning
        case .red:    return .bizarreError
        }
    }

    private func tierDisplayLabel(_ tier: CustomerHealthTier) -> String {
        switch tier {
        case .green:  return "Healthy"
        case .yellow: return "At Risk"
        case .red:    return "Critical"
        }
    }
}
#endif
