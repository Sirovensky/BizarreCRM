import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - ReportSnapshot

/// Snapshot of all data needed to render a PDF report.
public struct ReportSnapshot: Sendable {
    public let title: String
    public let period: String
    public let revenue: [RevenuePoint]
    public let ticketsByStatus: [TicketStatusPoint]
    public let avgTicketValue: AvgTicketValue?
    public let topEmployees: [EmployeePerf]
    public let inventoryTurnover: [InventoryTurnoverRow]
    public let csatScore: CSATScore?
    public let npsScore: NPSScore?
    public let generatedAt: Date

    public init(title: String,
                period: String,
                revenue: [RevenuePoint],
                ticketsByStatus: [TicketStatusPoint],
                avgTicketValue: AvgTicketValue?,
                topEmployees: [EmployeePerf],
                inventoryTurnover: [InventoryTurnoverRow],
                csatScore: CSATScore?,
                npsScore: NPSScore?,
                generatedAt: Date = Date()) {
        self.title = title
        self.period = period
        self.revenue = revenue
        self.ticketsByStatus = ticketsByStatus
        self.avgTicketValue = avgTicketValue
        self.topEmployees = topEmployees
        self.inventoryTurnover = inventoryTurnover
        self.csatScore = csatScore
        self.npsScore = npsScore
        self.generatedAt = generatedAt
    }
}

// MARK: - ReportExportService

