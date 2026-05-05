import Foundation
#if canImport(UIKit)
import UIKit
#endif

// §7.2 InvoicePrintService — shared actor for PDF rendering.
// Used by both AirPrint (UIPrintInteractionController) and Share PDF (ShareLink).
// All rendering is synchronous in a detached Task to avoid blocking the main actor.

import Networking

public actor InvoicePrintService {

    public init() {}

    // MARK: - PDF generation

    /// Renders an InvoiceDetail to a temporary PDF file URL.
    /// Throws `InvoicePrintError.renderFailed` if UIKit is unavailable.
    public func generatePDF(invoice: InvoiceDetail) async throws -> URL {
        #if canImport(UIKit)
        return try await Task.detached(priority: .userInitiated) {
            try Self.renderPDF(invoice: invoice)
        }.value
        #else
        throw InvoicePrintError.platformNotSupported
        #endif
    }

    #if canImport(UIKit)
    private static func renderPDF(invoice: InvoiceDetail) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4 portrait

        let fileName = "Invoice_\(invoice.orderId?.replacingOccurrences(of: "/", with: "-") ?? "\(invoice.id)").pdf"
        let tempURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(fileName)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()

            let margin: CGFloat = 48
            let width  = pageRect.width - margin * 2
            var y: CGFloat = margin

            // ── Header ──────────────────────────────────────────────────────────
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor.label
            ]
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let monoAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.label
            ]
            let sectionAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 14),
                .foregroundColor: UIColor.label
            ]
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.label
            ]
            let mutedAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.secondaryLabel
            ]

            draw(text: "INVOICE", attrs: titleAttrs, x: margin, y: &y, width: width)
            y += 4
            draw(text: invoice.orderId ?? "INV-?", attrs: monoAttrs, x: margin, y: &y, width: width)
            y += 4
            let statusText = (invoice.status ?? "—").capitalized
            draw(text: statusText, attrs: subAttrs, x: margin, y: &y, width: width)
            y += 12

            // ── Customer ─────────────────────────────────────────────────────────
            draw(text: "Bill to", attrs: sectionAttrs, x: margin, y: &y, width: width)
            y += 2
            draw(text: invoice.customerDisplayName, attrs: bodyAttrs, x: margin, y: &y, width: width)
            if let email = invoice.customerEmail, !email.isEmpty {
                draw(text: email, attrs: mutedAttrs, x: margin, y: &y, width: width)
            }
            if let phone = invoice.customerPhone, !phone.isEmpty {
                draw(text: phone, attrs: mutedAttrs, x: margin, y: &y, width: width)
            }
            y += 12

            // ── Dates ────────────────────────────────────────────────────────────
            if let issued = invoice.createdAt {
                draw(text: "Issued: \(String(issued.prefix(10)))", attrs: subAttrs, x: margin, y: &y, width: width)
            }
            if let due = invoice.dueOn, !due.isEmpty {
                draw(text: "Due:    \(String(due.prefix(10)))", attrs: subAttrs, x: margin, y: &y, width: width)
            }
            y += 16

            // ── Line items ───────────────────────────────────────────────────────
            if let items = invoice.lineItems, !items.isEmpty {
                draw(text: "Items", attrs: sectionAttrs, x: margin, y: &y, width: width)
                y += 4
                // Column header
                let colHeaderAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 10),
                    .foregroundColor: UIColor.secondaryLabel
                ]
                let headerRow = NSAttributedString(string: "DESCRIPTION                         QTY  UNIT PRICE      TOTAL", attributes: colHeaderAttrs)
                headerRow.draw(in: CGRect(x: margin, y: y, width: width, height: 16))
                y += 18

                let lineAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11),
                    .foregroundColor: UIColor.label
                ]
                for item in items {
                    let name = String((item.displayName).prefix(36))
                    let qty = item.quantity.map { String(format: "%.0f", $0) } ?? "1"
                    let unit = item.unitPrice.map { formatMoney($0) } ?? "—"
                    let total = item.total.map { formatMoney($0) } ?? "—"
                    let line = "\(name.padding(toLength: 36, withPad: " ", startingAt: 0)) \(qty.padding(toLength: 4, withPad: " ", startingAt: 0)) \(unit.padding(toLength: 14, withPad: " ", startingAt: 0)) \(total)"
                    draw(text: line, attrs: lineAttrs, x: margin, y: &y, width: width)
                    if let tax = item.taxAmount, tax > 0 {
                        draw(text: "  Tax: \(formatMoney(tax))", attrs: mutedAttrs, x: margin, y: &y, width: width)
                    }
                    y += 2
                }
                y += 10
            }

            // ── Totals ───────────────────────────────────────────────────────────
            let dividerPath = UIBezierPath()
            dividerPath.move(to: CGPoint(x: margin, y: y))
            dividerPath.addLine(to: CGPoint(x: margin + width, y: y))
            UIColor.separator.setStroke()
            dividerPath.stroke()
            y += 6

            if let sub = invoice.subtotal, sub != (invoice.total ?? 0) {
                drawTotalRow(label: "Subtotal", value: formatMoney(sub), x: margin, y: &y, width: width, attrs: mutedAttrs)
            }
            if let disc = invoice.discount, disc > 0 {
                drawTotalRow(label: "Discount", value: "-\(formatMoney(disc))", x: margin, y: &y, width: width, attrs: mutedAttrs)
            }
            if let tax = invoice.totalTax, tax > 0 {
                drawTotalRow(label: "Tax", value: formatMoney(tax), x: margin, y: &y, width: width, attrs: mutedAttrs)
            }

            let totalAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 14),
                .foregroundColor: UIColor.label
            ]
            drawTotalRow(label: "Total", value: formatMoney(invoice.total ?? 0), x: margin, y: &y, width: width, attrs: totalAttrs)

            if let paid = invoice.amountPaid, paid > 0 {
                drawTotalRow(label: "Paid", value: "-\(formatMoney(paid))", x: margin, y: &y, width: width, attrs: mutedAttrs)
            }
            if let due = invoice.amountDue, due > 0 {
                let dueAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 14),
                    .foregroundColor: UIColor.systemRed
                ]
                drawTotalRow(label: "Balance due", value: formatMoney(due), x: margin, y: &y, width: width, attrs: dueAttrs)
            }
            y += 16

            // ── Notes ────────────────────────────────────────────────────────────
            if let notes = invoice.notes, !notes.isEmpty {
                draw(text: "Notes", attrs: sectionAttrs, x: margin, y: &y, width: width)
                draw(text: notes, attrs: bodyAttrs, x: margin, y: &y, width: width)
                y += 8
            }

            // ── Footer ───────────────────────────────────────────────────────────
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor.tertiaryLabel
            ]
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let generated = "Generated \(formatter.string(from: Date()))"
            draw(text: generated, attrs: footerAttrs, x: margin, y: &y, width: width)
        }

        try data.write(to: tempURL)
        return tempURL
    }

    // MARK: - Render helpers

    private static func draw(text: String, attrs: [NSAttributedString.Key: Any], x: CGFloat, y: inout CGFloat, width: CGFloat) {
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.boundingRect(with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
                                    options: [.usesLineFragmentOrigin],
                                    context: nil).size
        str.draw(in: CGRect(x: x, y: y, width: width, height: size.height))
        y += size.height + 2
    }

    private static func drawTotalRow(label: String, value: String, x: CGFloat, y: inout CGFloat, width: CGFloat, attrs: [NSAttributedString.Key: Any]) {
        let str = NSAttributedString(string: label, attributes: attrs)
        let valueStr = NSAttributedString(string: value, attributes: attrs)
        let rowHeight: CGFloat = 18
        str.draw(in: CGRect(x: x, y: y, width: width * 0.7, height: rowHeight))
        valueStr.draw(in: CGRect(x: x + width * 0.7, y: y, width: width * 0.3, height: rowHeight))
        y += rowHeight
    }
    #endif
}

private func formatMoney(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    return f.string(from: NSNumber(value: v)) ?? "$\(v)"
}

// MARK: - Error

public enum InvoicePrintError: LocalizedError, Sendable {
    case renderFailed(String)
    case platformNotSupported

    public var errorDescription: String? {
        switch self {
        case .renderFailed(let msg): return "Could not render invoice PDF: \(msg)"
        case .platformNotSupported:  return "PDF rendering not supported on this platform."
        }
    }
}
