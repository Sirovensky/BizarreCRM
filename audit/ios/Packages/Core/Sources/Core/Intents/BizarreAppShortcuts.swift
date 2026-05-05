import AppIntents
#if os(iOS)

/// Registers all BizarreCRM App Shortcuts so they surface in the Shortcuts app,
/// Siri, Spotlight suggestions, and the Action Button.
///
/// `AppShortcutsProvider` self-registers on import — no additional wiring required
/// in `BizarreCRMApp.swift` beyond ensuring this module is linked.
@available(iOS 16, *)
public struct BizarreAppShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewTicketIntent(),
            phrases: [
                "New ticket in \(.applicationName)",
                "Create ticket in \(.applicationName)",
                "New repair in \(.applicationName)"
            ],
            shortTitle: "New Ticket",
            systemImageName: "ticket"
        )
        AppShortcut(
            intent: FindCustomerIntent(),
            phrases: [
                "Find customer in \(.applicationName)",
                "Search customer in \(.applicationName)"
            ],
            shortTitle: "Find Customer",
            systemImageName: "person.fill.questionmark"
        )
        AppShortcut(
            intent: NextAppointmentIntent(),
            phrases: [
                "Next appointment in \(.applicationName)",
                "When is my next appointment in \(.applicationName)"
            ],
            shortTitle: "Next Appointment",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: TodaysRevenueIntent(),
            phrases: [
                "Today's revenue in \(.applicationName)",
                "How much revenue today in \(.applicationName)"
            ],
            shortTitle: "Today's Revenue",
            systemImageName: "dollarsign.circle"
        )
        AppShortcut(
            intent: ClockInIntent(),
            phrases: [
                "Clock in to \(.applicationName)",
                "Start my shift in \(.applicationName)"
            ],
            shortTitle: "Clock In",
            systemImageName: "clock.fill"
        )
        AppShortcut(
            intent: ClockOutIntent(),
            phrases: [
                "Clock out of \(.applicationName)",
                "End my shift in \(.applicationName)"
            ],
            shortTitle: "Clock Out",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: OpenPosIntent(),
            phrases: [
                "Open POS in \(.applicationName)",
                "Open point of sale in \(.applicationName)"
            ],
            shortTitle: "Open POS",
            systemImageName: "cart"
        )
        AppShortcut(
            intent: OpenTicketsIntent(),
            phrases: [
                "Open tickets in \(.applicationName)",
                "Show repair tickets in \(.applicationName)"
            ],
            shortTitle: "Tickets",
            systemImageName: "wrench.and.screwdriver"
        )
        AppShortcut(
            intent: OpenDashboardIntent(),
            phrases: [
                "Open dashboard in \(.applicationName)",
                "Show dashboard in \(.applicationName)"
            ],
            shortTitle: "Dashboard",
            systemImageName: "gauge.medium"
        )
    }
}
#endif // os(iOS)
