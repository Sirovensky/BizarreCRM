import SwiftUI
import DesignSystem

// MARK: - CustomDateRangeSheet
//
// §15.1 — Custom date-range picker with one-tap quick-presets.
//
// Quick presets (Today / Yesterday / Last 7 days / This month /
// Last month / This year / All time) let users pick common windows
// without manually operating two DatePickers.  The free-form DatePicker
// pair below the chips covers any non-standard range.
//
// The caller supplies `from` and `to` Binding<Date> values and an
// `onApply` closure that is invoked when the user taps "Apply".

public struct CustomDateRangeSheet: View {
    @Binding var from: Date
    @Binding var to: Date
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    public init(from: Binding<Date>, to: Binding<Date>, onApply: @escaping () -> Void) {
        _from = from
        _to = to
        self.onApply = onApply
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                        // Quick-preset chips
                        sectionHeader("Quick Presets")
                        quickPresetsGrid
                        // Free-form date pickers
                        sectionHeader("Custom Range")
                        datePickerSection
                    }
                    .padding(BrandSpacing.base)
                    .padding(.bottom, BrandSpacing.xxl)
                }
            }
            .navigationTitle("Select Date Range")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        // Ensure from <= to before applying.
                        if from > to { swap(&from, &to) }
                        onApply()
                    }
                    .fontWeight(.semibold)
                    .tint(.bizarreOrange)
                }
            }
        }
    }

    // MARK: - Quick Presets

    private var quickPresetsGrid: some View {
        // Two-column grid of preset chips.
        let columns = [GridItem(.flexible(), spacing: BrandSpacing.sm),
                       GridItem(.flexible(), spacing: BrandSpacing.sm)]
        return LazyVGrid(columns: columns, spacing: BrandSpacing.sm) {
            ForEach(DateQuickPreset.allCases) { preset in
                Button {
                    applyPreset(preset)
                } label: {
                    Text(preset.displayLabel)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BrandSpacing.sm)
                        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quick preset: \(preset.displayLabel)")
            }
        }
    }

    // MARK: - Date Picker Section

    private var datePickerSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            DatePicker(
                "From",
                selection: $from,
                in: ...to,
                displayedComponents: .date
            )
            .tint(.bizarreOrange)
            .accessibilityLabel("Start date")

            Divider()

            DatePicker(
                "To",
                selection: $to,
                in: from...,
                displayedComponents: .date
            )
            .tint(.bizarreOrange)
            .accessibilityLabel("End date")
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .textCase(.uppercase)
    }

    private func applyPreset(_ preset: DateQuickPreset) {
        let (newFrom, newTo) = preset.dateRange()
        from = newFrom
        to = newTo
    }
}

// MARK: - DateQuickPreset

/// Quick date-range presets exposed in the custom date picker sheet.
public enum DateQuickPreset: String, CaseIterable, Identifiable, Sendable {
    case today       = "Today"
    case yesterday   = "Yesterday"
    case last7days   = "Last 7 Days"
    case last30days  = "Last 30 Days"
    case thisMonth   = "This Month"
    case lastMonth   = "Last Month"
    case thisYear    = "This Year"
    case allTime     = "All Time"

    public var id: String { rawValue }
    public var displayLabel: String { rawValue }

    /// Returns `(from, to)` for this preset relative to `now` (default: `Date()`).
    public func dateRange(relativeTo now: Date = Date()) -> (from: Date, to: Date) {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)

        switch self {
        case .today:
            return (startOfToday, now)

        case .yesterday:
            let start = cal.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
            let end   = cal.date(byAdding: .second, value: -1, to: startOfToday) ?? now
            return (start, end)

        case .last7days:
            let start = cal.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday
            return (start, now)

        case .last30days:
            let start = cal.date(byAdding: .day, value: -30, to: startOfToday) ?? startOfToday
            return (start, now)

        case .thisMonth:
            let comps = cal.dateComponents([.year, .month], from: now)
            let start = cal.date(from: comps) ?? startOfToday
            return (start, now)

        case .lastMonth:
            let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? startOfToday
            let start = cal.date(byAdding: .month, value: -1, to: thisMonthStart) ?? startOfToday
            let end   = cal.date(byAdding: .second, value: -1, to: thisMonthStart) ?? now
            return (start, end)

        case .thisYear:
            let comps = cal.dateComponents([.year], from: now)
            let start = cal.date(from: comps) ?? startOfToday
            return (start, now)

        case .allTime:
            // Epoch start — server will clamp to tenant's earliest record.
            let epoch = Date(timeIntervalSince1970: 0)
            return (epoch, now)
        }
    }
}
