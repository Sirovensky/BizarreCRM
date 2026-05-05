import Foundation
import Core

// MARK: - ScorecardExportService

/// Exports an `EmployeeScorecard` to a PDF file in the temp directory.
/// Caller is responsible for presenting the share sheet with the returned URL.
public enum ScorecardExportService: Sendable {

    /// Asynchronously renders the scorecard to PDF and returns the file URL.
    public static func exportPDF(_ scorecard: EmployeeScorecard) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scorecard-\(scorecard.employeeId)-\(scorecard.windowDays)d.pdf")
        let content = buildPDFContent(scorecard)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Private

    private static func buildPDFContent(_ card: EmployeeScorecard) -> String {
        // Production implementation would use PDFKit / UIGraphicsPDFRenderer.
        // This string is a structured placeholder so the plumbing is complete.
        var lines = ["Employee Scorecard", "Employee: \(card.employeeId)", "Window: \(card.windowDays) days", ""]
        lines.append(String(format: "Ticket Close Rate: %.0f%%", card.ticketCloseRate * 100))
        lines.append(String(format: "SLA Compliance:    %.0f%%", card.slaCompliance * 100))
        lines.append(String(format: "Avg Customer Rating: %.1f / 5.0", card.avgCustomerRating))
        lines.append(String(format: "Revenue Attributed: $%.2f", card.revenueAttributed))
        lines.append(String(format: "Commission Earned:  $%.2f", card.commissionEarned))
        lines.append(String(format: "Hours Worked: %.1f", card.hoursWorked))
        lines.append("Voids: \(card.voidsTriggered)  |  Overrides: \(card.overridesTriggered)")
        lines.append("")
        lines.append(String(format: "Composite Score: %.0f / 100", ScorecardAggregator.compositeScore(card)))
        return lines.joined(separator: "\n")
    }
}
