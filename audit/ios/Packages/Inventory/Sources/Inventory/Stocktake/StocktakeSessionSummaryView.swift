#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking

// MARK: - StocktakeSessionSummaryView

/// §6.6 — Inline progress summary card rendered inside the stocktake session list.
///
/// Shows scanned-item count, expected-item count, and completion percentage as a
/// `ProgressView`. Counts are derived from the session's embedded `counts` array —
/// a row is considered "counted" when its `actualQty` is non-nil.
/// When `counts` is empty (list endpoint omits them) the progress bar is hidden and
/// only the name + status chip are shown, matching the previous list-row behaviour.
///
/// Usage:
/// ```swift
/// StocktakeSessionSummaryView(session: session)
/// ```
public struct StocktakeSessionSummaryView: View {

    // MARK: Input

    public let session: StocktakeSession

    // MARK: Derived

    /// Total rows in the session; nil when counts are unavailable.
    private var expectedItems: Int? {
        session.counts.isEmpty ? nil : session.counts.count
    }

    /// Rows where the operator has entered an actual quantity.
    private var countedItems: Int? {
        guard !session.counts.isEmpty else { return nil }
        return session.counts.filter { $0.actualQty != nil }.count
    }

    // MARK: Init

    public init(session: StocktakeSession) {
        self.session = session
    }

    // MARK: Body

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            headerRow
            if let counted = countedItems, let expected = expectedItems, expected > 0 {
                progressSection(counted: counted, expected: expected)
            }
        }
        .padding(BrandSpacing.sm)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Header row

    private var headerRow: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(session.name.isEmpty ? "Untitled" : session.name)
                    .font(.brandBodyLarge())
                    .fontWeight(.semibold)
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)

                if let location = session.location, !location.isEmpty {
                    Label(location, systemImage: "location")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                if let openedAt = session.openedAt {
                    Text(openedAt)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            Spacer()
            statusChip
        }
    }

    // MARK: - Progress section

    private func progressSection(counted: Int, expected: Int) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            ProgressView(value: Double(counted), total: Double(expected))
                .tint(progressTint(counted: counted, expected: expected))
                .accessibilityHidden(true)

            HStack {
                Text("\(counted) / \(expected) items counted")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text(percentText(counted: counted, expected: expected))
                    .font(.brandLabelSmall())
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(progressTint(counted: counted, expected: expected))
            }
        }
    }

    // MARK: - Status chip

    @ViewBuilder
    private var statusChip: some View {
        let (label, color): (String, Color) = switch session.status {
        case "open":       ("Open", .bizarreOrange)
        case "committed":  ("Done", .bizarreSuccess)
        default:           ("Cancelled", .bizarreOnSurfaceMuted)
        }
        Text(label)
            .font(.brandLabelSmall())
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, BrandSpacing.xs)
            .padding(.vertical, BrandSpacing.xxs)
            .brandGlass(.regular, in: Capsule(), tint: color.opacity(0.15))
            .accessibilityHidden(true)
    }

    // MARK: - Helpers

    private func progressTint(counted: Int, expected: Int) -> Color {
        guard expected > 0 else { return .bizarreOrange }
        let fraction = Double(counted) / Double(expected)
        if fraction >= 1.0 { return .bizarreSuccess }
        if fraction >= 0.5 { return .bizarreOrange }
        return .bizarreError
    }

    private func percentText(counted: Int, expected: Int) -> String {
        guard expected > 0 else { return "0%" }
        let pct = Int((Double(counted) / Double(expected) * 100).rounded())
        return "\(pct)%"
    }

    private var accessibilityDescription: String {
        let name = session.name.isEmpty ? "Untitled" : session.name
        var desc = "\(name), \(session.status)"
        if let counted = countedItems, let expected = expectedItems {
            desc += ", \(counted) of \(expected) items counted"
        }
        return desc
    }
}
#endif
