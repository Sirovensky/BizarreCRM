import WidgetKit
import SwiftUI
import Core
import DesignSystem

// MARK: - Provider

struct TodaysRevenueProvider: TimelineProvider {

    func placeholder(in context: Context) -> TodaysRevenueEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (TodaysRevenueEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodaysRevenueEntry>) -> Void) {
        let entry = currentEntry()
        let intervalMinutes = WidgetSharedStore.refreshIntervalMinutes
        let refreshDate = Calendar.current.date(
            byAdding: .minute,
            value: intervalMinutes,
            to: entry.date
        ) ?? entry.date.addingTimeInterval(15 * 60)
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }

    private func currentEntry() -> TodaysRevenueEntry {
        let snapshot = WidgetSharedStore.snapshot
        return TodaysRevenueEntry(
            date: .now,
            revenueTodayCents: snapshot?.revenueTodayCents ?? 0,
            revenueDeltaCents: snapshot?.revenueDeltaCents ?? 0,
            isPlaceholder: snapshot == nil
        )
    }
}

// MARK: - Entry

struct TodaysRevenueEntry: TimelineEntry {
    let date: Date
    let revenueTodayCents: Int
    let revenueDeltaCents: Int
    let isPlaceholder: Bool

    static let placeholder = TodaysRevenueEntry(
        date: .now,
        revenueTodayCents: 4_285_50,
        revenueDeltaCents: 382_00,
        isPlaceholder: true
    )

    /// Revenue formatted as currency string.
    var formattedRevenue: String {
        let dollars = Double(revenueTodayCents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: dollars)) ?? "$0.00"
    }

    /// Delta as "+$X.XX" or "-$X.XX".
    var formattedDelta: String {
        let absCents = abs(revenueDeltaCents)
        let dollars = Double(absCents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let absStr = formatter.string(from: NSNumber(value: dollars)) ?? "$0.00"
        return (revenueDeltaCents >= 0 ? "+" : "-") + absStr
    }

    var deltaColor: Color {
        revenueDeltaCents >= 0 ? .green : .red
    }
}

// MARK: - Small view

struct TodaysRevenueSmallView: View {
    let entry: TodaysRevenueEntry
    // §24.1 Privacy — redact revenue amount on lock screen / redacted widget family.
    @Environment(\.redactionReasons) private var redactionReasons
    private var isRedacted: Bool { redactionReasons.contains(.privacy) }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Label {
                Text("Today's Revenue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Today's Revenue")
            } icon: {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }

            Spacer()

            // §24.1 — Revenue replaced with "••••" when privacy redaction is active.
            Text(isRedacted ? "••••" : entry.formattedRevenue)
                .font(.brandHeadlineMedium())
                .fontWeight(.bold)
                .minimumScaleFactor(0.5)
                .accessibilityLabel(isRedacted ? "Revenue hidden" : "Revenue today: \(entry.formattedRevenue)")
                .privacySensitive()

            if !isRedacted {
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    Image(systemName: entry.revenueDeltaCents >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2)
                        .foregroundStyle(entry.deltaColor)
                        .accessibilityHidden(true)
                    Text(entry.formattedDelta)
                        .font(.caption2)
                        .foregroundStyle(entry.deltaColor)
                        .accessibilityLabel("vs yesterday: \(entry.formattedDelta)")
                }
                .privacySensitive()
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
        // §24 deep-link: tapping the whole small widget opens the revenue dashboard.
        .widgetURL(URL(string: "bizarrecrm://dashboard/revenue")!)
    }
}

// MARK: - Medium view

struct TodaysRevenueMediumView: View {
    let entry: TodaysRevenueEntry
    // §24.1 Privacy — redact revenue amount on lock screen / redacted widget family.
    @Environment(\.redactionReasons) private var redactionReasons
    private var isRedacted: Bool { redactionReasons.contains(.privacy) }

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.xl) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Today's Revenue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Today's Revenue")

                // §24.1 — Revenue replaced with "••••" when privacy redaction is active.
                Text(isRedacted ? "••••" : entry.formattedRevenue)
                    .font(.brandDisplayMedium())
                    .fontWeight(.bold)
                    .minimumScaleFactor(0.4)
                    .accessibilityLabel(isRedacted ? "Revenue hidden" : "Revenue: \(entry.formattedRevenue)")
                    .privacySensitive()
            }

            Divider()

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("vs Yesterday")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                if isRedacted {
                    Text("••••")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.secondary)
                        .privacySensitive()
                        .accessibilityLabel("Delta hidden")
                } else {
                    HStack(spacing: DesignTokens.Spacing.xxs) {
                        Image(systemName: entry.revenueDeltaCents >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .foregroundStyle(entry.deltaColor)
                            .accessibilityHidden(true)
                        Text(entry.formattedDelta)
                            .font(.brandTitleSmall())
                            .foregroundStyle(entry.deltaColor)
                            .accessibilityLabel("Delta vs yesterday: \(entry.formattedDelta)")
                    }
                    .privacySensitive()
                }

                Text("Updated \(entry.date, style: .time)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Last updated at \(entry.date.formatted(date: .omitted, time: .shortened))")
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget

struct TodaysRevenueWidget: Widget {
    static let kind = "TodaysRevenueWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TodaysRevenueProvider()) { entry in
            TodaysRevenueWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today's Revenue")
        .description("Track today's total revenue and compare to yesterday.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodaysRevenueWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: TodaysRevenueEntry

    var body: some View {
        switch family {
        case .systemSmall:  TodaysRevenueSmallView(entry: entry)
        case .systemMedium: TodaysRevenueMediumView(entry: entry)
        default:            TodaysRevenueSmallView(entry: entry)
        }
    }
}
