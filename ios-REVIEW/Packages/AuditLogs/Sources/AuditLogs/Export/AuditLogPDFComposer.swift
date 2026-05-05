#if canImport(UIKit)
import UIKit
import Foundation

// §50.3 Court-evidence PDF export for audit logs.
// Rendered via UIGraphicsPDFRenderer (A4, 595.2 × 841.8 pt).
// Layout: cover header → entries table (paginated) → signature page.
// Thread-safe: all rendering happens inside Task.detached on caller's side.

public enum AuditLogPDFError: LocalizedError {
    case renderFailed
    case writeFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .renderFailed:   return "PDF rendering failed."
        case .writeFailed(let e): return "Could not write PDF: \(e.localizedDescription)"
        }
    }
}

/// Synchronous PDF composer — call from a `Task.detached` to avoid blocking the main actor.
public enum AuditLogPDFComposer {

    // MARK: - Page geometry (A4)

    static let pageWidth:  CGFloat = 595.2
    static let pageHeight: CGFloat = 841.8
    static let marginX:    CGFloat = 36
    static let marginTop:  CGFloat = 48
    static let marginBot:  CGFloat = 48
    static let contentWidth: CGFloat = pageWidth - marginX * 2

    // MARK: - Typography

    static let fontTitle  = UIFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    static let fontHeader = UIFont.systemFont(ofSize: 8, weight: .semibold)
    static let fontBody   = UIFont.monospacedSystemFont(ofSize: 7, weight: .regular)
    static let fontSmall  = UIFont.systemFont(ofSize: 7, weight: .regular)
    static let fontSig    = UIFont.systemFont(ofSize: 9, weight: .regular)

    // MARK: - Colors

