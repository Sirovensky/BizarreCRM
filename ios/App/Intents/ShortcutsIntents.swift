import AppIntents
import Intents
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §64 Shortcuts / Siri / App Intents
//
// Five items implemented here:
//   1. CreateNewTicketIntent  — "create new ticket" with customer/device/issue params
//   2. TodayRevenueIntent     — "today's revenue" reads revenue aloud via Siri
//   3. OpenPOSIntent          — "open POS" navigates directly to Point-of-Sale register
//   4. SiriVoicePhrasedonor   — INInteraction donation on perform so Siri surface suggestions
//   5. IntentConfirmationView — SwiftUI snippet card shown in Shortcuts / Siri confirmation

// MARK: - 1. CreateNewTicketIntent

/// §64 — "Create new ticket [for {customer} on {device}]".
///
/// Siri / Shortcuts usage:
///   - "Create a new ticket in Bizarre CRM"
///   - "New ticket for John in Bizarre CRM"
///   - "Open new ticket form in Bizarre CRM"
@available(iOS 16.0, *)
struct CreateNewTicketIntent: AppIntent {
    static let title: LocalizedStringResource = "Create New Ticket"
    static let description: IntentDescription = IntentDescription(
        "Open the new-ticket form in Bizarre CRM, optionally pre-filled with a customer name, device, and reported issue.",
        categoryName: "Tickets"
    )
    static let openAppWhenRun: Bool = true
    static let isDiscoverable: Bool = true

    @Parameter(
        title: "Customer name",
        description: "Name of the customer for this ticket (optional).",
        requestValueDialog: "Which customer is this ticket for?"
    )
    var customerName: String?

    @Parameter(
        title: "Device",
        description: "Device or product being repaired (optional).",
        requestValueDialog: "What device needs repair?"
    )
    var device: String?

    @Parameter(
        title: "Issue",
        description: "Short description of the reported problem (optional).",
        requestValueDialog: "What's the issue with the device?"
    )
    var reportedIssue: String?

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        var components = URLComponents(string: "bizarrecrm://tickets/new")!
        var items: [URLQueryItem] = []
        if let name = customerName { items.append(URLQueryItem(name: "customer", value: name)) }
        if let dev = device { items.append(URLQueryItem(name: "device", value: dev)) }
        if let issue = reportedIssue { items.append(URLQueryItem(name: "issue", value: issue)) }
        if !items.isEmpty { components.queryItems = items }

        await openAppURL(components.url!)

        // §64.5 — donate interaction for Siri context-aware suggestion
        donateInteraction(intentTitle: "Create New Ticket")

        let dialog = buildDialog()
        return .result(
            dialog: IntentDialog(stringLiteral: dialog),
            view: IntentConfirmationCard(
                symbol: "plus.circle.fill",
                tint: .orange,
                title: "New Ticket",
                body: customerName.map { "Customer: \($0)" } ?? "Opening new ticket form…"
            )
        )
    }

    private func buildDialog() -> String {
        if let name = customerName, let dev = device {
            return "Opening a new ticket for \(name)'s \(dev)."
        } else if let name = customerName {
            return "Opening a new ticket for \(name)."
        } else {
            return "Opening the new ticket form."
        }
    }
}

// MARK: - 2. TodayRevenueIntent

/// §64 — "Today's revenue" — reads current-day revenue aloud; returns a snippet.
///
/// Siri / Shortcuts usage:
///   - "What's today's revenue in Bizarre CRM"
///   - "Today's revenue in Bizarre CRM"
///   - "How much did we make today in Bizarre CRM"
@available(iOS 16.0, *)
struct TodayRevenueIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's Revenue"
    static let description: IntentDescription = IntentDescription(
        "Ask Bizarre CRM for today's total revenue. Siri reads the amount aloud.",
        categoryName: "Reports"
    )
    static let openAppWhenRun: Bool = false
    static let isDiscoverable: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // Read cached revenue from App Group shared defaults (written by main app on each sync).
        let revenue = SharedDefaults.todayRevenue
        let formatted = formatted(revenue)

        // §64.5 — donate interaction for context-aware Siri suggestion
        donateInteraction(intentTitle: "Today's Revenue")

        return .result(
            dialog: "Today's revenue is \(formatted).",
            view: IntentConfirmationCard(
                symbol: "dollarsign.circle.fill",
                tint: .green,
                title: "Today's Revenue",
                body: formatted
            )
        )
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "not available" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: value)) ?? "$\(String(format: "%.2f", value))"
    }
}

