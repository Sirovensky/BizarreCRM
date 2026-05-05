#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core

/// §6.4 — Review sheet displayed after stocktake finalization.
/// Shows discrepancies with per-line write-off reason field.
public struct StocktakeReviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var discrepancies: [StocktakeDiscrepancy]
    let summary: StocktakeSummary
    let isOfflinePending: Bool

    public init(
        discrepancies: [StocktakeDiscrepancy],
        summary: StocktakeSummary,
        isOfflinePending: Bool = false
    ) {
        _discrepancies = State(initialValue: discrepancies)
        self.summary = summary
        self.isOfflinePending = isOfflinePending
    }

    public var body: some View {
        NavigationStack {
            List {
                if isOfflinePending {
                    Section {
                        HStack(spacing: BrandSpacing.sm) {
                            Image(systemName: "icloud.slash")
                                .foregroundStyle(.bizarreOrange)
                                .accessibilityHidden(true)
                            Text("Queued for sync — will submit when online.")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOrange)
                        }
                    }
                    .accessibilityLabel("Stocktake queued for sync when online")
                }

                summarySection

                if discrepancies.isEmpty {
                    Section {
                        HStack(spacing: BrandSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.bizarreSuccess)
                                .accessibilityHidden(true)
                            Text("No discrepancies — perfect count!")
                                .font(.brandBodyLarge())
                                .foregroundStyle(.bizarreSuccess)
                        }
                    }
                } else {
                    Section("Discrepancies (\(discrepancies.count))") {
                        ForEach($discrepancies) { $entry in
                            DiscrepancyReviewRow(entry: $entry)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Stocktake Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Dismiss stocktake review")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Summary section

    private var summarySection: some View {
        Section("Summary") {
            HStack(spacing: BrandSpacing.lg) {
                summaryCell("Counted", "\(summary.countedRows)/\(summary.totalRows)", .bizarreOnSurface)
                Divider()
                summaryCell("Surplus", "+\(summary.totalSurplus)", .bizarreOrange)
                Divider()
                summaryCell("Shortage", "-\(summary.totalShortage)", .bizarreError)
            }
            .padding(.vertical, BrandSpacing.sm)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Counted \(summary.countedRows) of \(summary.totalRows). Surplus \(summary.totalSurplus), shortage \(summary.totalShortage)"
        )
    }

    private func summaryCell(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: BrandSpacing.xxs) {
            Text(value)
                .font(.brandTitleMedium())
                .foregroundStyle(color)
                .monospacedDigit()
            Text(title)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Discrepancy row with write-off reason

private struct DiscrepancyReviewRow: View {
    @Binding var entry: StocktakeDiscrepancy

    private let writeOffReasons = [
        "Counted correctly", "Damage/shrinkage", "Theft",
        "Transfer", "Data entry error", "Other"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(entry.name)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("SKU: \(entry.sku)")
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .textSelection(.enabled)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                    Text("\(entry.actualQty) / \(entry.expectedQty)")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                    Text(entry.delta > 0 ? "+\(entry.delta)" : "\(entry.delta)")
                        .font(.brandLabelSmall())
                        .foregroundStyle(entry.isSurplus ? .bizarreOrange : .bizarreError)
                }
            }

            if entry.isShortage {
                Picker("Reason", selection: $entry.writeOffReason) {
                    Text("Select reason…").tag(String?.none)
                    ForEach(writeOffReasons, id: \.self) { reason in
                        Text(reason).tag(String?.some(reason))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Write-off reason for \(entry.name)")
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .contain)
    }
}
#endif
