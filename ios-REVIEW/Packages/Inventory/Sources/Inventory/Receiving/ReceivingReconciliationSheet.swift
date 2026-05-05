#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core

/// §6.3 — Shown after finalizing a receiving order. Lists items that were
/// over-received or under-received so the operator can review discrepancies.
public struct ReceivingReconciliationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entries: [ReconciliationEntry]

    private var overEntries: [ReconciliationEntry] { entries.filter(\.isOver) }
    private var underEntries: [ReconciliationEntry] { entries.filter(\.isUnder) }
    private var exactEntries: [ReconciliationEntry] { entries.filter(\.isExact) }

    public init(entries: [ReconciliationEntry]) {
        self.entries = entries
    }

    public var body: some View {
        NavigationStack {
            List {
                summarySection
                if !overEntries.isEmpty { discrepancySection("Over-received", entries: overEntries, color: .bizarreOrange) }
                if !underEntries.isEmpty { discrepancySection("Under-received", entries: underEntries, color: .bizarreError) }
                if !exactEntries.isEmpty { exactSection }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Reconciliation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Dismiss reconciliation summary")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            HStack(spacing: BrandSpacing.lg) {
                summaryCell(title: "Total", count: entries.count, color: .bizarreOnSurface)
                Divider()
                summaryCell(title: "Over", count: overEntries.count, color: .bizarreOrange)
                Divider()
                summaryCell(title: "Under", count: underEntries.count, color: .bizarreError)
                Divider()
                summaryCell(title: "Exact", count: exactEntries.count, color: .bizarreSuccess)
            }
            .padding(.vertical, BrandSpacing.sm)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Summary: \(entries.count) total, \(overEntries.count) over, \(underEntries.count) under, \(exactEntries.count) exact"
        )
    }

    private func summaryCell(title: String, count: Int, color: Color) -> some View {
        VStack(spacing: BrandSpacing.xxs) {
            Text("\(count)")
                .font(.brandTitleMedium())
                .foregroundStyle(color)
                .monospacedDigit()
            Text(title)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func discrepancySection(
        _ title: String,
        entries: [ReconciliationEntry],
        color: Color
    ) -> some View {
        Section(title) {
            ForEach(entries) { entry in
                HStack(spacing: BrandSpacing.sm) {
                    VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                        Text(entry.name)
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOnSurface)
                        Text("SKU: \(entry.sku)")
                            .font(.brandMono(size: 12))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                        Text("\(entry.receivedQty) / \(entry.orderedQty)")
                            .font(.brandTitleMedium())
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                        Text(entry.delta > 0 ? "+\(entry.delta)" : "\(entry.delta)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(color)
                    }
                }
                .padding(.vertical, BrandSpacing.xs)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(entry.name), ordered \(entry.orderedQty), received \(entry.receivedQty), delta \(entry.delta)"
                )
            }
        }
    }

    private var exactSection: some View {
        Section("Exact match (\(exactEntries.count))") {
            ForEach(exactEntries) { entry in
                HStack {
                    Text(entry.name)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    Text("\(entry.receivedQty)")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreSuccess)
                        .monospacedDigit()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.bizarreSuccess)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(entry.name), received \(entry.receivedQty), exact match")
            }
        }
    }
}
#endif
