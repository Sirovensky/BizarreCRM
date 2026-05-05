import Foundation

// MARK: - §70 Per-event push copy matrix
//
// Tone: short, actionable, no emoji in title; body includes identifier so push
// list stays scannable.  Localization keys defined here; fallback to English
// until §27 locale pass adds translations.

/// Structured push notification copy for a single event.
public struct NotificationCopy: Sendable, Equatable {
    /// Short title line — shown bold in notification centre.
    public let title: String
    /// Body text — shown below title; includes identifiers for scannability.
    public let body: String
    /// Category ID to attach (determines action buttons available).
    public let categoryID: String?

    public init(title: String, body: String, categoryID: String? = nil) {
        self.title = title
        self.body = body
        self.categoryID = categoryID
    }
}

// MARK: - NotificationCopyProvider

/// Returns canonical push notification copy for every §70 event type.
///
/// Context parameters let callers inject entity-specific details
/// (ticket ID, customer name, amount, etc.) without building copy ad-hoc.
///
/// A11y: VoiceOver reads `title + body` from the notification banner —
/// keep both short and self-explanatory.
///
/// Localization: string literals are English source keys.  When §27 lands,
/// wrap in `NSLocalizedString` and add the same key to `Localizable.strings`.
public enum NotificationCopyProvider {

    // MARK: - Public API

