import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §9.1 Columns view for lead list
// iPad/Mac: Table with sortable columns — Name / Phone / Email / Lead Score / Status / Source / Value / Next Action
// iPhone: falls back to standard list rows

public struct LeadColumnsView: View {
    let leads: [Lead]
    var onTap: (Lead) -> Void

    public init(leads: [Lead], onTap: @escaping (Lead) -> Void) {
        self.leads = leads
        self.onTap = onTap
    }

    public var body: some View {
        if Platform.isCompact {
            compactList
        } else {
            iPadTable
        }
    }

    // MARK: - iPad Table

    @State private var sortOrder: [KeyPathComparator<Lead>] = [
        .init(\.displayName, order: .forward)
    ]

    private var sortedLeads: [Lead] {
        leads.sorted(using: sortOrder)
    }

    private var iPadTable: some View {
        Table(sortedLeads, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.displayName) { lead in
                nameCell(lead)
            }
            .width(min: 140, ideal: 180)

            TableColumn("Phone") { lead in
                Text(lead.phone ?? "—")
                    .font(.brandMono(size: 13))
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
            }
            .width(min: 110, ideal: 130)

            TableColumn("Email") { lead in
                Text(lead.email ?? "—")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            .width(min: 140, ideal: 180)

            TableColumn("Score") { lead in
                scoreCell(lead)
            }
            .width(min: 70, ideal: 80)

            TableColumn("Status") { lead in
                statusChip(lead.status ?? "—")
            }
            .width(min: 90, ideal: 110)

            TableColumn("Source") { lead in
                Text(lead.source?.capitalized ?? "—")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .width(min: 80, ideal: 100)
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .environment(\.defaultMinListRowHeight, 48)
    }

    // MARK: - iPhone compact list

    private var compactList: some View {
        List(leads) { lead in
            Button { onTap(lead) } label: {
                compactRow(lead)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.bizarreSurface1)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func compactRow(_ lead: Lead) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lead.displayName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                if let phone = lead.phone, !phone.isEmpty {
                    Text(phone)
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                } else if let email = lead.email, !email.isEmpty {
                    Text(email)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let score = lead.leadScore {
                    scoreBar(score: score, compact: true)
                }
                if let status = lead.status {
                    statusChip(status)
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(leadA11yLabel(lead))
    }

    // MARK: - Subviews

    private func nameCell(_ lead: Lead) -> some View {
        Button { onTap(lead) } label: {
            HStack(spacing: BrandSpacing.sm) {
                Circle()
                    .fill(Color.bizarreOrangeContainer)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Text(initials(lead))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.bizarreOnOrange)
                    )
                    .accessibilityHidden(true)
                Text(lead.displayName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(lead.displayName)
    }

    private func scoreCell(_ lead: Lead) -> some View {
        if let score = lead.leadScore {
            return AnyView(scoreBar(score: score, compact: false))
        }
        return AnyView(Text("—").font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted))
    }

    private func scoreBar(score: Int, compact: Bool) -> some View {
        let color: Color = score >= 70 ? .bizarreSuccess : score >= 40 ? .bizarreWarning : .bizarreError
        return HStack(spacing: BrandSpacing.xxs) {
            if !compact {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.bizarreSurface2).frame(width: 40, height: 6)
                    Capsule().fill(color).frame(width: 40 * CGFloat(score) / 100, height: 6)
                }
                .accessibilityHidden(true)
            }
            Text("\(score)")
                .font(.brandMono(size: 13))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .accessibilityLabel("Lead score \(score) of 100")
    }

    private func statusChip(_ status: String) -> some View {
        Text(status.capitalized)
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurface)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, 2)
            .background(chipBackground(for: status), in: Capsule())
    }

    private func chipBackground(for status: String) -> Color {
        switch status.lowercased() {
        case "new":        return .bizarreOrange.opacity(0.15)
        case "qualified":  return .bizarreSuccess.opacity(0.15)
        case "converted":  return .bizarreTeal.opacity(0.15)
        case "lost":       return .bizarreError.opacity(0.15)
        default:           return .bizarreSurface2
        }
    }

    private func initials(_ lead: Lead) -> String {
        let f = lead.firstName?.first.map(String.init) ?? ""
        let l = lead.lastName?.first.map(String.init) ?? ""
        return (f + l).isEmpty ? "#" : f + l
    }

    private func leadA11yLabel(_ lead: Lead) -> String {
        var parts = [lead.displayName]
        if let phone = lead.phone { parts.append(phone) }
        if let status = lead.status { parts.append("Status: \(status)") }
        if let score = lead.leadScore { parts.append("Score \(score) of 100") }
        return parts.joined(separator: ". ")
    }
}
