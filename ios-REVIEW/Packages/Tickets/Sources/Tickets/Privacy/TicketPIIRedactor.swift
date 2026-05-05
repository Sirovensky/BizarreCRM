import Foundation
import Core

// §28 Security & Privacy — PII redactor wrapper for the Tickets domain
//
// Ticket records aggregate multiple PII categories:
//   - Customer name + phone + email (contact info)
//   - Device serial / IMEI (device identifiers)
//   - Physical address (drop-off / pick-up)
//   - Internal technician notes (may contain free-text PII)
//
// This file centralises the redaction policy so every logging / telemetry
// call site in Tickets can use a single entry point rather than constructing
// ad-hoc category lists each time.

// MARK: - TicketPIIRedactor

/// Domain-specific PII redactor for the Tickets package.
///
/// Wraps ``SensitiveFieldRedactor`` with ticket-appropriate category defaults
/// so call sites do not have to enumerate categories manually.
///
/// ## Usage
/// ```swift
/// // Redact all PII that commonly appears in ticket text:
/// let safe = TicketPIIRedactor.redactTicketText(note)
///
/// // Redact only contact fields (e.g. for a "customer summary" log line):
/// let safe = TicketPIIRedactor.redactContactInfo(description)
///
/// // Redact a single structured field:
/// let safe = TicketPIIRedactor.redact(imei, as: .deviceID)
/// ```
public enum TicketPIIRedactor {

    // MARK: - Category sets

    /// Categories that commonly appear in free-text ticket notes or descriptions.
    ///
    /// Includes contact info, device identifiers, and addresses but excludes
    /// payment-card data (tickets never contain PANs).
    public static let ticketTextCategories: [DataHandlingCategory] = [
        .name,
        .email,
        .phone,
        .address,
        .deviceID,
    ]

    /// Categories present in a customer contact summary (name + email + phone).
    public static let contactInfoCategories: [DataHandlingCategory] = [
        .name,
        .email,
        .phone,
    ]

    /// Categories present in a device entry (serial, IMEI, model).
    public static let deviceCategories: [DataHandlingCategory] = [
        .deviceID,
    ]

    // MARK: - Public API

    /// Redact all PII categories commonly found in ticket free-text fields
    /// (notes, descriptions, internal memos).
    ///
    /// This is the right call for any string that might contain customer-typed
    /// or technician-typed content before sending it to logs or telemetry.
    ///
    /// - Parameter text: Raw ticket text.
    /// - Returns: Text with matched PII replaced by placeholder tokens.
    public static func redactTicketText(_ text: String) -> String {
        SensitiveFieldRedactor.redact(text, categories: ticketTextCategories)
    }

    /// Redact contact-specific PII (name, email, phone) from a string.
    ///
    /// Use for summary log lines that include the customer's contact details.
    ///
    /// - Parameter text: Raw contact summary string.
    /// - Returns: Redacted string.
    public static func redactContactInfo(_ text: String) -> String {
        SensitiveFieldRedactor.redact(text, categories: contactInfoCategories)
    }

    /// Redact device-identifier PII (serial number, IMEI, UUID) from a string.
    ///
    /// - Parameter text: Raw device info string.
    /// - Returns: Redacted string.
    public static func redactDeviceInfo(_ text: String) -> String {
        SensitiveFieldRedactor.redact(text, categories: deviceCategories)
    }

    /// Redact a single field using an explicit category.
    ///
    /// Useful when you know exactly what category a value belongs to.
    ///
    /// ```swift
    /// AppLog.tickets.debug("IMEI: \(TicketPIIRedactor.redact(imei, as: .deviceID), privacy: .public)")
    /// ```
    ///
    /// - Parameters:
    ///   - value:    The raw field value.
    ///   - category: The ``DataHandlingCategory`` that best describes the value.
    /// - Returns: Redacted string.
    public static func redact(_ value: String, as category: DataHandlingCategory) -> String {
        SensitiveFieldRedactor.redact(value, categories: [category])
    }

    /// Redact all known PII from a string (nuclear option).
    ///
    /// Use when the content origin is unknown or the string may contain
    /// mixed PII categories.
    ///
    /// - Parameter text: Raw string.
    /// - Returns: String with all PII patterns replaced.
    public static func redactAll(_ text: String) -> String {
        SensitiveFieldRedactor.redactAll(text)
    }
}