    static let colorPrimary  = UIColor(red: 0.91, green: 0.35, blue: 0.00, alpha: 1)  // bizarreOrange
    static let colorText     = UIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)
    static let colorMuted    = UIColor(red: 0.40, green: 0.40, blue: 0.40, alpha: 1)
    static let colorBorder   = UIColor(red: 0.80, green: 0.80, blue: 0.80, alpha: 1)
    static let colorHeaderBg = UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)

    // MARK: - Column widths (sum = contentWidth 523.2)

    static let colWidths: [CGFloat] = [42, 96, 90, 58, 120, 117]
    static let colHeaders = ["ID", "Timestamp", "Actor", "Actor ID", "Action", "Entity"]

    // MARK: - Public interface

    /// Render entries to a PDF and write to a temp file.
    /// - Parameters:
    ///   - entries: Entries to include in the report.
    ///   - tenantName: Name shown on the cover page.
    ///   - exportedBy: Staff member triggering the export (for signature page).
    ///   - since: Optional filter lower bound (display-only on cover).
    ///   - until: Optional filter upper bound (display-only on cover).
    /// - Returns: URL of the written PDF file.
    public static func compose(
        entries: [AuditLogEntry],
        tenantName: String = "BizarreCRM",
        exportedBy: String = "Administrator",
        since: Date? = nil,
        until: Date? = nil
    ) throws -> URL {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(
            x: 0, y: 0, width: pageWidth, height: pageHeight
        ))

        let data = try? renderer.pdfData { ctx in
            // State shared across closure (value types OK — closure is sync)
            var pageNumber = 0

            // MARK: Cover page
            pageNumber += 1
            ctx.beginPage()
            drawCover(
                ctx: ctx.cgContext,
                tenantName: tenantName,
                exportedBy: exportedBy,
                entryCount: entries.count,
                since: since,
                until: until,
                pageNumber: pageNumber,
                totalPagesHint: nil
            )

            // MARK: Entry pages
            let dateFormatter = iso8601Formatter()
            var rowY: CGFloat = marginTop + 12  // start below header
            var firstEntryPage = true

            for (idx, entry) in entries.enumerated() {
                let rowHeight: CGFloat = 13
                let available = pageHeight - marginTop - marginBot - 30  // 30 = table header

                // Need new page?
                let needsNewPage = firstEntryPage ||
                    (rowY + rowHeight > pageHeight - marginBot - 14)

                if needsNewPage {
                    pageNumber += 1
                    ctx.beginPage()
                    drawPageHeader(ctx: ctx.cgContext, pageNumber: pageNumber)
                    drawTableHeader(ctx: ctx.cgContext)
                    rowY = marginTop + 30
                    firstEntryPage = false
                }

                let isEven = idx % 2 == 0
                drawEntryRow(
                    ctx: ctx.cgContext,
                    entry: entry,
                    y: rowY,
                    isEven: isEven,
                    dateFormatter: dateFormatter
                )
                rowY += rowHeight
                drawPageFooter(ctx: ctx.cgContext, pageNumber: pageNumber)
                _ = available  // suppress unused warning
            }

            // MARK: Signature page
            pageNumber += 1
            ctx.beginPage()
            drawSignaturePage(
                ctx: ctx.cgContext,
                exportedBy: exportedBy,
                entryCount: entries.count,
                pageNumber: pageNumber
            )
            drawPageFooter(ctx: ctx.cgContext, pageNumber: pageNumber)
        }

        guard let pdfData = data else { throw AuditLogPDFError.renderFailed }

        let filename = "audit-log-court-\(timestampString()).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try pdfData.write(to: url, options: .atomic)
        } catch {
            throw AuditLogPDFError.writeFailed(underlying: error)
        }
        return url
    }

    // MARK: - Cover page

    private static func drawCover(
        ctx: CGContext,
        tenantName: String,
        exportedBy: String,
        entryCount: Int,
        since: Date?,
        until: Date?,
        pageNumber: Int,
        totalPagesHint: Int?
    ) {
        let logoFont = UIFont.monospacedSystemFont(ofSize: 22, weight: .bold)
        let subFont  = UIFont.systemFont(ofSize: 11, weight: .regular)
        let labelFont = UIFont.systemFont(ofSize: 9, weight: .semibold)
        let valueFont = UIFont.systemFont(ofSize: 9, weight: .regular)

        // Top bar
        ctx.setFillColor(colorPrimary.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pageWidth, height: 6))

        // Title block
        let title = "AUDIT LOG EXPORT"
        drawText(ctx: ctx, text: title, font: logoFont, color: colorPrimary,
                 rect: CGRect(x: marginX, y: 60, width: contentWidth, height: 30))

        let sub = "\(tenantName) — Court-Evidence Format"
        drawText(ctx: ctx, text: sub, font: subFont, color: colorMuted,
                 rect: CGRect(x: marginX, y: 94, width: contentWidth, height: 18))

        // Divider
        drawHRule(ctx: ctx, y: 120)

        // Metadata table
        var my: CGFloat = 140
        let rowH: CGFloat = 18

        let rows: [(String, String)] = [
            ("Generated at",  iso8601Formatter().string(from: Date())),
            ("Exported by",   exportedBy),
            ("Entries",       "\(entryCount)"),
            ("Date from",     since.map { shortFormatter().string(from: $0) } ?? "All"),
            ("Date to",       until.map { shortFormatter().string(from: $0) } ?? "Present"),
        ]

        for (label, value) in rows {
            drawText(ctx: ctx, text: label, font: labelFont, color: colorMuted,
                     rect: CGRect(x: marginX, y: my, width: 100, height: rowH))
            drawText(ctx: ctx, text: value, font: valueFont, color: colorText,
                     rect: CGRect(x: marginX + 110, y: my, width: contentWidth - 110, height: rowH))
            my += rowH
        }

        drawPageFooter(ctx: ctx, pageNumber: pageNumber)
    }

    // MARK: - Page header / footer

    private static func drawPageHeader(ctx: CGContext, pageNumber: Int) {
        // Top rule
        ctx.setFillColor(colorPrimary.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pageWidth, height: 3))

        drawText(ctx: ctx, text: "AUDIT LOG — COURT EVIDENCE",
                 font: UIFont.systemFont(ofSize: 7, weight: .semibold),
                 color: colorMuted,
                 rect: CGRect(x: marginX, y: 8, width: contentWidth, height: 12))
        drawText(ctx: ctx, text: "Page \(pageNumber)",
                 font: UIFont.systemFont(ofSize: 7, weight: .regular),
                 color: colorMuted,
                 rect: CGRect(x: marginX, y: 8, width: contentWidth, height: 12),
                 alignment: .right)
    }

    private static func drawPageFooter(ctx: CGContext, pageNumber: Int) {
        let footerY = pageHeight - marginBot + 12
        drawHRule(ctx: ctx, y: pageHeight - marginBot + 6)
        drawText(ctx: ctx, text: "BizarreCRM — Confidential. Generated \(Date().formatted()). Page \(pageNumber).",
                 font: UIFont.systemFont(ofSize: 6, weight: .regular),
                 color: colorMuted,
                 rect: CGRect(x: marginX, y: footerY, width: contentWidth, height: 12))
    }

    // MARK: - Table header

    private static func drawTableHeader(ctx: CGContext) {
        let y = marginTop + 14
        let rowH: CGFloat = 14

        // Background
        ctx.setFillColor(colorHeaderBg.cgColor)
        ctx.fill(CGRect(x: marginX, y: y, width: contentWidth, height: rowH))

        // Borders
        ctx.setStrokeColor(colorBorder.cgColor)
        ctx.setLineWidth(0.5)
        ctx.stroke(CGRect(x: marginX, y: y, width: contentWidth, height: rowH))

        // Column headers
        var x = marginX + 2
        for (i, header) in colHeaders.enumerated() {
            drawText(ctx: ctx, text: header, font: fontHeader, color: colorText,
                     rect: CGRect(x: x, y: y + 2, width: colWidths[i] - 4, height: rowH - 2))
            x += colWidths[i]
        }
    }

    // MARK: - Entry row

    private static func drawEntryRow(
        ctx: CGContext,
        entry: AuditLogEntry,
        y: CGFloat,
        isEven: Bool,
        dateFormatter: DateFormatter
    ) {
        let rowH: CGFloat = 13

        // Alternating row bg
        if isEven {
            ctx.setFillColor(UIColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1).cgColor)
            ctx.fill(CGRect(x: marginX, y: y, width: contentWidth, height: rowH))
        }

        // Bottom border per row
        ctx.setStrokeColor(colorBorder.cgColor)
        ctx.setLineWidth(0.25)
        ctx.move(to: CGPoint(x: marginX, y: y + rowH))
        ctx.addLine(to: CGPoint(x: marginX + contentWidth, y: y + rowH))
        ctx.strokePath()

        let values: [String] = [
            entry.id,
            dateFormatter.string(from: entry.createdAt),
            entry.actorName,
            entry.actorUserId.map(String.init) ?? "—",
            entry.action,
            "\(entry.entityKind)\(entry.entityId.map { " #\($0)" } ?? "")"
        ]

        var x = marginX + 2
        for (i, value) in values.enumerated() {
            drawText(ctx: ctx, text: value, font: fontBody, color: colorText,
                     rect: CGRect(x: x, y: y + 2, width: colWidths[i] - 4, height: rowH - 2))
            x += colWidths[i]
        }
    }

    // MARK: - Signature page

    private static func drawSignaturePage(
        ctx: CGContext,
        exportedBy: String,
        entryCount: Int,
        pageNumber: Int
    ) {
        ctx.setFillColor(colorPrimary.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pageWidth, height: 3))

        let titleFont = UIFont.systemFont(ofSize: 14, weight: .bold)
        drawText(ctx: ctx, text: "CERTIFICATION OF AUTHENTICITY",
                 font: titleFont, color: colorPrimary,
                 rect: CGRect(x: marginX, y: 60, width: contentWidth, height: 24))

        drawHRule(ctx: ctx, y: 90)

        let bodyText = """
This document is a true and accurate export of the audit log records from BizarreCRM \
as of \(Date().formatted(date: .long, time: .complete)). \
The export contains \(entryCount) log entries.

The records contained herein were generated by the BizarreCRM system and have not been \
altered in any manner. Each entry is immutable as enforced by the server-side audit engine.

Exported by: \(exportedBy)
"""

        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = 4

        let attrs: [NSAttributedString.Key: Any] = [
            .font: fontSig,
            .foregroundColor: colorText,
            .paragraphStyle: paraStyle
        ]

        let attrStr = NSAttributedString(string: bodyText, attributes: attrs)
        attrStr.draw(in: CGRect(x: marginX, y: 104, width: contentWidth, height: 200))

        // Signature lines
        let sigY: CGFloat = 340
        drawHRule(ctx: ctx, y: sigY)
        drawText(ctx: ctx, text: "Authorised Signature", font: fontSig, color: colorMuted,
                 rect: CGRect(x: marginX, y: sigY + 6, width: 200, height: 16))
        drawText(ctx: ctx, text: "Date", font: fontSig, color: colorMuted,
                 rect: CGRect(x: marginX + 300, y: sigY + 6, width: 100, height: 16))

        drawHRule(ctx: ctx, y: sigY + 36)
        drawText(ctx: ctx, text: "Witness Signature", font: fontSig, color: colorMuted,
                 rect: CGRect(x: marginX, y: sigY + 42, width: 200, height: 16))
        drawText(ctx: ctx, text: "Date", font: fontSig, color: colorMuted,
                 rect: CGRect(x: marginX + 300, y: sigY + 42, width: 100, height: 16))

        drawPageFooter(ctx: ctx, pageNumber: pageNumber)
    }

    // MARK: - Drawing helpers

    private static func drawHRule(ctx: CGContext, y: CGFloat) {
        ctx.setStrokeColor(colorBorder.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: marginX, y: y))
        ctx.addLine(to: CGPoint(x: marginX + contentWidth, y: y))
        ctx.strokePath()
    }

    private static func drawText(
        ctx: CGContext,
        text: String,
        font: UIFont,
        color: UIColor,
        rect: CGRect,
        alignment: NSTextAlignment = .left
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style
        ]
        NSAttributedString(string: text, attributes: attrs).draw(in: rect)
    }

    // MARK: - Formatters

    private static func iso8601Formatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }

    private static func shortFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }

    private static func timestampString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }
}
#else
import Foundation

// macOS / non-UIKit stub — PDF generation not supported.
public enum AuditLogPDFError: LocalizedError {
    case platformNotSupported
    public var errorDescription: String? { "PDF export requires iOS/iPadOS." }
}

public enum AuditLogPDFComposer {
    public static func compose(
        entries: [AuditLogEntry],
        tenantName: String = "BizarreCRM",
        exportedBy: String = "Administrator",
        since: Date? = nil,
        until: Date? = nil
    ) throws -> URL {
        throw AuditLogPDFError.platformNotSupported
    }
}
#endif
