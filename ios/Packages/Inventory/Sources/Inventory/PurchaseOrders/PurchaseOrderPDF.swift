#if canImport(UIKit)
import SwiftUI
import UniformTypeIdentifiers
import CoreGraphics
import UIKit

// MARK: - §6.7 PO PDF Export

// MARK: PDFDocument (FileDocument)

/// Thin `FileDocument` wrapper so `.fileExporter` can write PDF bytes to disk.
public struct PDFDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.pdf] }
    public var data: Data

    public init(data: Data) { self.data = data }

    public init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - PurchaseOrderPDFRenderer

/// Renders a `PurchaseOrder` into a simple PDF using CoreGraphics.
/// Layout: header (PO#, status, dates), supplier block, line-items table, total.
public enum PurchaseOrderPDFRenderer {

    private static let pageWidth: CGFloat  = 595   // A4 points
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat     = 40

    private static let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 22, weight: .bold),
        .foregroundColor: UIColor.label
    ]
    private static let headingAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
        .foregroundColor: UIColor.label
    ]
    private static let bodyAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 11, weight: .regular),
        .foregroundColor: UIColor.secondaryLabel
    ]
    private static let monoAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: UIColor.label
    ]

    public static func render(po: PurchaseOrder, supplier: Supplier?) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = margin

            // Title
            y = drawText("Purchase Order #\(po.id)", attrs: titleAttrs, at: y, maxWidth: pageWidth - margin * 2)
            y += 6

            // Status + dates row
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .none
            var meta = "Status: \(po.status.displayName)   Created: \(df.string(from: po.createdAt))"
            if let exp = po.expectedDate { meta += "   Expected: \(df.string(from: exp))" }
            y = drawText(meta, attrs: bodyAttrs, at: y, maxWidth: pageWidth - margin * 2)
            y += 12

            // Supplier block
            y = drawText("Supplier", attrs: headingAttrs, at: y, maxWidth: pageWidth - margin * 2)
            y += 2
            if let s = supplier {
                var lines2: [String] = [s.name]
                if let c = s.contactName, !c.isEmpty { lines2.append(c) }
                lines2.append(contentsOf: [s.email, s.phone, "Terms: \(s.paymentTerms)", "Lead: \(s.leadTimeDays)d"])
                let contact = lines2.joined(separator: "\n")
                y = drawText(contact, attrs: bodyAttrs, at: y, maxWidth: pageWidth - margin * 2)
            } else {
                y = drawText("Supplier #\(po.supplierId)", attrs: bodyAttrs, at: y, maxWidth: pageWidth - margin * 2)
            }
            y += 14

            // Line items table header
            y = drawTableRow(col1: "SKU", col2: "Name", col3: "Qty", col4: "Unit", col5: "Line Total",
                             attrs: headingAttrs, y: y)
            y += 2
            // Divider
            UIColor.separator.setStroke()
            let divPath = UIBezierPath()
            divPath.move(to: CGPoint(x: margin, y: y))
            divPath.addLine(to: CGPoint(x: pageWidth - margin, y: y))
            divPath.lineWidth = 0.5
            divPath.stroke()
            y += 4

            for line in po.items {
                let unitStr  = (Double(line.unitCostCents) / 100.0).currencyString
                let totalStr = (Double(line.lineTotalCents) / 100.0).currencyString
                y = drawTableRow(col1: line.sku,
                                 col2: line.name,
                                 col3: "\(line.qtyOrdered) (rcvd \(line.qtyReceived))",
                                 col4: unitStr,
                                 col5: totalStr,
                                 attrs: monoAttrs,
                                 y: y)
                // page break guard
                if y > pageHeight - margin - 60 {
                    ctx.beginPage()
                    y = margin
                }
            }

            y += 12
            // Total line
            let totalStr = (Double(po.totalCents) / 100.0).currencyString
            y = drawTableRow(col1: "", col2: "", col3: "", col4: "TOTAL",
                             col5: totalStr, attrs: headingAttrs, y: y)

            // Notes
            if let notes = po.notes, !notes.isEmpty {
                y += 14
                y = drawText("Notes", attrs: headingAttrs, at: y, maxWidth: pageWidth - margin * 2)
                y += 2
                y = drawText(notes, attrs: bodyAttrs, at: y, maxWidth: pageWidth - margin * 2)
            }
        }
    }

    // MARK: - Draw helpers

    @discardableResult
    private static func drawText(_ text: String, attrs: [NSAttributedString.Key: Any],
                                 at y: CGFloat, maxWidth: CGFloat) -> CGFloat {
        let str = NSAttributedString(string: text, attributes: attrs)
        let boundingRect = str.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        str.draw(in: CGRect(x: margin, y: y, width: maxWidth, height: boundingRect.height))
        return y + boundingRect.height + 4
    }

    @discardableResult
    private static func drawTableRow(col1: String, col2: String, col3: String,
                                     col4: String, col5: String,
                                     attrs: [NSAttributedString.Key: Any],
                                     y: CGFloat) -> CGFloat {
        let contentWidth = pageWidth - margin * 2
        // Column widths (proportional)
        let w1: CGFloat = contentWidth * 0.14   // SKU
        let w2: CGFloat = contentWidth * 0.34   // Name
        let w3: CGFloat = contentWidth * 0.17   // Qty
        let w4: CGFloat = contentWidth * 0.17   // Unit
        let w5: CGFloat = contentWidth * 0.18   // Line Total

        var x = margin
        var maxH: CGFloat = 0

        func cell(_ text: String, width: CGFloat) {
            let str = NSAttributedString(string: text, attributes: attrs)
            let br = str.boundingRect(
                with: CGSize(width: width - 4, height: 100),
                options: [.usesLineFragmentOrigin],
                context: nil
            )
            str.draw(in: CGRect(x: x + 2, y: y, width: width - 4, height: br.height))
            maxH = max(maxH, br.height)
            x += width
        }

        cell(col1, width: w1)
        cell(col2, width: w2)
        cell(col3, width: w3)
        cell(col4, width: w4)
        cell(col5, width: w5)

        return y + maxH + 4
    }
}

// MARK: - Double currency helper

private extension Double {
    var currencyString: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: self)) ?? "$\(self)"
    }
}
#endif
