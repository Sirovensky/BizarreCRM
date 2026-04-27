#if canImport(UIKit)
import Foundation
import Core

// MARK: - §5.6 Bulk export selected customers as CSV

public enum CustomerCSVExporter {
    /// Generates a CSV file from the given customer summaries and returns the file URL.
    /// Returns nil if the write fails.
    public static func export(_ customers: [CustomerSummary]) -> URL? {
        let header = "ID,Name,Email,Phone,Organization,City,State,Tickets\n"
        let rows = customers.map { c -> String in
            [
                String(c.id),
                c.displayName,
                c.email ?? "",
                c.mobile ?? c.phone ?? "",
                c.organization ?? "",
                c.city ?? "",
                c.state ?? "",
                c.ticketCount.map(String.init) ?? ""
            ]
            .map { field -> String in
                let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
                return escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n")
                    ? "\"\(escaped)\""
                    : escaped
            }
            .joined(separator: ",")
        }.joined(separator: "\n")
        let csv = header + rows
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("customers-export.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            AppLog.ui.error("CustomerCSVExporter write failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

#endif
