import Foundation

/// §16.7 — pure-function renderer for POS receipts. Produces two wire
/// formats from the same `Payload`:
///
/// - `text(_:)` — plain text, suitable as an SMS body and as the
///   pre-rendered `[String]` line slice fed to the §17.4 receipt printer.
/// - `html(_:)` — minimal semantic HTML, safe for dropping into an email
///   body. All user-controlled strings pass through `escapeHTML` so a
///   merchant name of `<script>` or a line titled `Burger & Fries` cannot
///   break the markup.
///
/// The renderer never touches system APIs (clock, locale, network) other
/// than `NumberFormatter.currency` + `DateFormatter`. That keeps tests
/// deterministic — inject a fixed `date` in the payload and the output is
/// byte-for-byte stable.
///
/// Money is cents everywhere. Currency formatting is delegated to a single
/// `NumberFormatter.currency` instance so plain text and HTML always agree
/// on the printable form (`$12.34`, not `12.34 USD`).
///
/// The renderer owns its own `Payload` type rather than reusing
/// `Hardware.ReceiptPayload` — the hardware type is intentionally shallow
/// (pre-rendered `[String]` lines for thermal printers). Splitting the
/// structs keeps the Pos receipt shape independent of the printer wire
/// format so either can evolve without churning the other.
public enum PosReceiptRenderer {

    /// Everything the renderer needs. Lives in Pos because the receipt
    /// shape is a POS concern — the Hardware printer adapter ingests the
    /// shallow `Hardware.ReceiptPayload` produced by `PosReceiptPrintPayloadBuilder`.
    public struct Payload: Equatable, Sendable {
        public struct Merchant: Equatable, Sendable {
            public let name: String
            public let address: String?
            public let phone: String?

            public init(name: String, address: String? = nil, phone: String? = nil) {
                self.name = name
                self.address = address
                self.phone = phone
            }
        }

        public struct Line: Equatable, Sendable {
            public let name: String
            public let sku: String?
            public let quantity: Int
            public let unitPriceCents: Int
            public let discountCents: Int
            public let lineTotalCents: Int

            public init(
                name: String,
                sku: String? = nil,
                quantity: Int,
                unitPriceCents: Int,
                discountCents: Int = 0,
                lineTotalCents: Int
            ) {
                self.name = name
                self.sku = sku
                self.quantity = max(1, quantity)
                self.unitPriceCents = max(0, unitPriceCents)
                self.discountCents = max(0, discountCents)
                self.lineTotalCents = lineTotalCents
            }
        }

        public struct Tender: Equatable, Sendable {
            public let method: String
            public let amountCents: Int
            public let last4: String?

            public init(method: String, amountCents: Int, last4: String? = nil) {
                self.method = method
                self.amountCents = amountCents
                self.last4 = last4
            }
        }

        public let merchant: Merchant
        public let date: Date
        public let customerName: String?
        public let orderNumber: String?
        public let lines: [Line]
        public let subtotalCents: Int
        public let discountCents: Int
        public let feesCents: Int
        public let taxCents: Int
        public let tipCents: Int
        public let totalCents: Int
        public let tenders: [Tender]
        public let currencyCode: String
        public let footer: String?

        public init(
            merchant: Merchant,
            date: Date,
            customerName: String? = nil,
            orderNumber: String? = nil,
            lines: [Line],
            subtotalCents: Int,
            discountCents: Int = 0,
            feesCents: Int = 0,
            taxCents: Int = 0,
            tipCents: Int = 0,
            totalCents: Int,
            tenders: [Tender] = [],
            currencyCode: String = "USD",
            footer: String? = nil
        ) {
            self.merchant = merchant
            self.date = date
            self.customerName = customerName
            self.orderNumber = orderNumber
            self.lines = lines
            self.subtotalCents = subtotalCents
            self.discountCents = discountCents
            self.feesCents = feesCents
            self.taxCents = taxCents
            self.tipCents = tipCents
            self.totalCents = totalCents
            self.tenders = tenders
            self.currencyCode = currencyCode
            self.footer = footer
        }
    }

    // MARK: - Public API

