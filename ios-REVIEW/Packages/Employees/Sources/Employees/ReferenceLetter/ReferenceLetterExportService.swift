import Foundation
import PDFKit
import SwiftUI
import DesignSystem
import Core

// MARK: - ReferenceLetterExportService
//
// §14 Reference letter (nice-to-have): auto-generate PDF summarizing tenure + stats
// (total tickets, sales); manager customizes before export.
//
// The export is on-device only — no data leaves the tenant server (§32 sovereignty).
// Uses UIGraphicsPDFRenderer so it is available on iOS 13+ without PDFKit restrictions.

public enum ReferenceLetterExportService {

    // MARK: - Public API

    /// Generate a reference letter PDF for the given employee.
    ///
    /// - Parameters:
    ///   - employee: The subject of the reference letter.
    ///   - stats: Performance stats compiled from §46.4 scorecard.
    ///   - authorName: Manager / owner name who is writing the reference.
    ///   - customBody: Optional manager-customized body text (overrides the auto-generated copy).
    /// - Returns: `Data` containing the generated PDF bytes, or throws on failure.
    public static func generatePDF(
        employee: ReferenceLetterEmployee,
        stats: ReferenceLetterStats,
        authorName: String,
        customBody: String? = nil
    ) throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
#if canImport(UIKit)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            renderLetterhead(in: pageRect)
            renderHeader(in: pageRect, employee: employee, authorName: authorName)
            renderBody(in: pageRect, employee: employee, stats: stats, customBody: customBody)
            renderFooter(in: pageRect)
        }
        return data
#else
        throw ReferenceLetterError.platformUnsupported
#endif
    }

    // MARK: - Private drawing helpers

