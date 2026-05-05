import WidgetKit
import SwiftUI
import Core

// MARK: - §24.1 Extra Large (iPad) — full dashboard mirror
//
// Supported family: `.systemExtraLarge` (iPad only).
// Content: 6 KPI tiles in a 3×2 grid + a short ticket list.
// Data source: same App Group UserDefaults `WidgetSnapshot` as other widgets.

// MARK: - Provider

struct DashboardMirrorProvider: TimelineProvider {
    func placeholder(in context: Context) -> DashboardMirrorEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (DashboardMirrorEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DashboardMirrorEntry>) -> Void) {
        let entry = currentEntry()
        let interval = WidgetSharedStore.refreshIntervalMinutes
        let next = Calendar.current.date(byAdding: .minute, value: interval, to: entry.date)
            ?? entry.date.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> DashboardMirrorEntry {
        let snap = WidgetSharedStore.snapshot
        return DashboardMirrorEntry(
            date: .now,
            snapshot: snap,
            isPlaceholder: snap == nil
        )
    }
}

// MARK: - Entry

struct DashboardMirrorEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let isPlaceholder: Bool

    static let placeholder = DashboardMirrorEntry(
        date: .now,
        snapshot: WidgetSnapshot(
            openTicketCount: 14,
            todayRevenue: 2_450.0,
            nextAppointmentTime: nil,
            latestTickets: [
                .init(id: 1, displayId: "T-001", customerName: "Alice B.", status: "in_progress", deviceSummary: "iPhone 15"),
                .init(id: 2, displayId: "T-002", customerName: "Bob C.", status: "intake", deviceSummary: "MacBook Pro"),
            ],
            syncedAt: Date()
        ),
        isPlaceholder: true
    )
}

// MARK: - ExtraLarge View

struct DashboardMirrorExtraLargeView: View {
    let entry: DashboardMirrorEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if entry.isPlaceholder || entry.snapshot == nil {
            placeholderContent
        } else {
            loadedContent(snapshot: entry.snapshot!)
        }
    }

    @ViewBuilder
    private func loadedContent(snapshot: WidgetSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Left: 3×2 KPI tile grid
            kpiGrid(snapshot: snapshot)
                .frame(maxWidth: .infinity)

            // Right: ticket list (up to 6)
            ticketList(tickets: snapshot.latestTickets)
                .frame(maxWidth: 200)
        }
        .padding(16)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private func kpiGrid(snapshot: WidgetSnapshot) -> some View {
        let tiles: [(String, String, String)] = [
            ("Open Tickets",       "\(snapshot.openTicketCount)",                                "wrench.and.screwdriver.fill"),
            ("Revenue Today",      currencyString(snapshot.todayRevenue),                        "dollarsign.circle.fill"),
            ("Appointments",       snapshot.nextAppointmentTime.map { appointmentLabel($0) } ?? "—",  "calendar"),
            ("Synced",             relativeTime(snapshot.syncedAt),                              "arrow.triangle.2.circlepath"),
        ]

        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10
        ) {
            ForEach(tiles, id: \.0) { tile in
                kpiTile(label: tile.0, value: tile.1, icon: tile.2)
            }
        }
    }

    @ViewBuilder
    private func kpiTile(label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                    .font(.caption2)
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .widgetURL(nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }

    @ViewBuilder
    private func ticketList(tickets: [WidgetSnapshot.TicketSummary]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Tickets", systemImage: "list.bullet.clipboard")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(tickets.prefix(6)) { ticket in
                Link(destination: URL(string: "bizarrecrm://tickets/\(ticket.id)")!) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor(ticket.status))
                            .frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ticket.displayId)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(ticket.customerName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(ticket.displayId), \(ticket.customerName), \(ticket.status)")
                }
            }

            if tickets.isEmpty {
                Text("No open tickets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var placeholderContent: some View {
        HStack {
            Text("Dashboard")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Helpers

    private func currencyString(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    private func appointmentLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 { return "Just now" }
        if diff < 3600 { return "\(diff / 60)m ago" }
        return "\(diff / 3600)h ago"
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "in_progress": return .blue
        case "awaiting_parts": return .orange
        case "ready": return .green
        default: return .gray
        }
    }
}

// MARK: - Widget declaration

struct DashboardMirrorWidget: Widget {
    static let kind = "DashboardMirrorWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: DashboardMirrorProvider()) { entry in
            DashboardMirrorExtraLargeView(entry: entry)
        }
        .configurationDisplayName("Dashboard Mirror")
        .description("Full dashboard overview with KPIs and open tickets. iPad only.")
        .supportedFamilies([.systemExtraLarge])
    }
}