public actor ReportExportService {
    private let repository: ReportsRepository

    public init(repository: ReportsRepository) {
        self.repository = repository
    }

    // MARK: - PDF Generation

    /// Renders a `ReportSnapshot` to a temporary PDF file.
    /// Returns the URL of the written file.
    public func generatePDF(report: ReportSnapshot) async throws -> URL {
        #if canImport(UIKit)
        return try await Task.detached(priority: .userInitiated) {
            try Self.renderPDF(report: report)
        }.value
        #elseif canImport(AppKit)
        return try await Task.detached(priority: .userInitiated) {
            try Self.renderPDFMac(report: report)
        }.value
        #else
        throw ReportExportError.platformNotSupported
        #endif
    }

    // MARK: - Filename token

    /// Derives a sanitised PDF filename from the report title and period.
    ///
    /// Format: `{SafeTitle}_{SafePeriod}.pdf`
    /// where each component has whitespace collapsed to underscores and
    /// non-alphanumeric/underscore characters stripped so the result is
    /// safe for every major filesystem and safe to pass to share-sheet /
    /// UIDocumentInteractionController without further escaping.
    ///
    /// Example: "BizarreCRM Report" + "2025-01-01 – 2025-01-31"
    ///          → `BizarreCRM_Report_2025-01-01_2025-01-31.pdf`
    private static func pdfFilename(for report: ReportSnapshot) -> String {
        func sanitise(_ s: String) -> String {
            s.replacingOccurrences(of: " ", with: "_")
             .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-")))
             .joined()
        }
        let titlePart  = sanitise(report.title)
        let periodPart = sanitise(report.period)
        let base = [titlePart, periodPart].filter { !$0.isEmpty }.joined(separator: "_")
        let safeName = base.isEmpty ? "BizarreCRM_Report" : base
        return "\(safeName).pdf"
    }

    #if canImport(UIKit)
    private static func renderPDF(report: ReportSnapshot) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4

        let tempURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(Self.pdfFilename(for: report))

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.label
            ]
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.tertiaryLabel
            ]

            var y: CGFloat = 40
            let margin: CGFloat = 40
            let width = pageRect.width - margin * 2

            // Title
            report.title.draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
            y += 36

            // Period + generated date
            report.period.draw(at: CGPoint(x: margin, y: y), withAttributes: bodyAttrs)
            y += 20

            let dateStr = "Generated \(Self.shortDate(report.generatedAt))"
            dateStr.draw(at: CGPoint(x: margin, y: y), withAttributes: dateAttrs)
            y += 30

            // Revenue summary
            let totalRevenue = report.revenue.reduce(0) { $0 + $1.amountCents }
            let revenueStr = String(format: "Total Revenue: $%.2f", Double(totalRevenue) / 100.0)
            revenueStr.draw(at: CGPoint(x: margin, y: y), withAttributes: bodyAttrs)
            y += 20

            // Avg ticket value
            if let atv = report.avgTicketValue {
                let atvStr = String(format: "Avg Ticket Value: $%.2f (%.1f%% trend)", atv.currentDollars, atv.trendPct)
                atvStr.draw(at: CGPoint(x: margin, y: y), withAttributes: bodyAttrs)
                y += 20
            }

            // CSAT
            if let csat = report.csatScore {
                let csatStr = String(format: "CSAT Score: %.1f / 5.0 (%d responses)", csat.current, csat.responseCount)
                csatStr.draw(at: CGPoint(x: margin, y: y), withAttributes: bodyAttrs)
                y += 20
            }

            // NPS
            if let nps = report.npsScore {
                let npsStr = "NPS Score: \(nps.current) (Promoters \(String(format: "%.0f%%", nps.promoterPct)), Detractors \(String(format: "%.0f%%", nps.detractorPct)))"
                npsStr.draw(in: CGRect(x: margin, y: y, width: width, height: 40), withAttributes: bodyAttrs)
                y += 30
            }

            // Top employees
            if !report.topEmployees.isEmpty {
                y += 10
                "Top Employees".draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
                y += 24
                for emp in report.topEmployees.prefix(5) {
                    let empStr = String(format: "• %@: %d tickets, $%.2f revenue", emp.employeeName, emp.ticketsClosed, emp.revenueDollars)
                    empStr.draw(in: CGRect(x: margin, y: y, width: width, height: 20), withAttributes: bodyAttrs)
                    y += 18
                    if y > pageRect.height - 60 {
                        ctx.beginPage()
                        y = 40
                    }
                }
            }

            // Tickets by status
            if !report.ticketsByStatus.isEmpty {
                y += 10
                "Tickets by Status".draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
                y += 24
                for pt in report.ticketsByStatus {
                    let ptStr = "• \(pt.status): \(pt.count)"
                    ptStr.draw(at: CGPoint(x: margin, y: y), withAttributes: bodyAttrs)
                    y += 18
                }
            }

            // Inventory turnover (slowest movers)
            let slowest = report.inventoryTurnover.sorted { $0.daysOnHand > $1.daysOnHand }.prefix(10)
            if !slowest.isEmpty {
                if y > pageRect.height - 120 {
                    ctx.beginPage()
                    y = 40
                }
                y += 10
                "Slowest Inventory (by Days on Hand)".draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
                y += 24
                for row in slowest {
                    let rowStr = String(format: "• %@ (%@): %.0f days on hand, rate %.1f", row.name, row.sku, row.daysOnHand, row.turnoverRate)
                    rowStr.draw(in: CGRect(x: margin, y: y, width: width, height: 20), withAttributes: bodyAttrs)
                    y += 18
                    if y > pageRect.height - 60 {
                        ctx.beginPage()
                        y = 40
                    }
                }
            }
        }

        try data.write(to: tempURL)
        return tempURL
    }

    private static func shortDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
    #endif

    // MARK: - Email

    /// Sends report PDF via the server's email endpoint.
    /// Passes base64-encoded PDF to `POST /api/v1/reports/email`.
    public func emailReport(pdf: URL, recipient: String) async throws {
        let data = try Data(contentsOf: pdf)
        let base64 = data.base64EncodedString()
        try await repository.emailReport(recipient: recipient, pdfBase64: base64)
    }

    #if canImport(AppKit)
    private static func renderPDFMac(report: ReportSnapshot) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let tempURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(Self.pdfFilename(for: report))

        var mediaBox = pageRect
        guard let ctx = CGContext(tempURL as CFURL, mediaBox: &mediaBox, nil) else {
            throw ReportExportError.pdfRenderFailed
        }
        ctx.beginPDFPage(nil)
        let titleStr = "\(report.title) — \(report.period)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 20)
        ]
        titleStr.draw(at: CGPoint(x: 40, y: pageRect.height - 60), withAttributes: attrs)

        let revenue = report.revenue.reduce(0) { $0 + $1.amountCents }
        let revenueStr = String(format: "Total Revenue: $%.2f", Double(revenue) / 100.0) as NSString
        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12)]
        revenueStr.draw(at: CGPoint(x: 40, y: pageRect.height - 100), withAttributes: bodyAttrs)

        ctx.endPDFPage()
        ctx.closePDF()
        return tempURL
    }
    #endif
}

// MARK: - Errors

public enum ReportExportError: Error, LocalizedError {
    case platformNotSupported
    case pdfRenderFailed

    public var errorDescription: String? {
        switch self {
        case .platformNotSupported: return "PDF export is not supported on this platform."
        case .pdfRenderFailed:      return "Failed to render the PDF report."
        }
    }
}
