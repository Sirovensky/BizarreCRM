import AppIntents
#if os(iOS)

/// Extends `BizarreAppShortcuts` by registering the deeper App Intents
/// (CreateTicketIntent, LookupTicketIntent, ScanBarcodeIntent) so they surface
/// in the Shortcuts gallery, Spotlight suggestions, and the Action Button.
///
/// Because `AppShortcutsProvider` works through static property composition,
/// this file declares a **separate** provider that pairs the three new intents.
/// The app shell can adopt either `BizarreAppShortcuts` or both providers.
@available(iOS 16, *)
// Not an AppShortcutsProvider (only one conformance allowed app-wide).
// App shell merges these entries into its single AppShortcutsProvider.
public enum BizarreDeepAppShortcuts {
    @AppShortcutsBuilder
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateTicketIntent(),
            phrases: [
                "Create ticket in \(.applicationName)",
                "New repair ticket in \(.applicationName)",
                "Open new ticket for customer in \(.applicationName)"
            ],
            shortTitle: "Create Ticket",
            systemImageName: "ticket.fill"
        )
        AppShortcut(
            intent: LookupTicketIntent(),
            phrases: [
                "Look up ticket in \(.applicationName)",
                "Open ticket in \(.applicationName)",
                "Find order in \(.applicationName)"
            ],
            shortTitle: "Look Up Ticket",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: ScanBarcodeIntent(),
            phrases: [
                "Scan barcode in \(.applicationName)",
                "Scan item in \(.applicationName)",
                "Scan in \(.applicationName)"
            ],
            shortTitle: "Scan Barcode",
            systemImageName: "barcode.viewfinder"
        )
    }
}
#endif // os(iOS)
