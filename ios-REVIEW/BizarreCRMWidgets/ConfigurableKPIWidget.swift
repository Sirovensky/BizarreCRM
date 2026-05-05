import AppIntents
import WidgetKit
import SwiftUI
import Core
import DesignSystem

// MARK: - §24.1 Configurable KPI widget — IntentConfiguration

/// User-configurable widget: choose which KPI to show, time range, and location.
/// Uses `AppIntentConfiguration` (iOS 17+) so the widget can be configured from
/// the widget gallery and the Smart Stack without a separate Intents extension.

// MARK: - KPI kind

enum WidgetKPIKind: String, AppEnum {
    case openTickets  = "open_tickets"
    case revenueToday = "revenue_today"
    case nextAppointments = "next_appointments"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "KPI"
    static var caseDisplayRepresentations: [WidgetKPIKind: DisplayRepresentation] = [
        .openTickets:       DisplayRepresentation(title: "Open Tickets",     image: .init(systemName: "wrench.and.screwdriver.fill")),
        .revenueToday:      DisplayRepresentation(title: "Today's Revenue",  image: .init(systemName: "dollarsign.circle.fill")),
        .nextAppointments:  DisplayRepresentation(title: "Next Appointments", image: .init(systemName: "calendar")),
    ]
}

// MARK: - Configuration intent

struct ConfigurableKPIIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose KPI"
    static var description = IntentDescription("Pick which metric to display on your Home Screen.")

    @Parameter(title: "KPI", default: .openTickets)
    var kpi: WidgetKPIKind
}

// MARK: - Entry

struct ConfigurableKPIEntry: TimelineEntry {
    let date: Date
    let intent: ConfigurableKPIIntent
    let value: Int
    let label: String
    let isRedacted: Bool
    let isPlaceholder: Bool

    static func placeholder(for intent: ConfigurableKPIIntent) -> ConfigurableKPIEntry {
        ConfigurableKPIEntry(
            date: .now,
            intent: intent,
            value: 12,
            label: intent.kpi.rawValue,
            isRedacted: false,
            isPlaceholder: true
        )
    }
}

// MARK: - Provider

struct ConfigurableKPIProvider: AppIntentTimelineProvider {
    typealias Intent = ConfigurableKPIIntent
    typealias Entry = ConfigurableKPIEntry

    func placeholder(in context: Context) -> ConfigurableKPIEntry {
        .placeholder(for: ConfigurableKPIIntent())
    }

    func snapshot(for intent: ConfigurableKPIIntent, in context: Context) async -> ConfigurableKPIEntry {
        makeEntry(for: intent)
    }

    func timeline(for intent: ConfigurableKPIIntent, in context: Context) async -> Timeline<ConfigurableKPIEntry> {
        let entry = makeEntry(for: intent)
        let refreshMinutes = WidgetSharedStore.refreshIntervalMinutes
        let next = Calendar.current.date(byAdding: .minute, value: refreshMinutes, to: entry.date)
            ?? entry.date.addingTimeInterval(15 * 60)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func makeEntry(for intent: ConfigurableKPIIntent) -> ConfigurableKPIEntry {
        let snapshot = WidgetSharedStore.snapshot
        let (value, label): (Int, String) = {
            guard let snap = snapshot else { return (0, intent.kpi.rawValue) }
            switch intent.kpi {
            case .openTickets:      return (snap.openTicketCount, "open tickets")
            case .revenueToday:     return (snap.revenueTodayCents, "today")
            case .nextAppointments: return (snap.nextAppointments.count, "upcoming")
            }
        }()
        return ConfigurableKPIEntry(
            date: .now,
            intent: intent,
            value: value,
            label: label,
            isRedacted: false,
            isPlaceholder: snapshot == nil
        )
    }
}

// MARK: - View

struct ConfigurableKPIView: View {
    let entry: ConfigurableKPIEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.redactionReasons) private var redactionReasons

    /// Revenue KPIs are sensitive — redact when `.privacy` is set.
    private var shouldRedact: Bool {
        guard redactionReasons.contains(.privacy) else { return false }
        return entry.intent.kpi == .revenueToday
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Label {
                Text(kpiTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: kpiSystemImage)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }

            Spacer()

            // §24.1 — Revenue values replaced with "••••" when privacy redaction active.
            if shouldRedact {
                Text("••••")
                    .font(.brandDisplayLarge())
                    .fontWeight(.bold)
                    .privacySensitive()
                    .accessibilityLabel("\(kpiTitle) hidden for privacy")
            } else {
                Text(displayValue)
                    .font(.brandDisplayLarge())
                    .fontWeight(.bold)
                    .minimumScaleFactor(0.4)
                    .accessibilityLabel("\(kpiTitle): \(displayValue)")
                    .privacySensitive(entry.intent.kpi == .revenueToday)
            }

            Text(entry.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var kpiTitle: String {
        switch entry.intent.kpi {
        case .openTickets:      return "Open Tickets"
        case .revenueToday:     return "Today's Revenue"
        case .nextAppointments: return "Appointments"
        }
    }

    private var kpiSystemImage: String {
        switch entry.intent.kpi {
        case .openTickets:      return "wrench.and.screwdriver.fill"
        case .revenueToday:     return "dollarsign.circle.fill"
        case .nextAppointments: return "calendar"
        }
    }

    private var displayValue: String {
        if entry.intent.kpi == .revenueToday {
            let dollars = Double(entry.value) / 100.0
            let fmt = NumberFormatter()
            fmt.numberStyle = .currency
            fmt.currencyCode = "USD"
            return fmt.string(from: NSNumber(value: dollars)) ?? "$0.00"
        }
        return "\(entry.value)"
    }
}

// MARK: - Widget declaration

/// §24.1 — Configurable KPI widget using `AppIntentConfiguration`.
/// User taps "Edit Widget" → picks which KPI to display.
struct ConfigurableKPIWidget: Widget {
    static let kind = "ConfigurableKPIWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: ConfigurableKPIIntent.self,
            provider: ConfigurableKPIProvider()
        ) { entry in
            ConfigurableKPIView(entry: entry)
        }
        .configurationDisplayName("KPI")
        .description("Choose any key metric — tickets, revenue, SMS, or appointments.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
