// §57.1 NextJobCardView — Liquid Glass overlay on the map showing the
// next appointment and a Navigate button.
// Reduce Motion: card appears instantly (no spring animation) when enabled.

import SwiftUI
import CoreLocation
import DesignSystem

// MARK: - NextJobCardView

/// Floating glass card overlaid on `FieldServiceMapView`.
/// Shows next appointment details + ETA + Navigate button.
///
/// A11y: card is a distinct accessibility group; navigate button
/// has `accessibilityHint`.
public struct NextJobCardView: View {

    public let appointmentTitle: String
    public let customerName: String
    public let address: String
    public let etaMinutes: Int?
    public let onNavigate: () -> Void
    public let onStartJob: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        appointmentTitle: String,
        customerName: String,
        address: String,
        etaMinutes: Int?,
        onNavigate: @escaping () -> Void,
        onStartJob: @escaping () -> Void
    ) {
        self.appointmentTitle = appointmentTitle
        self.customerName = customerName
        self.address = address
        self.etaMinutes = etaMinutes
        self.onNavigate = onNavigate
        self.onStartJob = onStartJob
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            headerRow
            Divider().opacity(0.4)
            addressRow
            actionRow
        }
        .padding(DesignTokens.Spacing.lg)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .frame(maxWidth: 380)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.bottom, DesignTokens.Spacing.xl)
        .animation(reduceMotion ? nil : BrandMotion.sheet, value: etaMinutes)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(combinedA11yLabel)
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Next Job")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.secondary)
                Text(appointmentTitle)
                    .font(.brandTitleMedium())
                    .foregroundStyle(.primary)
                Text(customerName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let eta = etaMinutes {
                ETAChip(minutes: eta)
            }
        }
    }

    private var addressRow: some View {
        Label(address, systemImage: "location.fill")
            .font(.brandBodyMedium())
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    private var actionRow: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Button(action: onNavigate) {
                Label("Navigate", systemImage: "arrow.triangle.turn.up.right.circle.fill")
            }
            .buttonStyle(.brandGlassProminent)
            .tint(.bizarreOrange)
            .accessibilityHint("Opens Apple Maps with turn-by-turn directions")

            Button(action: onStartJob) {
                Label("Start Job", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.brandGlass)
            .accessibilityHint("Marks the job as started and prompts check-in")
        }
    }

    // MARK: - A11y

    private var combinedA11yLabel: String {
        var parts = ["Next job: \(appointmentTitle)", "Customer: \(customerName)", "Address: \(address)"]
        if let eta = etaMinutes { parts.append("\(eta) minutes away") }
        return parts.joined(separator: ". ")
    }
}

// MARK: - NoNextJobCardView

/// Shown in place of NextJobCardView when the technician has no remaining jobs today.
/// Displayed as the same glass card so the layout stays stable.
public struct NoNextJobCardView: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.bizarreSuccess)
                .accessibilityHidden(true)
            Text("All done for today")
                .font(.brandTitleMedium())
                .foregroundStyle(.primary)
            Text("No more jobs scheduled. Check back later or contact dispatch.")
                .font(.brandBodyMedium())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(DesignTokens.Spacing.lg)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .frame(maxWidth: 380)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.bottom, DesignTokens.Spacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("All done for today. No more jobs scheduled.")
    }
}

// MARK: - ETAChip

/// Color-coded ETA badge.
///
/// States:
/// - ≤ 5 min  → green  (arriving imminently)
/// - 6–20 min → orange (normal transit)
/// - > 20 min → red    (delayed / far out)
///
/// A11y: badge is excluded from combine so that `NextJobCardView.combinedA11yLabel`
/// already describes the ETA value in plain English.
private struct ETAChip: View {
    let minutes: Int

    private var chipColor: Color {
        switch minutes {
        case ...5:  return .bizarreSuccess
        case 6...20: return .bizarreOrange
        default:    return .bizarreError
        }
    }

    private var a11yLabel: String {
        switch minutes {
        case ...5:  return "\(minutes) minutes, arriving soon"
        case 6...20: return "\(minutes) minutes away"
        default:    return "\(minutes) minutes, may be delayed"
        }
    }

    var body: some View {
        Text("\(minutes) min")
            .font(.brandLabelSmall())
            .foregroundStyle(.white)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(chipColor, in: Capsule())
            .accessibilityLabel(a11yLabel)
    }
}
