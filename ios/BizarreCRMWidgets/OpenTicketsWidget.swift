import WidgetKit
import SwiftUI
import Core
import DesignSystem

// MARK: - Provider

struct OpenTicketsProvider: TimelineProvider {

    func placeholder(in context: Context) -> OpenTicketsEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (OpenTicketsEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OpenTicketsEntry>) -> Void) {
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

    private func currentEntry() -> OpenTicketsEntry {
        let snapshot = WidgetSharedStore.snapshot
        return OpenTicketsEntry(
            date: .now,
            openCount: snapshot?.openTicketCount ?? 0,
            tickets: snapshot?.latestTickets ?? [],
            isPlaceholder: snapshot == nil
        )
    }
}

// MARK: - Entry

struct OpenTicketsEntry: TimelineEntry {
    let date: Date
    let openCount: Int
    let tickets: [WidgetSnapshot.TicketSummary]
    let isPlaceholder: Bool

    static let placeholder = OpenTicketsEntry(
        date: .now,
        openCount: 12,
        tickets: [
            .init(id: 1, displayId: "T-001", customerName: "Alice B.", status: "in_progress", deviceSummary: "iPhone 15"),
            .init(id: 2, displayId: "T-002", customerName: "Bob C.", status: "intake", deviceSummary: "MacBook Pro"),
            .init(id: 3, displayId: "T-003", customerName: "Carol D.", status: "awaiting_parts", deviceSummary: nil)
        ],
        isPlaceholder: true
    )
}

// MARK: - Views

/// Small (2×2): ticket count + delta badge.
struct OpenTicketsSmallView: View {
    let entry: OpenTicketsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Label {
                Text("Open Tickets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Open Tickets")
            } icon: {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }

            Spacer()

            Text("\(entry.openCount)")
                .font(.brandDisplayLarge())
                .fontWeight(.bold)
                .accessibilityLabel("\(entry.openCount) open tickets")
                .minimumScaleFactor(0.5)

            Text(entry.isPlaceholder ? "Tap to open" : "tickets need attention")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
        // §24 deep-link: tapping the whole small widget opens the tickets list.
        .widgetURL(URL(string: "bizarrecrm://tickets")!)
    }
}

/// Medium (4×2): open count + 3 latest tickets.
struct OpenTicketsMediumView: View {
    let entry: OpenTicketsEntry

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Tickets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Open Tickets")

                Text("\(entry.openCount)")
                    .font(.brandHeadlineLarge())
                    .fontWeight(.bold)
                    .accessibilityLabel("\(entry.openCount) open")

                Text("open")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(width: 60)

            Divider()

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                ForEach(entry.tickets.prefix(3)) { ticket in
                    Link(destination: URL(string: "bizarrecrm://tickets/\(ticket.id)")!) {
                        TicketRowView(ticket: ticket)
                    }
                }
                if entry.tickets.isEmpty {
                    Text("No open tickets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("No open tickets")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignTokens.Spacing.sm)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

/// Large (4×4): open count + up to 10 latest tickets.
struct OpenTicketsLargeView: View {
    let entry: OpenTicketsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Label {
                    Text("Open Tickets")
                        .font(.brandTitleMedium())
                        .accessibilityLabel("Open Tickets")
                } icon: {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
                Spacer()
                Text("\(entry.openCount) open")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(entry.openCount) open tickets")
            }

            Divider()

            if entry.tickets.isEmpty {
                Spacer()
                Text("All caught up!")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel("All tickets handled")
                Spacer()
            } else {
                ForEach(entry.tickets.prefix(10)) { ticket in
                    Link(destination: URL(string: "bizarrecrm://tickets/\(ticket.id)")!) {
                        TicketRowView(ticket: ticket)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Shared row subview

private struct TicketRowView: View {
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
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ticket.displayId), \(ticket.customerName), status: \(ticket.status)")
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

// MARK: - Widget declaration

struct OpenTicketsWidget: Widget {
    static let kind = "OpenTicketsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: OpenTicketsProvider()) { entry in
            OpenTicketsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Open Tickets")
        .description("See how many tickets are waiting for attention.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct OpenTicketsWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: OpenTicketsEntry

    var body: some View {
        switch family {
        case .systemSmall:  OpenTicketsSmallView(entry: entry)
        case .systemMedium: OpenTicketsMediumView(entry: entry)
        case .systemLarge:  OpenTicketsLargeView(entry: entry)
        default:            OpenTicketsSmallView(entry: entry)
        }
    }
}
