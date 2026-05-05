import Foundation
#if canImport(UIKit)
import UIKit
#endif

// §28.9 Pasteboard hygiene — Paste-blind utility for the Tickets domain
//
// "Paste-blind" means the app never reads the pasteboard on behalf of the
// user without an explicit user gesture.  This helper:
//
//   1. Provides a single entry point for *all* pasteboard writes in the Tickets
//      domain, enforcing a uniform expiry policy on sensitive content.
//   2. Wraps the iOS 16+ `UIPasteboard` expiration API and documents the
//      chosen TTL for each content type.
//   3. Exposes a `pasteboardAuditString` helper that logs a redacted summary
//      of any write so the audit trail shows what was copied without capturing
//      the raw value.
//
// NOTE: Reading from the pasteboard is intentionally NOT exposed here.
// Ticket UI uses SwiftUI `PasteButton` (iOS 16+) for all user-initiated pastes
// so iOS doesn't show the "X accessed your pasteboard" banner.

// MARK: - TicketPasteBlind

/// Centralised, auditable pasteboard-write utility for the Tickets package.
///
/// All clipboard copies from Ticket screens **must** go through this type
/// rather than calling `UIPasteboard.general` directly. This ensures:
/// - Sensitive copies (email, phone) expire after 120 seconds.
/// - Non-sensitive copies (ticket ID, SKU) are set without expiration.
/// - Every write is accompanied by a brief audit description for logging.
///
/// ## Expiry policy
/// | Content type      | TTL       | Rationale                        |
/// |-------------------|-----------|----------------------------------|
/// | Email address     | 120 s     | PII; clears before session idle  |
/// | Phone number      | 120 s     | PII                              |
/// | Device serial     | 120 s     | Sensitive device identifier      |
/// | Ticket ID         | none      | Non-sensitive operational ref    |
/// | Invoice number    | none      | Non-sensitive operational ref    |
/// | SKU / barcode     | none      | Non-sensitive product ref        |
///
/// ## Usage
/// ```swift
/// TicketPasteBlind.copyEmail(customer.email) { entry in
///     AppLog.tickets.debug("Clipboard write: \(entry, privacy: .public)")
/// }
/// ```
public enum TicketPasteBlind {

    // MARK: - Expiry durations

    /// Seconds before a sensitive clipboard item is cleared automatically.
    /// iOS clears the item at or after this interval; exact timing is
    /// platform-controlled.
    public static let sensitiveExpirySeconds: TimeInterval = 120

    // MARK: - Sensitive copies (expire after `sensitiveExpirySeconds`)

    /// Copy a customer email address to the pasteboard with a 120-second TTL.
    ///
    /// - Parameters:
    ///   - email:    The raw email string to copy.
    ///   - onCopy:   Optional closure called with an audit description after the
    ///               write. The description is already redacted and safe to log.
    public static func copyEmail(
        _ email: String,
        onCopy: ((String) -> Void)? = nil
    ) {
        writeSensitive(email, auditLabel: "email")
        onCopy?("Ticket clipboard write: <email> (expires \(Int(sensitiveExpirySeconds))s)")
    }

    /// Copy a customer phone number to the pasteboard with a 120-second TTL.
    public static func copyPhone(
        _ phone: String,
        onCopy: ((String) -> Void)? = nil
    ) {
        writeSensitive(phone, auditLabel: "phone")
        onCopy?("Ticket clipboard write: <phone> (expires \(Int(sensitiveExpirySeconds))s)")
    }

    /// Copy a device serial number or IMEI to the pasteboard with a 120-second TTL.
    public static func copyDeviceSerial(
        _ serial: String,
        onCopy: ((String) -> Void)? = nil
    ) {
        writeSensitive(serial, auditLabel: "device-serial")
        onCopy?("Ticket clipboard write: <device-serial> (expires \(Int(sensitiveExpirySeconds))s)")
    }

    // MARK: - Non-sensitive copies (no expiry)

    /// Copy a ticket ID (e.g. "#4821") to the pasteboard without expiry.
    public static func copyTicketID(
        _ ticketID: String,
        onCopy: ((String) -> Void)? = nil
    ) {
        writeNonSensitive(ticketID)
        onCopy?("Ticket clipboard write: ticket-id \(ticketID)")
    }

    /// Copy an invoice number to the pasteboard without expiry.
    public static func copyInvoiceNumber(
        _ invoiceNumber: String,
        onCopy: ((String) -> Void)? = nil
    ) {
        writeNonSensitive(invoiceNumber)
        onCopy?("Ticket clipboard write: invoice-number \(invoiceNumber)")
    }

    /// Copy a SKU or barcode string to the pasteboard without expiry.
    public static func copySKU(
        _ sku: String,
        onCopy: ((String) -> Void)? = nil
    ) {
        writeNonSensitive(sku)
        onCopy?("Ticket clipboard write: sku \(sku)")
    }

    // MARK: - Private helpers

    /// Write a sensitive string with an automatic expiration.
    private static func writeSensitive(_ value: String, auditLabel: String) {
        #if canImport(UIKit)
        let expiry = Date().addingTimeInterval(sensitiveExpirySeconds)
        UIPasteboard.general.setItems(
            [[UIPasteboard.typeAutomatic: value]],
            options: [.expirationDate: expiry]
        )
        #endif
    }

    /// Write a non-sensitive string with no expiration.
    private static func writeNonSensitive(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #endif
    }
}
