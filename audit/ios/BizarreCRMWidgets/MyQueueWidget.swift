import WidgetKit
import SwiftUI
import Core
import DesignSystem

// MARK: - Provider

struct MyQueueProvider: TimelineProvider {

    func placeholder(in context: Context) -> MyQueueEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (MyQueueEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MyQueueEntry>) -> Void) {
        let entry = currentEntry()
        let intervalMinutes = WidgetSharedStore.refreshIntervalMinutes
        let refreshDate = Calendar.current.date(
            byAdding: .minute,
            value: intervalMinutes,
            to: entry.date
        ) ?? entry.date.addingTimeInterval(15 * 60)
        // §24 refresh schedule: policy .after(refreshDate) so WidgetKit reloads
        // at the configured interval (5/15/30 min set in WidgetSettingsView).
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }

    private func currentEntry() -> MyQueueEntry {
        let snapshot = WidgetSharedStore.snapshot
        return MyQueueEntry(
            date: .now,
            tickets: snapshot?.myQueueTickets ?? [],
            isPlaceholder: snapshot == nil
        )
    }
}

// MARK: - Entry

struct MyQueueEntry: TimelineEntry {
    let date: Date
    let tickets: [WidgetSnapshot.TicketSummary]
    let isPlaceholder: Bool

    static let placeholder = MyQueueEntry(
        date: .now,
        tickets: [
            .init(id: 101, displayId: "T-101", customerName: "Alice B.", status: "in_progress", deviceSummary: "iPhone 15"),
            .init(id: 102, displayId: "T-102", customerName: "Bob C.", status: "awaiting_parts", deviceSummary: "MacBook Pro"),
            .init(id: 103, displayId: "T-103", customerName: "Carol D.", status: "intake", deviceSummary: nil)
        ],
        isPlaceholder: true
    )
}

// MARK: - Medium view

/// Medium (4×2): up to 3 tickets assigned to the signed-in technician.
struct MyQueueMediumView: View {
    let entry: MyQueueEntry

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Label {
                Text("My Queue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("My Queue")
            } icon: {
                Image(systemName: "person.crop.circle.badge.clock")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }

            if entry.tickets.isEmpty {
                Spacer()
                Text("Queue empty — all done!")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel("My queue is empty")
                Spacer()
            } else {
                ForEach(entry.tickets.prefix(3)) { ticket in
                    // §24 deep-link: each row taps into the specific ticket.
                    Link(destination: URL(string: "bizarrecrm://tickets/\(ticket.id)")!) {
                        MyQueueRowView(ticket: ticket)
                    }
                    .accessibilityLabel("Ticket \(ticket.displayId) for \(ticket.customerName)")
                }
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
        // §24 deep-link: tapping outside a row opens the full queue list.
        .widgetURL(URL(string: "bizarrecrm://tickets?filter=mine")!)
    }
}

// MARK: - Shared row subview

private struct MyQueueRowView: View {
    let ticket: WidgetSnapshot.TicketSummary

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(ticket.displayId)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(ticket.customerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let device = ticket.deviceSummary {
                Text(device)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private var statusColor: Color {
        switch ticket.status {
        case "in_progress":    return .blue
        case "awaiting_parts": return .orange
        case "ready":          return .green
        case "intake":         return .gray
        default:               return .secondary
        }
    }
}

// MARK: - Widget

/// Medium home-screen widget showing the signed-in technician's assigned ticket queue.
///
/// Data source: `WidgetSnapshot.myQueueTickets` written by the main app on sync
/// using the current user's employee ID filter. Refreshes on the same
/// configurable 5/15/30-minute schedule as other widgets.
struct MyQueueWidget: Widget {
    static let kind = "MyQueueWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: MyQueueProvider()) { entry in
            MyQueueMediumView(entry: entry)
        }
        .configurationDisplayName("My Queue")
        .description("See the repair tickets assigned to you right now.")
        .supportedFamilies([.systemMedium])
    }
}
