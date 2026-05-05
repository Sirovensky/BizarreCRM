import WidgetKit
import SwiftUI
import Core
import DesignSystem

// MARK: - Provider

struct AppointmentsNextProvider: TimelineProvider {

    func placeholder(in context: Context) -> AppointmentsNextEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (AppointmentsNextEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AppointmentsNextEntry>) -> Void) {
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

    private func currentEntry() -> AppointmentsNextEntry {
        let snapshot = WidgetSharedStore.snapshot
        return AppointmentsNextEntry(
            date: .now,
            appointments: snapshot?.nextAppointments ?? [],
            isPlaceholder: snapshot == nil
        )
    }
}

// MARK: - Entry

struct AppointmentsNextEntry: TimelineEntry {
    let date: Date
    let appointments: [WidgetSnapshot.AppointmentSummary]
    let isPlaceholder: Bool

    static let placeholder = AppointmentsNextEntry(
        date: .now,
        appointments: [
            .init(id: 1, customerName: "Alice Brown", scheduledAt: Date().addingTimeInterval(1800)),
            .init(id: 2, customerName: "Bob Chen", scheduledAt: Date().addingTimeInterval(5400)),
            .init(id: 3, customerName: "Carol Davis", scheduledAt: Date().addingTimeInterval(10800))
        ],
        isPlaceholder: true
    )

    var nextAppointment: WidgetSnapshot.AppointmentSummary? { appointments.first }
}

// MARK: - Medium view

struct AppointmentsNextMediumView: View {
    let entry: AppointmentsNextEntry

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Label {
                Text("Next Appointments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Next Appointments")
            } icon: {
                Image(systemName: "calendar")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }

            if entry.appointments.isEmpty {
                Spacer()
                Text("No upcoming appointments")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel("No upcoming appointments")
                Spacer()
            } else {
                ForEach(entry.appointments.prefix(3)) { appt in
                    Link(destination: URL(string: "bizarrecrm://appointments/\(appt.id)")!) {
                        AppointmentRowView(appointment: appt)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Large view

struct AppointmentsNextLargeView: View {
    let entry: AppointmentsNextEntry

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Label {
                    Text("Upcoming Appointments")
                        .font(.brandTitleMedium())
                        .accessibilityLabel("Upcoming Appointments")
                } icon: {
                    Image(systemName: "calendar")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
                Spacer()
                Text("\(entry.appointments.count) today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(entry.appointments.count) appointments today")
            }

            Divider()

            if entry.appointments.isEmpty {
                Spacer()
                Text("No upcoming appointments")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel("No upcoming appointments")
                Spacer()
            } else {
                ForEach(entry.appointments) { appt in
                    Link(destination: URL(string: "bizarrecrm://appointments/\(appt.id)")!) {
                        AppointmentRowView(appointment: appt)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Shared row subview

private struct AppointmentRowView: View {
    let appointment: WidgetSnapshot.AppointmentSummary

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "person.fill")
                .font(.caption2)
                .foregroundStyle(.tint)
                .frame(width: 14)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(appointment.customerName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(Self.timeFormatter.string(from: appointment.scheduledAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(appointment.customerName) at \(Self.timeFormatter.string(from: appointment.scheduledAt))")
    }
}

// MARK: - Widget

struct AppointmentsNextWidget: Widget {
    static let kind = "AppointmentsNextWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: AppointmentsNextProvider()) { entry in
            AppointmentsNextWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Next Appointments")
        .description("See your next 3 upcoming appointments.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct AppointmentsNextWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: AppointmentsNextEntry

    var body: some View {
        switch family {
        case .systemMedium: AppointmentsNextMediumView(entry: entry)
        case .systemLarge:  AppointmentsNextLargeView(entry: entry)
        default:            AppointmentsNextMediumView(entry: entry)
        }
    }
}
