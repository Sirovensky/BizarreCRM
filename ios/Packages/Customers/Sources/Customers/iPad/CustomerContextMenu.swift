#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - CustomerContextMenu

/// Context menu actions for a `CustomerSummary` row in the three-column view.
///
/// Actions:
/// - **Open** — selects the customer in the split view
/// - **Copy Phone** — copies the best available phone number to the pasteboard
/// - **Copy Email** — copies email address to the pasteboard
/// - **New Ticket** — placeholder deep-link (Phase 4)
/// - **New Invoice** — placeholder deep-link (Phase 4)
/// - **Merge** — placeholder merge flow (Phase 4)
///
/// Each action carries an `.accessibilityLabel` so VoiceOver reads the
/// customer name alongside the action description.
public struct CustomerContextMenu: View {
    let customer: CustomerSummary
    let onOpen: () -> Void
    let api: APIClient

    public init(
        customer: CustomerSummary,
        onOpen: @escaping () -> Void,
        api: APIClient
    ) {
        self.customer = customer
        self.onOpen = onOpen
        self.api = api
    }

    public var body: some View {
        // Open
        Button {
            onOpen()
        } label: {
            Label("Open", systemImage: "person.circle")
        }
        .accessibilityLabel("Open \(customer.displayName)")

        Divider()

        // Copy Phone
        if let phone = bestPhone {
            Button {
                UIPasteboard.general.string = phone
            } label: {
                Label("Copy Phone", systemImage: "phone.fill")
            }
            .accessibilityLabel("Copy phone number for \(customer.displayName)")
        }

        // Copy Email
        if let email = customer.email, !email.isEmpty {
            Button {
                UIPasteboard.general.string = email
            } label: {
                Label("Copy Email", systemImage: "envelope.fill")
            }
            .accessibilityLabel("Copy email for \(customer.displayName)")
        }

        Divider()

        // New Ticket
        Button {
            // TODO: deep-link to TicketCreateView pre-filled with customer — Phase 4
        } label: {
            Label("New Ticket", systemImage: "ticket")
        }
        .accessibilityLabel("Create new ticket for \(customer.displayName)")

        // New Invoice
        Button {
            // TODO: deep-link to InvoiceCreateView pre-filled with customer — Phase 4
        } label: {
            Label("New Invoice", systemImage: "doc.text.fill")
        }
        .accessibilityLabel("Create new invoice for \(customer.displayName)")

        Divider()

        // Merge
        Button {
            // TODO: present CustomerMergeView — Phase 4
        } label: {
            Label("Merge\u{2026}", systemImage: "person.2.badge.gearshape")
        }
        .accessibilityLabel("Merge \(customer.displayName) with another customer")
    }

    // MARK: - Private

    private var bestPhone: String? {
        if let m = customer.mobile, !m.isEmpty { return m }
        if let p = customer.phone, !p.isEmpty { return p }
        return nil
    }
}
#endif