    /// Plain-text receipt body. Safe for SMS and for thermal-printer
    /// pre-rendered line lists. Uses ASCII characters only so no codepage
    /// surprises on receipt printers that default to CP437.
    public static func text(_ payload: Payload) -> String {
        var out: [String] = []
        out.append(payload.merchant.name)
        if let address = payload.merchant.address, !address.isEmpty {
            out.append(address)
        }
        if let phone = payload.merchant.phone, !phone.isEmpty {
            out.append(phone)
        }
        out.append(formatDate(payload.date))
        if let name = payload.customerName, !name.isEmpty {
            out.append("Customer: \(name)")
        }
        if let orderNumber = payload.orderNumber, !orderNumber.isEmpty {
            out.append("Order: \(orderNumber)")
        }
        out.append("")

        for line in payload.lines {
            let header = line.quantity > 1
                ? "\(line.quantity) x \(line.name)"
                : line.name
            out.append(header)
            let unitNote = line.quantity > 1
                ? " @ \(formatCents(line.unitPriceCents, code: payload.currencyCode))"
                : ""
            out.append("  \(formatCents(line.lineTotalCents, code: payload.currencyCode))\(unitNote)")
            if let sku = line.sku, !sku.isEmpty {
                out.append("  SKU: \(sku)")
            }
            if line.discountCents > 0 {
                out.append("  Line discount: -\(formatCents(line.discountCents, code: payload.currencyCode))")
            }
        }

        out.append("")
        out.append(row(label: "Subtotal", cents: payload.subtotalCents, code: payload.currencyCode))
        if payload.discountCents > 0 {
            out.append(row(label: "Discount", cents: -payload.discountCents, code: payload.currencyCode))
        }
        if payload.feesCents > 0 {
            out.append(row(label: "Fees", cents: payload.feesCents, code: payload.currencyCode))
        }
        if payload.taxCents > 0 {
            out.append(row(label: "Tax", cents: payload.taxCents, code: payload.currencyCode))
        }
        if payload.tipCents > 0 {
            out.append(row(label: "Tip", cents: payload.tipCents, code: payload.currencyCode))
        }
        out.append(row(label: "Total", cents: payload.totalCents, code: payload.currencyCode))

        if !payload.tenders.isEmpty {
            out.append("")
            for tender in payload.tenders {
                var label = tender.method
                if let last4 = tender.last4, !last4.isEmpty {
                    label += " •\(last4)"
                }
                out.append(row(label: label, cents: tender.amountCents, code: payload.currencyCode))
            }
        }

        if let footer = payload.footer, !footer.isEmpty {
            out.append("")
            out.append(footer)
        }

        return out.joined(separator: "\n")
    }

