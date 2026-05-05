import AppIntents
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif
import Core

// MARK: - §24.8 Interactive Widgets (iOS 17+)
//
// Interactive widgets let the user tap a button inside the widget without opening the app.
//
// Widgets implemented here:
//   1. Toggle "Clock In" directly from widget (no app open) — via `Button { ClockInOutWidgetIntent() }`
//   2. Mark ticket done from Medium widget              — via `Button { MarkTicketDoneWidgetIntent(ticketId:) }`
//   3. Reply to SMS inline (Placeholder — full reply needs app open; shows compose intent)
//
// These intents write to App Group UserDefaults so widget can optimistically update,
// then the main app reconciles on next foreground. They DO open the app for auth-gated actions.

// MARK: - Clock In/Out Widget Intent

/// §24.8 — Toggle clock in/out directly from the widget.
/// Reads current state from App Group; fires the appropriate deep-link to main app.
struct ClockInOutWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Clock In/Out"
    static var description: IntentDescription = IntentDescription("Clock in or out of your shift.")
    // Open the app so the timeclock ViewModel can confirm the action with a PIN / biometric if required.
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Read current state and deep-link to the timeclock toggle
        await openURL("bizarrecrm://timeclock?action=toggle")
        // Optimistically flip the App Group flag so the widget updates before the app opens
        let defaults = UserDefaults(suiteName: "group.com.bizarrecrm")
        let current = defaults?.bool(forKey: "control.isClockIn") ?? false
        defaults?.set(!current, forKey: "control.isClockIn")
        WidgetCenter.shared.reloadTimelines(ofKind: "OpenTicketsWidget")
        return .result()
    }
}

// MARK: - Mark Ticket Done Widget Intent

/// §24.8 — Mark a ticket done directly from the Medium/Large widget row.
/// Opens the app to the ticket detail where the status change can be confirmed.
struct MarkTicketDoneWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Ticket Done"
    static var description: IntentDescription = IntentDescription("Complete a ticket from the widget.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Ticket ID")
    var ticketId: Int

    init() { self.ticketId = 0 }
    init(ticketId: Int) { self.ticketId = ticketId }

    func perform() async throws -> some IntentResult {
        await openURL("bizarrecrm://tickets/\(ticketId)?action=complete")
        return .result()
    }
}

// MARK: - Updated OpenTickets Medium view with interactive clock-in button

/// Extends `OpenTicketsMediumView` to include an interactive clock-in toggle button (iOS 17+).
/// The existing `OpenTicketsWidget` keeps the static layout for pre-iOS 17.
@available(iOS 17.0, *)
struct OpenTicketsInteractiveMediumView: View {
    let entry: OpenTicketsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row with count + clock-in toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Tickets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(entry.openCount)")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
                Spacer()

                // §24.8 — Interactive clock-in toggle button
                Button(intent: ClockInOutWidgetIntent()) {
                    let isClockedIn = UserDefaults(suiteName: "group.com.bizarrecrm")?
                        .bool(forKey: "control.isClockIn") ?? false
                    Image(systemName: isClockedIn ? "clock.fill" : "clock")
                        .font(.title3)
                        .foregroundStyle(isClockedIn ? .green : .secondary)
                        .accessibilityLabel(isClockedIn ? "Clock out" : "Clock in")
                }
                .buttonStyle(.plain)
            }

            // Ticket rows with "Done" button
            ForEach(entry.tickets.prefix(2)) { ticket in
                HStack(spacing: 6) {
                    Circle()
                        .fill(ticketStatusColor(ticket.status))
                        .frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ticket.displayId)
                            .font(.caption.weight(.medium))
                        Text(ticket.customerName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    // §24.8 — Mark done button
                    Button(intent: MarkTicketDoneWidgetIntent(ticketId: Int(ticket.id))) {
                        Image(systemName: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .accessibilityLabel("Mark ticket \(ticket.displayId) done")
                    }
                    .buttonStyle(.plain)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func ticketStatusColor(_ status: String) -> Color {
        switch status {
        case "in_progress": return .blue
        case "awaiting_parts": return .orange
        case "ready": return .green
        default: return .gray
        }
    }
}

// MARK: - URL helper

@MainActor
private func openURL(_ urlString: String) async {
    #if canImport(UIKit)
    guard let url = URL(string: urlString) else { return }
    await UIApplication.shared.open(url)
    #endif
}