#if canImport(UIKit)
    private static func renderLetterhead(in page: CGRect) {
        // Brand colour band at top
        let brandColor = UIColor(red: 1.0, green: 0.44, blue: 0.0, alpha: 1.0) // bizarreOrange
        brandColor.setFill()
        let band = CGRect(x: 0, y: 0, width: page.width, height: 6)
        UIBezierPath(rect: band).fill()
    }

    private static func renderHeader(in page: CGRect, employee: ReferenceLetterEmployee, authorName: String) {
        let titleFont = UIFont.systemFont(ofSize: 22, weight: .bold)
        let subFont   = UIFont.systemFont(ofSize: 13, weight: .regular)
        let dateFmt = DateFormatter(); dateFmt.dateStyle = .long; dateFmt.timeStyle = .none

        let titleAttr: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: UIColor.label]
        let subAttr:   [NSAttributedString.Key: Any] = [.font: subFont,   .foregroundColor: UIColor.secondaryLabel]

        let title = NSAttributedString(string: "Letter of Reference", attributes: titleAttr)
        title.draw(at: CGPoint(x: 56, y: 30))

        let dateStr = "Dated: \(dateFmt.string(from: Date()))"
        let dateLine = NSAttributedString(string: dateStr, attributes: subAttr)
        dateLine.draw(at: CGPoint(x: 56, y: 60))

        UIColor.separator.setStroke()
        let rule = UIBezierPath()
        rule.move(to: CGPoint(x: 56, y: 86))
        rule.addLine(to: CGPoint(x: page.width - 56, y: 86))
        rule.lineWidth = 0.5
        rule.stroke()
    }

    private static func renderBody(
        in page: CGRect,
        employee: ReferenceLetterEmployee,
        stats: ReferenceLetterStats,
        customBody: String?
    ) {
        let bodyFont = UIFont.systemFont(ofSize: 12)
        let bodyAttr: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: UIColor.label]
        let indent = CGFloat(56)
        let maxWidth = page.width - indent * 2

        var y = CGFloat(100)

        let tenureStr = tenureDescription(start: stats.startDate, end: stats.endDate)

        let body: String
        if let custom = customBody, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body = custom
        } else {
            body = defaultBody(employee: employee, stats: stats, tenureStr: tenureStr)
        }

        let paragraph = NSAttributedString(string: body, attributes: bodyAttr)
        let textRect = CGRect(x: indent, y: y, width: maxWidth, height: page.height - y - 100)
        paragraph.draw(in: textRect)

        // Stats table
        y = 480
        renderStatsTable(y: &y, x: indent, width: maxWidth, stats: stats, bodyAttr: bodyAttr)
    }

    private static func renderStatsTable(y: inout CGFloat, x: CGFloat, width: CGFloat, stats: ReferenceLetterStats, bodyAttr: [NSAttributedString.Key: Any]) {
        let headerFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
        let headerAttr: [NSAttributedString.Key: Any] = [.font: headerFont, .foregroundColor: UIColor.secondaryLabel]

        let header = NSAttributedString(string: "PERFORMANCE SUMMARY", attributes: headerAttr)
        header.draw(at: CGPoint(x: x, y: y))
        y += 18

        UIColor.separator.setStroke()
        let rule = UIBezierPath()
        rule.move(to: CGPoint(x: x, y: y))
        rule.addLine(to: CGPoint(x: x + width, y: y))
        rule.lineWidth = 0.25
        rule.stroke()
        y += 8

        let rows: [(String, String)] = [
            ("Total tickets closed", "\(stats.totalTickets)"),
            ("Revenue attributed",   stats.revenueFormatted),
            ("Average customer rating", stats.avgRating.map { String(format: "%.1f / 5.0", $0) } ?? "—"),
            ("Commission earned",    stats.commissionFormatted),
        ]

        for (label, value) in rows {
            let line = NSAttributedString(string: "\(label):  \(value)", attributes: bodyAttr)
            line.draw(at: CGPoint(x: x + 8, y: y))
            y += 16
        }
    }

    private static func renderFooter(in page: CGRect) {
        let footerFont = UIFont.systemFont(ofSize: 9)
        let footerAttr: [NSAttributedString.Key: Any] = [.font: footerFont, .foregroundColor: UIColor.tertiaryLabel]
        let footer = NSAttributedString(
            string: "Generated by BizarreCRM — Confidential",
            attributes: footerAttr
        )
        footer.draw(at: CGPoint(x: 56, y: page.height - 36))
    }

    // MARK: - Copy helpers

    private static func defaultBody(employee: ReferenceLetterEmployee, stats: ReferenceLetterStats, tenureStr: String) -> String {
        """
To whom it may concern,

It is my pleasure to recommend \(employee.fullName) for their next opportunity.

\(employee.firstName) joined our team as \(employee.role) and served with us \(tenureStr). During their tenure, they demonstrated strong professionalism, consistent performance, and a genuine commitment to customer satisfaction.

\(employee.firstName) was a valued member of our operations and I am confident they will bring the same dedication to their next role.

Please feel free to reach out with any questions.


Sincerely,
"""
    }

    private static func tenureDescription(start: Date?, end: Date?) -> String {
        guard let start else { return "as a valued employee" }
        let fmt = DateFormatter(); fmt.dateStyle = .medium; fmt.timeStyle = .none
        let endStr = end.map { fmt.string(from: $0) } ?? "present"
        return "from \(fmt.string(from: start)) to \(endStr)"
    }
#endif
}

// MARK: - Supporting types

/// Employee data for the reference letter.
public struct ReferenceLetterEmployee: Sendable {
    public let fullName: String
    public let firstName: String
    public let role: String

    public init(fullName: String, firstName: String, role: String) {
        self.fullName = fullName
        self.firstName = firstName
        self.role = role
    }
}

/// Performance statistics for the reference letter summary table.
public struct ReferenceLetterStats: Sendable {
    public let startDate: Date?
    public let endDate: Date?
    public let totalTickets: Int
    public let revenueFormatted: String
    public let avgRating: Double?
    public let commissionFormatted: String

    public init(
        startDate: Date?,
        endDate: Date?,
        totalTickets: Int,
        revenueFormatted: String,
        avgRating: Double?,
        commissionFormatted: String
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.totalTickets = totalTickets
        self.revenueFormatted = revenueFormatted
        self.avgRating = avgRating
        self.commissionFormatted = commissionFormatted
    }
}

// MARK: - Errors

public enum ReferenceLetterError: Error, LocalizedError {
    case platformUnsupported

    public var errorDescription: String? {
        switch self {
        case .platformUnsupported:
            return "Reference letter PDF generation requires UIKit (iOS/iPadOS)."
        }
    }
}