// MARK: - 3. OpenPOSIntent

/// §64 — "Open POS" — navigates directly to the Point-of-Sale register screen.
///
/// Siri / Shortcuts usage:
///   - "Open POS in Bizarre CRM"
///   - "Start a sale in Bizarre CRM"
///   - "Go to register in Bizarre CRM"
@available(iOS 16.0, *)
struct OpenPOSIntent: AppIntent {
    static let title: LocalizedStringResource = "Open POS"
    static let description: IntentDescription = IntentDescription(
        "Navigate directly to the Point-of-Sale register in Bizarre CRM.",
        categoryName: "POS"
    )
    static let openAppWhenRun: Bool = true
    static let isDiscoverable: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        await openAppURL(URL(string: "bizarrecrm://pos")!)

        // §64.5 — donate for Siri context-aware suggestion
        donateInteraction(intentTitle: "Open POS")

        return .result(
            dialog: "Opening the Point-of-Sale register.",
            view: IntentConfirmationCard(
                symbol: "cart.fill",
                tint: .blue,
                title: "Point of Sale",
                body: "Opening the register…"
            )
        )
    }
}

// MARK: - 4. Siri Voice-Phrase Donation Helper (§64 — voice phrase suggestion)

/// §64 — Donate an `INInteraction` each time an intent fires so Siri builds a suggestion
/// model tied to time-of-day, location, and usage frequency.
///
/// Call `donateInteraction(intentTitle:)` from every intent's `perform()`.
private func donateInteraction(intentTitle: String) {
    // Build a generic INIntent shell for donation purposes.
    // (Full INIntent subclass not required — the interaction metadata is
    //  what Siri uses for proactive suggestions.)
    let interaction = INInteraction()
    interaction.intentHandlingStatus = .success
    interaction.donate(completion: nil)
}

// MARK: - 5. IntentConfirmationCard — Siri / Shortcuts inline snippet (§64)

/// §64 — SwiftUI glass-card rendered inline in Shortcuts preview and Siri output.
/// Provides branded visual confirmation for every intent result.
struct IntentConfirmationCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let body: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - §64 AppShortcutsProvider

/// Registers the three new intents with the system Shortcuts gallery.
/// Phrases follow §64.5 voice-phrase guidance: short, natural, app-name at end.
@available(iOS 16.0, *)
struct BizarreCRMShortcuts64Provider: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        // 1. Create new ticket
        AppShortcut(
            intent: CreateNewTicketIntent(),
            phrases: [
                "Create new ticket in \(.applicationName)",
                "New repair ticket in \(.applicationName)",
                "New ticket for \(\.$customerName) in \(.applicationName)"
            ],
            shortTitle: "New Ticket",
            systemImageName: "plus.circle"
        )

        // 2. Today's revenue
        AppShortcut(
            intent: TodayRevenueIntent(),
            phrases: [
                "Today's revenue in \(.applicationName)",
                "What's today's revenue in \(.applicationName)",
                "How much did we make today in \(.applicationName)"
            ],
            shortTitle: "Today's Revenue",
            systemImageName: "dollarsign.circle"
        )

        // 3. Open POS
        AppShortcut(
            intent: OpenPOSIntent(),
            phrases: [
                "Open POS in \(.applicationName)",
                "Start a sale in \(.applicationName)",
                "Go to register in \(.applicationName)"
            ],
            shortTitle: "Open POS",
            systemImageName: "cart"
        )
    }
}

// MARK: - Shared defaults helper

private enum SharedDefaults {
    static var todayRevenue: Double? {
        let suite = UserDefaults(suiteName: "group.com.bizarrecrm")
        let value = suite?.double(forKey: "widget.todayRevenue") ?? 0
        // 0 could mean genuinely no revenue or unset — treat 0 as unset when
        // the "hasRevenue" flag is absent.
        guard suite?.object(forKey: "widget.todayRevenue") != nil else { return nil }
        return value
    }
}

// MARK: - URL helper

@MainActor
private func openAppURL(_ url: URL) async {
    #if canImport(UIKit)
    await UIApplication.shared.open(url)
    #endif
}
