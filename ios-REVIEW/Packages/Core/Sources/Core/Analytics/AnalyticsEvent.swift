import Foundation

// §71 Privacy-first Analytics Event List (iOS)

// MARK: - Entity kind

/// Identifies the CRM entity type involved in a navigation or action event.
/// Only structural identifiers — no PII.
public enum EntityKind: String, Sendable, Hashable, CaseIterable {
    case ticket
    case customer
    case invoice
    case estimate
    case inventoryItem
    case appointment
    case sale
}

// MARK: - AnalyticsEvent (strongly-typed, closed set)

/// Closed set of privacy-safe analytics events emitted by BizarreCRM iOS.
///
/// Design rules:
/// - Every case carries **only non-PII structural data** (IDs, counts, booleans,
///   enums). Raw user text, names, emails, and phone numbers are **forbidden** as
///   associated values.
/// - IDs are opaque server-assigned identifiers — safe to transmit because they
///   cannot be reverse-engineered to a person without the server database.
/// - `AnalyticsPIIGuard` enforces these constraints at compile time via phantom types.
///
/// Named `PrivacyEvent` (not `AnalyticsEvent`) to avoid collision with the
/// existing flat `AnalyticsEvent` catalog in `Core/Telemetry/AnalyticsEventCatalog.swift`.
///
/// Usage:
/// ```swift
/// AnalyticsDispatcher.log(.openedDetail(entity: .ticket, id: "t_123"))
/// AnalyticsDispatcher.log(.saleCompleted(totalCents: 4999, itemCount: 3))
/// ```
public enum PrivacyEvent: Sendable {

    // MARK: Navigation

    /// A top-level screen / tab was tapped or opened programmatically.
    case tappedView(screen: String)

    /// A detail view for a CRM entity was opened.
    case openedDetail(entity: EntityKind, id: String)

    // MARK: Forms

    /// A form was submitted successfully (no field content — only the form name).
    case formSubmitted(formName: String, fieldCount: Int)

    /// A form was discarded by the user.
    case formDiscarded(formName: String)

    // MARK: Domain actions

    /// A sale (POS checkout) was completed.
    case saleCompleted(totalCents: Int, itemCount: Int)

    /// A refund was issued. Amount is in minor currency units (cents).
    case refundIssued(amountCents: Int)

    /// A ticket was created.
    case ticketCreated(priority: String)

    /// A ticket's status changed.
    case ticketStatusChanged(fromStatus: String, toStatus: String)

    /// A customer record was created.
    case customerCreated

    /// An inventory item quantity was adjusted.
    case inventoryAdjusted(itemId: String, delta: Int)

    /// An invoice was sent.
    case invoiceSent(invoiceId: String)

    /// A payment was recorded against an invoice or sale.
    case paymentRecorded(method: String, amountCents: Int)

    // MARK: Session / app lifecycle

    /// The app was launched.
    case appLaunched(coldStart: Bool)

    /// The app entered the background.
    case appBackgrounded

    /// A user session ended (either sign-out or expiry).
    case sessionEnded(durationSeconds: Int)

    // MARK: Feature engagement

    /// The user opened the command palette.
    case commandPaletteOpened

    /// A command was executed from the palette.
    case commandExecuted(commandId: String)

    /// A feature was used for the first time on this device.
    case featureFirstUse(featureId: String)

    // MARK: Search

    /// A search was performed. No query text is logged — only result count.
    case searchPerformed(resultCount: Int)

    // MARK: Errors

    /// A user-visible error alert was shown.
    case errorPresented(domain: String, code: Int)

    // MARK: - Derived metadata

    /// Machine-readable event name in `snake_case` dot-notation.
    public var name: String {
        switch self {
        case .tappedView:            return "ui.tapped_view"
        case .openedDetail:          return "ui.opened_detail"
        case .formSubmitted:         return "ui.form.submitted"
        case .formDiscarded:         return "ui.form.discarded"
        case .saleCompleted:         return "pos.sale.completed"
        case .refundIssued:          return "pos.refund.issued"
        case .ticketCreated:         return "ticket.created"
        case .ticketStatusChanged:   return "ticket.status.changed"
        case .customerCreated:       return "customer.created"
        case .inventoryAdjusted:     return "inventory.adjusted"
        case .invoiceSent:           return "invoice.sent"
        case .paymentRecorded:       return "payment.recorded"
        case .appLaunched:           return "app.launched"
        case .appBackgrounded:       return "app.backgrounded"
        case .sessionEnded:          return "session.ended"
        case .commandPaletteOpened:  return "command_palette.opened"
        case .commandExecuted:       return "command_palette.executed"
        case .featureFirstUse:       return "feature.first_use"
        case .searchPerformed:       return "search.performed"
        case .errorPresented:        return "error.presented"
        }
    }

    /// Maps to the corresponding `TelemetryCategory` for routing.
    public var telemetryCategory: TelemetryCategory {
        switch self {
        case .tappedView, .openedDetail,
             .commandPaletteOpened, .commandExecuted:
            return .navigation

        case .formSubmitted, .formDiscarded,
             .ticketCreated, .ticketStatusChanged,
             .customerCreated, .inventoryAdjusted,
             .invoiceSent, .saleCompleted, .refundIssued,
             .paymentRecorded, .featureFirstUse,
             .searchPerformed:
            return .domain

        case .appLaunched, .appBackgrounded, .sessionEnded:
            return .appLifecycle

        case .errorPresented:
            return .error
        }
    }

    /// Extracts the event's payload as a flat `[String: String]` dictionary.
    ///
    /// All values are structural (IDs, counts, flags) — no raw user content.
    /// Callers should pass this through `TelemetryRedactor.scrub(_:)` before
    /// embedding in a `TelemetryRecord` (done automatically by `AnalyticsEventMapper`).
    public var properties: [String: String] {
        switch self {
        case let .tappedView(screen):
            return ["screen": screen]

        case let .openedDetail(entity, id):
            return ["entity": entity.rawValue, "id": id]

        case let .formSubmitted(formName, fieldCount):
            return ["form": formName, "field_count": String(fieldCount)]

        case let .formDiscarded(formName):
            return ["form": formName]

        case let .saleCompleted(totalCents, itemCount):
            return ["total_cents": String(totalCents), "item_count": String(itemCount)]

        case let .refundIssued(amountCents):
            return ["amount_cents": String(amountCents)]

        case let .ticketCreated(priority):
            return ["priority": priority]

        case let .ticketStatusChanged(from, to):
            return ["from_status": from, "to_status": to]

        case .customerCreated:
            return [:]

        case let .inventoryAdjusted(itemId, delta):
            return ["item_id": itemId, "delta": String(delta)]

        case let .invoiceSent(invoiceId):
            return ["invoice_id": invoiceId]

        case let .paymentRecorded(method, amountCents):
            return ["method": method, "amount_cents": String(amountCents)]

        case let .appLaunched(coldStart):
            return ["cold_start": coldStart ? "true" : "false"]

        case .appBackgrounded:
            return [:]

        case let .sessionEnded(durationSeconds):
            return ["duration_seconds": String(durationSeconds)]

        case .commandPaletteOpened:
            return [:]

        case let .commandExecuted(commandId):
            return ["command_id": commandId]

        case let .featureFirstUse(featureId):
            return ["feature_id": featureId]

        case let .searchPerformed(resultCount):
            return ["result_count": String(resultCount)]

        case let .errorPresented(domain, code):
            return ["error_domain": domain, "error_code": String(code)]
        }
    }
}
