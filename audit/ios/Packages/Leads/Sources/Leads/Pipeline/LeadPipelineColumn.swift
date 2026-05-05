import SwiftUI
import Networking
import DesignSystem
import Core

// MARK: - LeadPipelineColumn

/// Vertical list of lead cards for one pipeline stage.
/// The column header shows stage name + card count + total value.
struct LeadPipelineColumn: View {
    let stage: PipelineStage
    let leads: [Lead]
    let totalValueCents: Int
    let onMoveTo: (Lead, PipelineStage) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader
            ScrollView {
                LazyVStack(spacing: BrandSpacing.sm) {
                    ForEach(leads) { lead in
                        LeadKanbanCard(lead: lead, stage: stage, onMoveTo: onMoveTo)
                            .draggable(String(lead.id)) // Int64 serialised as String (Transferable)
                    }
                    if leads.isEmpty {
                        emptyPlaceholder
                    }
                }
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.base)
            }
        }
        .frame(width: 220)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Header

    private var columnHeader: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: stage.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text(stage.displayName)
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
            Spacer(minLength: 0)
            Text("\(leads.count)")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .monospacedDigit()
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, in: UnevenRoundedRectangle(
            topLeadingRadius: 16,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 16
        ))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stage.displayName) column, \(leads.count) leads")
    }

    private var emptyPlaceholder: some View {
        Text("No leads")
            .font(.brandLabelLarge())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.xl)
    }
}

// MARK: - LeadKanbanCard

/// Single card in a Kanban column.
struct LeadKanbanCard: View {
    let lead: Lead
    let stage: PipelineStage
    let onMoveTo: (Lead, PipelineStage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(lead.displayName)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(2)
            if let phone = lead.phone, !phone.isEmpty {
                Text(PhoneFormatter.format(phone))
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(1)
            }
            HStack(spacing: BrandSpacing.xs) {
                if let score = lead.leadScore {
                    LeadScoreBadge(score: score)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
        .contextMenu {
            moveMenuItems
        }
    }

    // MARK: - A11y

    private var a11yLabel: String {
        var parts = [stage.displayName, lead.displayName]
        if let phone = lead.phone, !phone.isEmpty { parts.append(PhoneFormatter.format(phone)) }
        if let score = lead.leadScore { parts.append("Score \(score) of 100") }
        return parts.joined(separator: ". ")
    }

    // MARK: - Context menu (move between stages)

    @ViewBuilder
    private var moveMenuItems: some View {
        ForEach(PipelineStage.allCases.filter { $0 != stage }) { target in
            Button("Move to \(target.displayName)") {
                onMoveTo(lead, target)
            }
        }
    }
}
