import SwiftUI
import DesignSystem
import Networking

// MARK: - EmployeePerformanceTilesView
//
// §14.2 Performance tiles (admin-only).
// Displays: tickets closed / SMS sent / revenue touched / avg ticket value / NPS.
//
// Note: SMS sent count and NPS from customers require future server fields
// (`sms_sent`, `nps_score` on EmployeePerformance). Both display a "--" placeholder
// until the server supplies those values, per §74 audit shim approach.
//
// Usage: embed inside EmployeeDetailView below the profile header (admin-only guard
// applied by the parent via `EmployeeDetailViewModel.isAdminViewing`).

public struct EmployeePerformanceTilesView: View {
    public let performance: EmployeePerformance

    public init(performance: EmployeePerformance) {
        self.performance = performance
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Performance")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: BrandSpacing.sm
            ) {
                PerformanceTile(
                    icon: "checkmark.circle.fill",
                    value: "\(performance.closedTickets)",
                    label: "Tickets Closed",
                    accent: .bizarreOrange
                )
                PerformanceTile(
                    icon: "dollarsign.circle.fill",
                    value: currencyString(performance.totalRevenue),
                    label: "Revenue Touched",
                    accent: .green
                )
                PerformanceTile(
                    icon: "ticket.fill",
                    value: currencyString(performance.avgTicketValue),
                    label: "Avg Ticket Value",
                    accent: .blue
                )
                // SMS sent: server field pending — show totalTickets as proxy until §74 ships
                PerformanceTile(
                    icon: "message.fill",
                    value: "--",
                    label: "SMS Sent",
                    accent: .cyan
                )
                // NPS: requires future server field nps_score
                PerformanceTile(
                    icon: "star.fill",
                    value: "--",
                    label: "Customer NPS",
                    accent: .yellow
                )
                if let hours = performance.avgRepairHours {
                    PerformanceTile(
                        icon: "clock.fill",
                        value: String(format: "%.1fh", hours),
                        label: "Avg Repair Time",
                        accent: .purple
                    )
                }
            }
        }
    }

    private func currencyString(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = value >= 1000 ? 0 : 2
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

// MARK: - PerformanceTile

private struct PerformanceTile: View {
    let icon: String
    let value: String
    let label: String
    let accent: Color

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(value)
                    .font(.brandTitleMedium().monospacedDigit())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                Text(label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.bizarreOutline.opacity(0.25), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