    /// Return the canonical copy for the given event.
    ///
    /// - Parameters:
    ///   - event: The `NotificationEvent` being delivered.
    ///   - context: Optional dict with entity-specific substitution values.
    ///     Supported keys: `ticketId`, `customerId`, `customerName`,
    ///     `invoiceId`, `amount`, `status`, `device`, `phone`, `employeeName`,
    ///     `messagePreview`, `sku`, `count`, `serviceName`, `appointmentTime`.
    public static func copy(
        for event: NotificationEvent,
        context: [String: String] = [:]
    ) -> NotificationCopy {
        let t = Substituter(context)
        switch event {

        // MARK: Tickets
        case .ticketAssigned:
            return NotificationCopy(
                title: "Ticket assigned to you",
                body: t.ifPresent("ticketId") { "Ticket #\($0)\(t.ifPresent("device") { " – \($0)" } ?? "")" }
                    ?? "Open the app to view your new ticket.",
                categoryID: NotificationCategoryID.ticketUpdate.rawValue
            )

        case .ticketStatusChangeMine:
            return NotificationCopy(
                title: "Your ticket was updated",
                body: t.ifPresent("ticketId") { "Ticket #\($0) → \(t.context["status"] ?? "new status")" }
                    ?? "A ticket assigned to you changed status.",
                categoryID: NotificationCategoryID.ticketUpdate.rawValue
            )

        case .ticketStatusChangeAny:
            return NotificationCopy(
                title: "Ticket status changed",
                body: t.ifPresent("ticketId") { "Ticket #\($0) is now \(t.context["status"] ?? "updated")" }
                    ?? "A ticket changed status.",
                categoryID: NotificationCategoryID.ticketUpdate.rawValue
            )

        // MARK: SMS / Communications
        case .smsInbound:
            return NotificationCopy(
                title: t.ifPresent("customerName") { "SMS from \($0)" } ?? "New SMS",
                body: t.context["messagePreview"].flatMap { p in p.isEmpty ? nil : p }
                    ?? t.ifPresent("phone") { "From \($0)" }
                    ?? "Open the app to reply.",
                categoryID: NotificationCategoryID.smsReply.rawValue
            )

        case .smsDeliveryFailed:
            return NotificationCopy(
                title: "SMS delivery failed",
                body: t.ifPresent("phone") { "Message to \($0) was not delivered." }
                    ?? "An outbound SMS was not delivered.",
                categoryID: nil
            )

        // MARK: Customers
        case .newCustomerCreated:
            return NotificationCopy(
                title: "New customer",
                body: t.ifPresent("customerName") { "\($0) just signed up." }
                    ?? "A new customer was added.",
                categoryID: nil
            )

        // MARK: Invoices / Billing
        case .invoiceOverdue:
            return NotificationCopy(
                title: "Invoice overdue",
                body: t.ifPresent("invoiceId") {
                    "Invoice #\($0)\(t.amountSuffix) is past due."
                } ?? "An invoice is past due.",
                categoryID: nil
            )

        case .invoicePaid:
            return NotificationCopy(
                title: "Payment received",
                body: t.ifPresent("invoiceId") {
                    "Invoice #\($0)\(t.amountSuffix) marked paid\(t.customerSuffix)."
                } ?? "A payment was received.",
                categoryID: NotificationCategoryID.paymentReceived.rawValue
            )

        case .estimateApproved:
            return NotificationCopy(
                title: "Estimate approved",
                body: t.ifPresent("invoiceId") {
                    "Estimate #\($0)\(t.amountSuffix)\(t.customerSuffix) approved."
                } ?? "An estimate was approved.",
                categoryID: nil
            )

        case .estimateDeclined:
            return NotificationCopy(
                title: "Estimate declined",
                body: t.ifPresent("invoiceId") {
                    "Estimate #\($0)\(t.customerSuffix) was declined."
                } ?? "An estimate was declined.",
                categoryID: nil
            )

        // MARK: Appointments
        case .appointmentReminder24h:
            return NotificationCopy(
                title: "Appointment tomorrow",
                body: t.ifPresent("customerName") {
                    "\($0)\(t.ifPresent("appointmentTime") { " at \($0)" } ?? "") tomorrow."
                } ?? "You have an appointment tomorrow.",
                categoryID: NotificationCategoryID.appointmentReminder.rawValue
            )

        case .appointmentReminder1h:
            return NotificationCopy(
                title: "Appointment in 1 hour",
                body: t.ifPresent("customerName") {
                    "\($0)\(t.ifPresent("appointmentTime") { " at \($0)" } ?? "") in 1 hour."
                } ?? "You have an appointment in 1 hour.",
                categoryID: NotificationCategoryID.appointmentReminder.rawValue
            )

        case .appointmentCanceled:
            return NotificationCopy(
                title: "Appointment canceled",
                body: t.ifPresent("customerName") {
                    "\($0)'s appointment\(t.ifPresent("appointmentTime") { " at \($0)" } ?? "") was canceled."
                } ?? "An appointment was canceled.",
                categoryID: nil
            )

        // MARK: Collaboration
        case .mentionInNote:
            return NotificationCopy(
                title: t.ifPresent("employeeName") { "\($0) mentioned you" } ?? "You were mentioned",
                body: t.context["messagePreview"] ?? "Open the app to see the note.",
                categoryID: NotificationCategoryID.mention.rawValue
            )

        // MARK: Inventory
        case .lowStock:
            return NotificationCopy(
                title: "Low stock",
                body: t.ifPresent("sku") {
                    "SKU \($0)\(t.ifPresent("count") { " — \($0) remaining" } ?? "") is running low."
                } ?? "An item is running low.",
                categoryID: NotificationCategoryID.lowStock.rawValue
            )

        case .outOfStock:
            return NotificationCopy(
                title: "Out of stock",
                body: t.ifPresent("sku") { "SKU \($0) is out of stock." }
                    ?? "An item is out of stock.",
                categoryID: NotificationCategoryID.lowStock.rawValue
            )

        // MARK: POS / Payments
        case .paymentDeclined:
            return NotificationCopy(
                title: "Payment declined",
                body: t.ifPresent("invoiceId") {
                    "Charge on invoice #\($0)\(t.amountSuffix)\(t.customerSuffix) was declined."
                } ?? "A payment was declined.",
                categoryID: NotificationCategoryID.paymentFailed.rawValue
            )

        case .refundProcessed:
            return NotificationCopy(
                title: "Refund processed",
                body: t.ifPresent("invoiceId") {
                    "Refund of\(t.amountSuffix) for invoice #\($0) completed."
                } ?? "A refund was processed.",
                categoryID: nil
            )

        case .cashRegisterShort:
            return NotificationCopy(
                title: "Cash register short",
                body: t.ifPresent("amount") { "Register is short by $\($0)." }
                    ?? "The cash register count does not match.",
                categoryID: nil
            )

        // MARK: Staff
        case .shiftStartedEnded:
            return NotificationCopy(
                title: t.ifPresent("employeeName") { "\($0)'s shift" } ?? "Shift update",
                body: t.ifPresent("status") { "Shift \($0)." } ?? "A shift was updated.",
                categoryID: nil
            )

        case .goalAchieved:
            return NotificationCopy(
                title: "Goal achieved",
                body: t.ifPresent("employeeName") { "\($0) hit a goal!" }
                    ?? "A team goal was achieved.",
                categoryID: nil
            )

        case .ptoApprovedDenied:
            return NotificationCopy(
                title: "PTO request decision",
                body: t.ifPresent("status") { "Your PTO request was \($0)." }
                    ?? "A PTO request decision was made.",
                categoryID: nil
            )

        // MARK: Marketing
        case .campaignSent:
            return NotificationCopy(
                title: "Campaign sent",
                body: t.ifPresent("count") { "Campaign delivered to \($0) recipients." }
                    ?? "A marketing campaign was sent.",
                categoryID: nil
            )

        case .npsDetractor:
            return NotificationCopy(
                title: "Low NPS score",
                body: t.ifPresent("customerName") { "\($0) gave a low satisfaction score." }
                    ?? "A customer gave a low NPS score.",
                categoryID: nil
            )

        // MARK: Admin / System
        case .setupWizardIncomplete:
            return NotificationCopy(
                title: "Setup incomplete",
                body: "Your shop setup is not finished. Tap to continue.",
                categoryID: nil
            )

        case .subscriptionRenewal:
            return NotificationCopy(
                title: "Subscription renewing",
                body: "Your BizarreCRM subscription renews soon.",
                categoryID: nil
            )

        case .integrationDisconnected:
            return NotificationCopy(
                title: "Integration disconnected",
                body: t.ifPresent("serviceName") { "\($0) integration was disconnected." }
                    ?? "An integration was disconnected.",
                categoryID: nil
            )

        case .backupFailed:
            return NotificationCopy(
                title: "Backup failed",
                body: "Last data backup did not complete. Open the app to retry.",
                categoryID: nil
            )

        case .securityEvent:
            return NotificationCopy(
                title: "Security alert",
                body: "A security event was detected on your account. Open the app immediately.",
                categoryID: nil
            )
        }
    }
}

// MARK: - Substituter (private helper)

/// Lightweight context interpolator to keep copy strings readable.
private struct Substituter {
    let context: [String: String]
    init(_ context: [String: String]) { self.context = context }

    func ifPresent<T>(_ key: String, transform: (String) -> T) -> T? {
        guard let value = context[key], !value.isEmpty else { return nil }
        return transform(value)
    }

    var amountSuffix: String {
        ifPresent("amount") { " ($\($0))" } ?? ""
    }

    var customerSuffix: String {
        ifPresent("customerName") { " from \($0)" } ?? ""
    }
}