    /// Minimal-CSS HTML receipt. Inline styles only so email clients that
    /// strip `<style>` blocks (Gmail web, Outlook) still render correctly.
    /// Every string-typed payload field passes through `escapeHTML`.
    public static func html(_ payload: Payload) -> String {
        var out: [String] = []
        out.append("<!doctype html>")
        out.append("<html><body style=\"font-family:-apple-system,sans-serif;color:#111;max-width:420px;margin:0 auto;padding:16px;\">")
        out.append("<h2 style=\"margin:0 0 4px 0;font-size:18px;\">\(escapeHTML(payload.merchant.name))</h2>")
        if let address = payload.merchant.address, !address.isEmpty {
            out.append("<p style=\"margin:0;font-size:12px;color:#555;\">\(escapeHTML(address))</p>")
        }
        if let phone = payload.merchant.phone, !phone.isEmpty {
            out.append("<p style=\"margin:0;font-size:12px;color:#555;\">\(escapeHTML(phone))</p>")
        }
        out.append("<p style=\"margin:8px 0 12px 0;color:#555;font-size:13px;\">\(escapeHTML(formatDate(payload.date)))</p>")
        if let name = payload.customerName, !name.isEmpty {
            out.append("<p style=\"margin:0 0 12px 0;font-size:13px;\">Customer: \(escapeHTML(name))</p>")
        }
        if let orderNumber = payload.orderNumber, !orderNumber.isEmpty {
            out.append("<p style=\"margin:0 0 12px 0;font-size:13px;\">Order: \(escapeHTML(orderNumber))</p>")
        }

        out.append("<table style=\"width:100%;border-collapse:collapse;font-size:13px;\">")
        out.append("<thead><tr><th align=\"left\" style=\"padding:4px 0;border-bottom:1px solid #ddd;\">Item</th><th align=\"right\" style=\"padding:4px 0;border-bottom:1px solid #ddd;\">Amount</th></tr></thead>")
        out.append("<tbody>")
        for line in payload.lines {
            let qty = line.quantity > 1 ? "\(line.quantity) &times; " : ""
            var detail = ""
            if let sku = line.sku, !sku.isEmpty {
                detail += "<div style=\"color:#888;font-size:11px;\">SKU: \(escapeHTML(sku))</div>"
            }
            if line.discountCents > 0 {
                detail += "<div style=\"color:#888;font-size:11px;\">Line discount: -\(formatCents(line.discountCents, code: payload.currencyCode))</div>"
            }
            out.append("<tr><td style=\"padding:4px 0;\">\(qty)\(escapeHTML(line.name))\(detail)</td><td align=\"right\" style=\"padding:4px 0;font-variant-numeric:tabular-nums;\">\(formatCents(line.lineTotalCents, code: payload.currencyCode))</td></tr>")
        }
        out.append("</tbody></table>")

        out.append("<table style=\"width:100%;border-collapse:collapse;font-size:13px;margin-top:12px;\">")
        out.append(htmlRow(label: "Subtotal", cents: payload.subtotalCents, code: payload.currencyCode))
        if payload.discountCents > 0 {
            out.append(htmlRow(label: "Discount", cents: -payload.discountCents, code: payload.currencyCode))
        }
        if payload.feesCents > 0 {
            out.append(htmlRow(label: "Fees", cents: payload.feesCents, code: payload.currencyCode))
        }
        if payload.taxCents > 0 {
            out.append(htmlRow(label: "Tax", cents: payload.taxCents, code: payload.currencyCode))
        }
        if payload.tipCents > 0 {
            out.append(htmlRow(label: "Tip", cents: payload.tipCents, code: payload.currencyCode))
        }
        out.append(htmlRow(label: "Total", cents: payload.totalCents, code: payload.currencyCode, emphasize: true))
        out.append("</table>")

        if !payload.tenders.isEmpty {
            out.append("<table style=\"width:100%;border-collapse:collapse;font-size:13px;margin-top:12px;\">")
            for tender in payload.tenders {
                var label = tender.method
                if let last4 = tender.last4, !last4.isEmpty {
                    label += " •" + last4
                }
                out.append(htmlRow(label: label, cents: tender.amountCents, code: payload.currencyCode))
            }
            out.append("</table>")
        }

        if let footer = payload.footer, !footer.isEmpty {
            out.append("<p style=\"margin:16px 0 0 0;font-size:12px;color:#666;\">\(escapeHTML(footer))</p>")
        }

        out.append("</body></html>")
        return out.joined(separator: "\n")
    }

    // MARK: - Formatting helpers

    /// Canonical `$12.34` rendering. Shared between text + HTML so the
    /// same cent-count formats identically in both surfaces.
    static func formatCents(_ cents: Int, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        let decimal = Decimal(cents) / 100
        let number = NSDecimalNumber(decimal: decimal)
        return formatter.string(from: number) ?? "$\(Double(cents) / 100)"
    }

    /// Deterministic `yyyy-MM-dd HH:mm` in `en_US_POSIX`. Never drifts by
    /// locale — receipts read the same in a test snapshot and on a phone
    /// set to German.
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// Escape the five characters HTML5 treats specially in body text.
    /// `'` is included so we're safe to use in attribute values too.
    public static func escapeHTML(_ raw: String) -> String {
        var out = ""
        out.reserveCapacity(raw.count)
        for ch in raw {
            switch ch {
            case "&":  out += "&amp;"
            case "<":  out += "&lt;"
            case ">":  out += "&gt;"
            case "\"": out += "&quot;"
            case "'":  out += "&#39;"
            default:   out.append(ch)
            }
        }
        return out
    }

    private static func row(label: String, cents: Int, code: String) -> String {
        "\(label): \(formatCents(cents, code: code))"
    }

    private static func htmlRow(label: String, cents: Int, code: String, emphasize: Bool = false) -> String {
        let weight = emphasize ? "font-weight:700;" : ""
        return "<tr><td style=\"padding:2px 0;\(weight)\">\(escapeHTML(label))</td><td align=\"right\" style=\"padding:2px 0;font-variant-numeric:tabular-nums;\(weight)\">\(formatCents(cents, code: code))</td></tr>"
    }
}
