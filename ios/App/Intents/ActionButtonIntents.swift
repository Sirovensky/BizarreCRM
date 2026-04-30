import AppIntents
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §24.7 Action Button (iPhone 15 Pro+)
//
// Users can map the iPhone 15 Pro / 16 Action Button to an App Intent
// via Settings → Action Button → Shortcuts → select a "Bizarre CRM" shortcut.
//
// We expose two primary App Intents for Action Button use:
//   1. CreateTicketActionIntent  — opens New Ticket (default recommendation)
//   2. ClockInOutActionIntent    — toggles clock in/out
//
// Both are already in the App Intents catalog from §24.4. This file registers
// them as recommended Action Button targets via `AppShortcutsProvider`
// phrases + `WidgetBundle`-style exposure so they appear in Action Button picker.
//
// Implementation: expose a dedicated `ActionButtonRecommendations` set so the
// system can suggest them in the Action Button settings pane.

// MARK: - CreateTicket for Action Button

/// §24.7 — "Create Ticket" via Action Button.
/// Opens the new-ticket flow directly from the hardware button.
struct CreateTicketActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Create New Ticket"
    static let description: IntentDescription = IntentDescription(
        "Open the new ticket form in Bizarre CRM.",
        categoryName: "Tickets"
    )
    static let openAppWhenRun: Bool = true

    // Surface to Action Button picker
    static let isDiscoverable: Bool = true

    func perform() async throws -> some IntentResult {
        await openURL("bizarrecrm://tickets/new")
        return .result()
    }
}

// MARK: - Clock In/Out for Action Button

/// §24.7 — Alt mapping: "Clock In/Out" via Action Button.
/// Toggles shift timer directly from the hardware button.
struct ClockInOutActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Clock In / Clock Out"
    static let description: IntentDescription = IntentDescription(
        "Toggle your shift clock in Bizarre CRM.",
        categoryName: "Timeclock"
    )
    static let openAppWhenRun: Bool = true
    static let isDiscoverable: Bool = true

    func perform() async throws -> some IntentResult {
        await openURL("bizarrecrm://timeclock")
        return .result()
    }
}

// MARK: - Action Button Shortcuts Provider

/// Exposes Action Button-compatible shortcuts.
/// System presents these in Settings → Action Button → Shortcut when our app is installed.
struct BizarreCRMActionButtonProvider: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateTicketActionIntent(),
            phrases: [
                "Create ticket in \(.applicationName)",
                "New repair ticket in \(.applicationName)",
                "Open new ticket in \(.applicationName)"
            ],
            shortTitle: "New Ticket",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: ClockInOutActionIntent(),
            phrases: [
                "Clock in with \(.applicationName)",
                "Clock out of \(.applicationName)",
                "Toggle clock in \(.applicationName)"
            ],
            shortTitle: "Clock In/Out",
            systemImageName: "clock"
        )
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
