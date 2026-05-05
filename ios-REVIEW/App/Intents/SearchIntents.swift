import AppIntents
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §24.4 LookupTicketIntent — "Find ticket {number}"; returns structured snippet.

/// Siri / Shortcuts intent to look up a ticket by number.
///
/// Usage: "Find ticket 1234 in Bizarre CRM"
@available(iOS 16.0, *)
struct AppShellLookupTicketIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Ticket"
    static let description: IntentDescription = IntentDescription(
        "Look up a ticket by ID or order number in Bizarre CRM.",
        categoryName: "Tickets"
    )
    static let isDiscoverable: Bool = true

    @Parameter(title: "Ticket number", description: "The ticket ID or order number")
    var ticketNumber: String

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let deepLink = URL(string: "bizarrecrm://search?q=\(ticketNumber.urlEncoded)&scope=tickets")!
        await openURL(deepLink)
        return .result(
            dialog: "Opening search for ticket \(ticketNumber) in Bizarre CRM.",
            view: TicketLookupSnippet(query: ticketNumber)
        )
    }
}

// MARK: - §24.4 SendSMSIntent — "Text {customer} {message}".

/// Siri / Shortcuts intent to compose an SMS to a customer.
///
/// Usage: "Text John Smith a message in Bizarre CRM"
@available(iOS 16.0, *)
struct SendSMSToCustomerIntent: AppIntent {
    static let title: LocalizedStringResource = "Send SMS to Customer"
    static let description: IntentDescription = IntentDescription(
        "Open an SMS compose window to a specific customer in Bizarre CRM.",
        categoryName: "Communications"
    )
    static let isDiscoverable: Bool = true

    @Parameter(title: "Customer name or phone", description: "Customer name or phone number")
    var customerQuery: String

    @Parameter(title: "Message", description: "Message to pre-fill (optional)")
    var messageBody: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var path = "bizarrecrm://sms/new?customer=\(customerQuery.urlEncoded)"
        if let body = messageBody {
            path += "&body=\(body.urlEncoded)"
        }
        if let url = URL(string: path) {
            await openURL(url)
        }
        return .result(dialog: "Opening SMS to \(customerQuery) in Bizarre CRM.")
    }
}

// MARK: - §24.4 RecordExpenseIntent — "Log $42 lunch expense".

/// Siri / Shortcuts intent to log a quick expense.
///
/// Usage: "Log a $42 lunch expense in Bizarre CRM"
@available(iOS 16.0, *)
struct RecordExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Record Expense"
    static let description: IntentDescription = IntentDescription(
        "Quickly log an expense in Bizarre CRM.",
        categoryName: "Expenses"
    )
    static let isDiscoverable: Bool = true

    @Parameter(title: "Amount", description: "Expense amount in dollars")
    var amount: Double

    @Parameter(title: "Description", description: "What the expense was for")
    var expenseDescription: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var path = "bizarrecrm://expenses/new?amount=\(amount)"
        if let desc = expenseDescription {
            path += "&description=\(desc.urlEncoded)"
        }
        if let url = URL(string: path) {
            await openURL(url)
        }
        let desc = expenseDescription ?? "expense"
        return .result(dialog: "Opening expense form for $\(String(format: "%.2f", amount)) \(desc).")
    }
}

// MARK: - §24.5 App Shortcuts — system suggestions & Siri suggestions

/// Extends the main BizarreCRMShortcutsProvider (from the existing §24 phase-6 file)
/// with the new intents.
@available(iOS 16.0, *)
enum BizarreCRMSearchShortcuts {
    @AppShortcutsBuilder
    static var shortcuts: [AppShortcut] {
        AppShortcut(
            intent: AppShellLookupTicketIntent(),
            phrases: [
                "Find ticket \(\.$ticketNumber) in \(.applicationName)",
                "Look up \(\.$ticketNumber) in \(.applicationName)",
                "Search ticket \(\.$ticketNumber) in \(.applicationName)"
            ],
            shortTitle: "Find Ticket",
            systemImageName: "ticket"
        )

        AppShortcut(
            intent: SendSMSToCustomerIntent(),
            phrases: [
                "Text \(\.$customerQuery) in \(.applicationName)",
                "Send SMS to \(\.$customerQuery) in \(.applicationName)",
                "Message \(\.$customerQuery) in \(.applicationName)"
            ],
            shortTitle: "Send SMS",
            systemImageName: "message"
        )

        AppShortcut(
            intent: RecordExpenseIntent(),
            phrases: [
                "Log expense in \(.applicationName)",
                "Record expense in \(.applicationName)",
                "Add expense in \(.applicationName)"
            ],
            shortTitle: "Log Expense",
            systemImageName: "dollarsign.circle"
        )
    }
}

// MARK: - Snippet view

private struct TicketLookupSnippet: View {
    let query: String

    var body: some View {
        HStack {
            Image(systemName: "ticket")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Searching for ticket \"\(query)\"…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
    }
}

// MARK: - Helpers

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}

@MainActor
private func openURL(_ url: URL) async {
    #if canImport(UIKit)
    await UIApplication.shared.open(url)
    #endif
}
