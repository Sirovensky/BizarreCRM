import Foundation

// §26 A11y retrofit — list row accessibility label helpers

/// Pure, stateless helpers that build VoiceOver accessibility labels for list rows.
///
/// No UI imports — safe for non-UIKit targets, unit tests, and SwiftUI previews.
/// All output ends with a period. Labels are capped at 500 chars to avoid
/// excessively long VoiceOver announcements.
///
/// Swift 6: enum is implicitly Sendable (no mutable state).
public enum RowAccessibilityFormatter: Sendable {

    // MARK: — Hints (static strings)

    public static let ticketRowHint    = "Tap to open ticket details."
    public static let customerRowHint  = "Tap to open customer details."
    public static let inventoryRowHint = "Tap for item details."
    public static let invoiceRowHint   = "Tap to view invoice."

    // MARK: — Ticket row

    /// VoiceOver label for a service-ticket list row.
    ///
    /// Example: "Ticket TKT-001, customer Jane Doe, device iPhone 14, status Diagnosing, due in 2 days."
    ///
    /// - Parameters:
    ///   - id:       Human-readable display id (e.g. "TKT-001"). Never pass a raw Int64.
    ///   - customer: Customer display name; omitted when empty.
    ///   - device:   Device name; omitted when empty.
    ///   - status:   Status display name.
    ///   - dueAt:    Due date; formatted relative when non-nil, omitted when nil.
    public static func ticketRow(
        id: String,
        customer: String,
        device: String,
        status: String,
        dueAt: Date?
    ) -> String {
        var parts: [String] = ["Ticket \(id)"]
        if !customer.isEmpty { parts.append("customer \(customer)") }
        if !device.isEmpty   { parts.append("device \(device)") }
        if !status.isEmpty   { parts.append("status \(status)") }
        if let due = dueAt   { parts.append("due \(relativeDate(due))") }
        return finalize(parts)
    }

    // MARK: — Customer row

    /// VoiceOver label for a customer list row.
    ///
    /// Example: "Jane Doe, phone 555-1212, 3 open tickets, LTV $1,250.00, last visit 2 weeks ago."
    ///
    /// - Parameters:
    ///   - name:            Customer display name.
    ///   - phone:           Phone number; omitted when nil/empty.
    ///   - openTicketCount: Open ticket count; omitted when 0.
    ///   - ltvCents:        Lifetime value in cents; formatted as currency when non-nil.
    ///   - lastVisitAt:     Last visit date formatted relative; omitted when nil.
    public static func customerRow(
        name: String,
        phone: String?,
        openTicketCount: Int,
        ltvCents: Int?,
        lastVisitAt: Date?
    ) -> String {
        var parts: [String] = []
        if !name.isEmpty { parts.append(name) }
        if let ph = phone, !ph.isEmpty { parts.append("phone \(ph)") }
        if openTicketCount > 0 {
            let unit = openTicketCount == 1 ? "open ticket" : "open tickets"
            parts.append("\(openTicketCount) \(unit)")
        }
        if let ltv = ltvCents { parts.append("LTV \(currencyFormatted(ltv))") }
        if let visit = lastVisitAt { parts.append("last visit \(relativeDate(visit))") }
        return finalize(parts)
    }

    // MARK: — Inventory row

    /// VoiceOver label for an inventory item list row.
    ///
    /// Example: "SKU ABC-123, iPhone 14 battery, 3 in stock, retail $89.99, — low stock warning."
    ///
    /// - Parameters:
    ///   - sku:         SKU string; omitted when nil/empty.
    ///   - name:        Item display name.
    ///   - stock:       Current stock quantity.
    ///   - retailCents: Retail price in cents; formatted as currency when non-nil.
    ///   - isLowStock:  Appends "— low stock warning" when true.
    public static func inventoryRow(
        sku: String?,
        name: String,
        stock: Int,
        retailCents: Int?,
        isLowStock: Bool
    ) -> String {
        var parts: [String] = []
        if let s = sku, !s.isEmpty { parts.append("SKU \(s)") }
        if !name.isEmpty { parts.append(name) }
        if stock == 0 {
            parts.append("out of stock")
        } else {
            parts.append("\(stock) in stock")
        }
        if let cents = retailCents { parts.append("retail \(currencyFormatted(cents))") }
        if isLowStock              { parts.append("— low stock warning") }
        return finalize(parts)
    }

    // MARK: — Invoice row

    /// VoiceOver label for an invoice list row.
    ///
    /// Example: "Invoice INV-001, customer Jane Doe, $250.00, status Paid, issued Mar 5, 2024."
    ///
    /// - Parameters:
    ///   - number:     Human-readable invoice number (e.g. "INV-001"). Never a raw Int64.
    ///   - customer:   Customer display name.
    ///   - totalCents: Invoice total in cents; formatted as currency.
    ///   - status:     Status string; auto-capitalized.
    ///   - issuedAt:   Issue date formatted in medium style (e.g. "Mar 5, 2024").
    public static func invoiceRow(
        number: String,
        customer: String,
        totalCents: Int,
        status: String,
        issuedAt: Date
    ) -> String {
        var parts: [String] = ["Invoice \(number)"]
        if !customer.isEmpty { parts.append("customer \(customer)") }
        parts.append(currencyFormatted(totalCents))
        if !status.isEmpty { parts.append("status \(capitalized(status))") }
        parts.append("issued \(mediumDate(issuedAt))")
        return finalize(parts)
    }

    // MARK: — Private helpers

    /// Joins parts with ", ", appends ".", and truncates to 500 chars.
    private static func finalize(_ parts: [String]) -> String {
        let raw = parts.joined(separator: ", ") + "."
        guard raw.count > 500 else { return raw }
        return String(raw.prefix(497)) + "…"
    }

    /// Capitalizes only the first letter, preserving the rest.
    private static func capitalized(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// Formats a date relative to now.
    /// Uses `RelativeDateTimeFormatter` which produces "in 2 days", "2 weeks ago", etc.
    private static func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        f.locale = .current
        return f.localizedString(for: date, relativeTo: Date())
    }

    /// Formats a date in medium style: "Mar 5, 2024".
    private static func mediumDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = .current
        return f.string(from: date)
    }

    /// Formats cents as localized currency.
    /// Uses `Locale.current`; tenant locale to be wired in Phase 11.
    private static func currencyFormatted(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        let value = Double(cents) / 100.0
        return f.string(from: NSNumber(value: value)) ?? "$\(String(format: "%.2f", value))"
    }
}
