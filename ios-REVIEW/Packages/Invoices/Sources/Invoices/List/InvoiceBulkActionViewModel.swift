import Foundation
import Observation
import Core
import Networking

// §7.1 Bulk select + bulk action
// Supported actions: send_reminder, export, void, delete
// Server: POST /api/v1/invoices/bulk-action

@MainActor
@Observable
public final class InvoiceBulkActionViewModel {

    public enum State: Sendable, Equatable {
        case idle
        case submitting
        case success(processed: Int, failed: Int)
        case failed(String)
    }

    public private(set) var state: State = .idle

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func perform(action: String, ids: [Int64]) async {
        guard !ids.isEmpty else { return }
        guard case .idle = state else { return }
        state = .submitting
        do {
            let body = InvoiceBulkActionRequest(ids: ids, action: action)
            let response = try await api.invoiceBulkAction(body)
            state = .success(processed: response.processed, failed: response.failed)
        } catch {
            AppLog.ui.error("Bulk action '\(action)' failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    public func reset() {
        state = .idle
    }
}

// MARK: - CSV export helper (§7.1 Export CSV)

public enum InvoiceCSVExporter {
    /// Produces RFC-4180 CSV bytes from a list of `InvoiceSummary`.
    public static func csv(from invoices: [InvoiceSummary]) -> Data {
        var rows: [String] = ["ID,Customer,Total,Paid,Due,Status,Issued,DueOn"]
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.minimumFractionDigits = 2
        fmt.maximumFractionDigits = 2

        for inv in invoices {
            let total  = fmt.string(from: NSNumber(value: inv.total ?? 0)) ?? "0.00"
            let paid   = fmt.string(from: NSNumber(value: inv.amountPaid ?? 0)) ?? "0.00"
            let due    = fmt.string(from: NSNumber(value: inv.amountDue ?? 0)) ?? "0.00"
            let status = inv.status ?? ""
            let issued = inv.createdAt.map { String($0.prefix(10)) } ?? ""
            let dueOn  = inv.dueOn.map { String($0.prefix(10)) } ?? ""
            let row = [
                inv.displayId,
                escapeCSV(inv.customerName),
                total, paid, due,
                escapeCSV(status),
                issued, dueOn
            ].joined(separator: ",")
            rows.append(row)
        }
        return rows.joined(separator: "\n").data(using: .utf8) ?? Data()
    }

    private static func escapeCSV(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}
