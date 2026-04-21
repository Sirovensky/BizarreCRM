import WidgetKit
import SwiftUI
import Core
import DesignSystem

// MARK: - Provider

struct LockScreenProvider: TimelineProvider {

    func placeholder(in context: Context) -> LockScreenEntry {
        LockScreenEntry(date: .now, openTicketCount: 5, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (LockScreenEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LockScreenEntry>) -> Void) {
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

    private func currentEntry() -> LockScreenEntry {
        let snapshot = WidgetSharedStore.snapshot
        return LockScreenEntry(
            date: .now,
            openTicketCount: snapshot?.openTicketCount ?? 0,
            isPlaceholder: snapshot == nil
        )
    }
}

// MARK: - Entry

struct LockScreenEntry: TimelineEntry {
    let date: Date
    let openTicketCount: Int
    let isPlaceholder: Bool
}

// MARK: - Views

/// Accessory circular: ticket count badge.
struct AccessoryCircularView: View {
    let entry: LockScreenEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 10))
                    .accessibilityHidden(true)
                Text("\(entry.openTicketCount)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
            }
            .accessibilityLabel("\(entry.openTicketCount) open tickets")
        }
        .containerBackground(.clear, for: .widget)
    }
}

/// Accessory rectangular: "X tickets ready" text.
struct AccessoryRectangularView: View {
    let entry: LockScreenEntry

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .accessibilityHidden(true)
            Text("\(entry.openTicketCount) tickets open")
                .font(.caption)
                .minimumScaleFactor(0.7)
                .accessibilityLabel("\(entry.openTicketCount) tickets open")
        }
        .containerBackground(.clear, for: .widget)
    }
}

/// Accessory inline: single-line compact text.
struct AccessoryInlineView: View {
    let entry: LockScreenEntry

    var body: some View {
        Label {
            Text("\(entry.openTicketCount) open tickets")
                .accessibilityLabel("\(entry.openTicketCount) open tickets")
        } icon: {
            Image(systemName: "wrench.and.screwdriver.fill")
                .accessibilityHidden(true)
        }
        .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Widget

/// Lock Screen complications for iOS 16+ and StandBy mode.
///
/// Supported families:
/// - `.accessoryCircular` — circular badge (ticket count).
/// - `.accessoryRectangular` — wide rectangular (ticket count text).
/// - `.accessoryInline` — single-line (ticket count).
struct LockScreenComplicationsWidget: Widget {
    static let kind = "LockScreenComplicationsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: LockScreenProvider()) { entry in
            LockScreenComplicationsEntryView(entry: entry)
        }
        .configurationDisplayName("BizarreCRM — Tickets")
        .description("Show open ticket count on the lock screen and in StandBy.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct LockScreenComplicationsEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: LockScreenEntry

    var body: some View {
        switch family {
        case .accessoryCircular:    AccessoryCircularView(entry: entry)
        case .accessoryRectangular: AccessoryRectangularView(entry: entry)
        case .accessoryInline:      AccessoryInlineView(entry: entry)
        default:                    AccessoryCircularView(entry: entry)
        }
    }
}
